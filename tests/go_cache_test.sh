#!/usr/bin/env bash
# Runs the "Mark Go build cache" / "Trim Go build cache" and "Merge repeated coverage blocks"
# steps of go-ci.yml with a real Go toolchain on a throwaway module:
# - entries the run used stay, so the next build of the same packages compiles nothing, even
#   though the cache was written seconds earlier (Go only refreshes mtimes older than an hour);
# - entries the run did not use are deleted, and a cached `go run` executable that was used stays;
# - the merged -coverpkg profile is smaller, `go tool cover -func` prints exactly the same, and
#   the set of covered lines (Sonar's rule: any block on the line with a count > 0) is the same,
#   in atomic and in set mode.
# Lint and Test must carry the same Mark / Trim scripts.
#
#   bash tests/go_cache_test.sh
# shellcheck disable=SC2016,SC2329 # check() evals its single-quoted conditions
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d); trap 'chmod -R u+w "$work" 2>/dev/null; rm -rf "$work"' EXIT

python3 - "$root/.github/workflows/go-ci.yml" "$work" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
def step(job, name):
    return next(s for s in doc["jobs"][job]["steps"] if s.get("name") == name)["run"]
for name, out in (("Mark Go build cache", "mark.sh"), ("Trim Go build cache", "trim.sh")):
    if step("lint", name) != step("test", name):
        sys.exit(f"lint and test differ in step {name!r}")
    open(f"{sys.argv[2]}/{out}", "w").write(step("lint", name))
open(f"{sys.argv[2]}/merge.sh", "w").write(step("test", "Merge repeated coverage blocks"))
PY

fail=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
compiles() { go build -x "$@" 2>&1 | grep -cE '/compile( |$)' || true; }

mod="$work/mod"
mkdir -p "$mod/a" "$mod/b" "$mod/cmd/used" "$mod/cmd/unused" "$work/tmp" "$work/coverage"
printf 'module example.com/trim\n\ngo 1.21\n' > "$mod/go.mod"
printf 'package a\n\nimport "strings"\n\nfunc A(s string) string {\n\tif s == "" {\n\t\treturn "empty"\n\t}\n\treturn strings.ToUpper(s)\n}\n' > "$mod/a/a.go"
printf 'package a\n\nimport "testing"\n\nfunc TestA(t *testing.T) {\n\tif A("x") != "X" {\n\t\tt.Fatal()\n\t}\n}\n' > "$mod/a/a_test.go"
printf 'package b\n\nimport (\n\t"encoding/json"\n\n\t"example.com/trim/a"\n)\n\nfunc B(v any) string {\n\tout, err := json.Marshal(v)\n\tif err != nil {\n\t\treturn a.A("")\n\t}\n\treturn a.A(string(out))\n}\n' > "$mod/b/b.go"
printf 'package b\n\nimport "testing"\n\nfunc TestB(t *testing.T) {\n\tif B(1) != "1" {\n\t\tt.Fatal()\n\t}\n}\n' > "$mod/b/b_test.go"
printf 'package main\n\nimport "fmt"\n\nfunc main() { fmt.Println("used") }\n' > "$mod/cmd/used/main.go"
printf 'package main\n\nimport "net/http"\n\nfunc main() { _ = http.StatusOK }\n' > "$mod/cmd/unused/main.go"

export GOCACHE="$work/gocache" GOFLAGS=-mod=mod GOTOOLCHAIN=local RUNNER_TEMP="$work/tmp" GITHUB_WORKSPACE="$work"
export DIRS="$GOCACHE"$'\n'"$work/staticcheck-absent"
cd "$mod"

# --- Mark / Trim -----------------------------------------------------------------------------
go build ./... && go run ./cmd/used >/dev/null && go run ./cmd/unused
exe_before=$(find "$GOCACHE" -mindepth 2 -maxdepth 2 -type d -name '*-d' | wc -l | tr -d ' ')
size_before=$(du -sk "$GOCACHE" | cut -f1)
bash "$work/mark.sh"
go build ./a && go run ./cmd/used >/dev/null # this run's working set: package a, its deps, cmd/used
bash "$work/trim.sh"
size_after=$(du -sk "$GOCACHE" | cut -f1)
exe_after=$(find "$GOCACHE" -mindepth 2 -maxdepth 2 -type d -name '*-d' | wc -l | tr -d ' ')
echo "cache ${size_before} KiB -> ${size_after} KiB, cached executables ${exe_before} -> ${exe_after}"
check "the trim deleted unused entries" '[ "$size_after" -lt "$size_before" ]'
check "the used package and its deps are still cached (0 compiles)" '[ "$(compiles ./a)" = 0 ]'
check "the unused package was trimmed (it compiles again)" '[ "$(compiles ./b)" -gt 0 ]'
if [ "$exe_before" -gt 0 ]; then # Go >= 1.24 caches go run executables as <hash>-d directories
  check "the used go run executable stays, the unused one is gone" '[ "$exe_after" = 1 ]'
fi
check "files outside the <xx>/ entry dirs are kept" '[ -e "$GOCACHE/README" ]'

# A second cycle right away: entries written seconds ago (mtime < 1 h, so Go does not touch
# them on use) must survive because Mark ages them first.
go build ./b
bash "$work/mark.sh"
go build ./a ./b
bash "$work/trim.sh"
check "fresh entries used again survive a second cycle" '[ "$(compiles ./a ./b)" = 0 ]'

# --- coverage merge --------------------------------------------------------------------------
covered_lines() { # file:line of every line some block with count > 0 covers (Sonar's rule)
  awk 'NR > 1 && NF == 3 { split($1, p, ":"); split(p[2], r, ","); split(r[1], s, "."); split(r[2], e, ".")
         for (l = s[1]; l <= e[1]; l++) { k = p[1] ":" l; if ($3 > 0) c[k] = 1; else if (!(k in c)) c[k] = 0 } }
       END { for (k in c) print k, c[k] }' "$1" | LC_ALL=C sort
}
for mode in atomic set; do
  go test -covermode="$mode" -coverpkg=./... -coverprofile="$work/coverage/go.out" ./... >/dev/null
  cp "$work/coverage/go.out" "$work/orig.out"
  bash "$work/merge.sh" >/dev/null
  check "$mode: merged profile is smaller" '[ "$(wc -l < "$work/coverage/go.out")" -lt "$(wc -l < "$work/orig.out")" ]'
  check "$mode: no block appears twice" '[ -z "$(tail -n +2 "$work/coverage/go.out" | cut -d" " -f1 | sort | uniq -d)" ]'
  check "$mode: go tool cover -func is identical" \
    'diff <(go tool cover -func="$work/orig.out") <(go tool cover -func="$work/coverage/go.out") >/dev/null'
  check "$mode: covered line set is identical" \
    'diff <(covered_lines "$work/orig.out") <(covered_lines "$work/coverage/go.out") >/dev/null'
done
printf 'mode: atomic\nnot a coverage line\n' > "$work/coverage/go.out"
bash "$work/merge.sh" >/dev/null 2>&1
check "an unexpected line leaves the profile as it was" '[ "$(sed -n 2p "$work/coverage/go.out")" = "not a coverage line" ]'

exit "$fail"
