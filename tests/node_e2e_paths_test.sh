#!/usr/bin/env bash
# Runs the "Changed paths" step of node-ci.yml (e2e-paths) in throwaway git repositories:
# a PR merge commit checked out with fetch-depth 2 (a match, no match, a rename out of the
# listed paths), a multi-commit push whose `before` has to be fetched, and the fail-open
# cases (new branch, unknown `before`, other events).
#
#   bash tests/node_e2e_paths_test.sh
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

python3 - "$root/.github/workflows/node-ci.yml" "$work/step.sh" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
jobs = doc["jobs"]
assert jobs["e2e"]["steps"] == jobs["e2e-parallel"]["steps"], "e2e variants must share their steps"
step = next(s for s in jobs["e2e"]["steps"] if s.get("id") == "paths")
open(sys.argv[2], "w").write(step["run"])
PY

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
export GIT_CONFIG_NOSYSTEM=1 HOME="$work/home"; mkdir -p "$HOME"
g() { git -c init.defaultBranch=main -c advice.detachedHead=false "$@"; }
commit() { # commit <repo> <message> <file>...
  local r="$1" m="$2"; shift 2
  for f in "$@"; do mkdir -p "$r/$(dirname "$f")"; echo "$m" >> "$r/$f"; done
  g -C "$r" add -A && g -C "$r" commit -qm "$m"
}

# Upstream history:  A (web + docs) -> B (web) -> C (docs); a PR branch off C that renames
# a web file; a PR branch off C that changes docs only.
up="$work/up"; g init -q "$up"
commit "$up" A web/app.ts docs/readme.md
A=$(g -C "$up" rev-parse HEAD)
commit "$up" B web/app.ts
B=$(g -C "$up" rev-parse HEAD)
commit "$up" C docs/readme.md
C=$(g -C "$up" rev-parse HEAD)
# the merge commits stay reachable from their own branches, as refs/pull/N/merge does
g -C "$up" checkout -qb pr-docs; commit "$up" D docs/guide.md
g -C "$up" checkout -qb m-docs "$C"; g -C "$up" merge -q --no-ff -m merge-docs pr-docs
MERGE_DOCS=$(g -C "$up" rev-parse HEAD)
g -C "$up" checkout -qb pr-rename "$C"; mkdir -p "$up/src"; g -C "$up" mv web/app.ts src/app.ts; g -C "$up" commit -qm rename
g -C "$up" checkout -qb m-rename "$C"; g -C "$up" merge -q --no-ff -m merge-rename pr-rename
MERGE_RENAME=$(g -C "$up" rev-parse HEAD)
g -C "$up" checkout -q main

fails=0
# scenario <name> <event> <checkout sha> <depth> <before> <patterns> <expected run> [<expected log line>]
scenario() {
  local ws="$work/ws-$1" out="$work/out-$1"
  g init -q "$ws"; g -C "$ws" remote add origin "file://$up"
  g -C "$ws" fetch -q --no-tags --depth="$4" origin "$3"; g -C "$ws" checkout -q FETCH_HEAD
  : > "$out"
  (cd "$ws" && GITHUB_EVENT_NAME="$2" GITHUB_OUTPUT="$out" GITHUB_SERVER_URL=https://github.invalid \
    BEFORE="$5" PATTERNS="$6" TOKEN=dummy bash -e "$work/step.sh") > "$work/log-$1" 2>&1 || { echo "FAIL $1: step exited non-zero"; cat "$work/log-$1"; fails=$((fails + 1)); return; }
  got=$(sed -n 's/^run=//p' "$out")
  if [ -n "${8:-}" ] && ! grep -qF -- "$8" "$work/log-$1"; then
    echo "FAIL $1: log lacks '$8'"; cat "$work/log-$1"; fails=$((fails + 1))
  elif [ "$got" = "$7" ]; then echo "ok   $1 (run=$got)"; else echo "FAIL $1: run=$got, want $7"; cat "$work/log-$1"; fails=$((fails + 1)); fi
}

web=$'web/**\n.github/workflows/ci.yml'
scenario pr-match-none pull_request "$MERGE_DOCS" 2 "" "$web" false
scenario pr-match-docs pull_request "$MERGE_DOCS" 2 "" $'  \n  docs/**  \n' true "docs/guide.md matches docs/**"
scenario pr-rename-out pull_request "$MERGE_RENAME" 2 "" "$web" true "web/app.ts matches web/**"
scenario pr-not-merge pull_request "$C" 2 "" "$web" true "no base commit"
scenario push-multi push "$C" 1 "$A" "$web" true "web/app.ts matches web/**"
scenario push-last-only push "$C" 1 "$B" "$web" false
scenario push-new-branch push "$C" 1 0000000000000000000000000000000000000000 "$web" true "no base commit"
scenario push-unknown push "$C" 1 1111111111111111111111111111111111111111 "$web" true "no base commit"
scenario dispatch workflow_dispatch "$C" 1 "" "$web" true "no base commit"
scenario star-crosses-slash pull_request "$MERGE_DOCS" 2 "" "docs*" true "docs/guide.md matches docs*"

[ "$fails" = 0 ] || { echo "$fails scenario(s) failed"; exit 1; }
echo "all e2e-paths scenarios passed"
