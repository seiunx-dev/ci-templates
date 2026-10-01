#!/usr/bin/env bash
# Runs the "Move tags" step of docker-retag.yml against stubbed `docker` and `gh` commands to
# cover the ordering guard (tag holds an older / newer / no commit, a concurrent run of an older
# commit overwriting the tag right after this write, check-ancestry off). The registry path
# itself is covered by the docker-push jobs of self-test.yml.
#
#   bash tests/docker_retag_test.sh
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

python3 - "$root/.github/workflows/docker-retag.yml" "$work/step.sh" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
step = next(s for s in doc["jobs"]["retag"]["steps"] if s.get("id") == "retag")
open(sys.argv[2], "w").write(step["run"].replace("sleep 10", "sleep 0"))
PY

mkdir "$work/bin"
# Registry stub: $STATE holds the commit the :main tag's image was built from (empty = no tag).
# With RACE set, the first write is immediately overwritten by a run of the commit "older".
cat > "$work/bin/docker" <<'SH'
#!/usr/bin/env bash
case "$*" in
  *"imagetools inspect"*":main --format"*)
    r=$(cat "$STATE"); [ -n "$r" ] || exit 1
    echo "{\"linux/amd64\":{\"config\":{\"Labels\":{\"org.opencontainers.image.revision\":\"$r\"}}}}" ;;
  *"imagetools inspect"*) exit 0 ;;
  *"imagetools create"*)
    echo "$*" >> "$STATE.writes"
    if [ -n "${RACE:-}" ] && [ ! -e "$STATE.raced" ]; then : > "$STATE.raced"; echo older > "$STATE"
    else echo "$GITHUB_SHA" > "$STATE"; fi ;;
esac
SH
# compare API stub: "older" and "base" are ancestors of "cur", "newer" descends from it.
cat > "$work/bin/gh" <<'SH'
#!/usr/bin/env bash
case "$*" in
  *"compare/older...cur"*|*"compare/base...cur"*) echo ahead ;;
  *"compare/newer...cur"*) echo behind ;;
  *) exit 1 ;;
esac
SH
chmod +x "$work/bin/"*

fails=0
# scenario <name> <start commit> <race> <check> <expected final commit> <expected writes>
scenario() {
  local state="$work/$1"
  echo "$2" > "$state"; : > "$state.writes"; : > "$work/out"
  STATE=$state RACE=$3 CHECK=$4 PATH="$work/bin:$PATH" GITHUB_OUTPUT="$work/out" \
    GITHUB_SHA=cur GITHUB_REPOSITORY=o/r IMAGE=ghcr.io/o/r DIGEST=sha256:d TAGS=$'  main \n' \
    bash -euo pipefail "$work/step.sh" > "$work/log" 2>&1 || { echo "FAIL $1: step failed"; cat "$work/log"; fails=$((fails + 1)); return; }
  local final writes; final=$(cat "$state"); writes=$(wc -l < "$state.writes" | tr -d ' ')
  if [ "$final" = "$5" ] && [ "$writes" = "$6" ]; then
    echo "ok   $1 (final=$final writes=$writes)"
  else
    echo "FAIL $1: final=$final writes=$writes, expected final=$5 writes=$6"; cat "$work/log"; fails=$((fails + 1))
  fi
  grep -q -- "--prefer-index=false --tag ghcr.io/o/r:main ghcr.io/o/r@sha256:d" "$state.writes" || [ "$6" = 0 ] \
    || { echo "FAIL $1: unexpected create arguments"; cat "$state.writes"; fails=$((fails + 1)); }
}

scenario older-tag      base  ""  true  cur   1
scenario new-tag        ""    ""  true  cur   1
scenario newer-tag      newer ""  true  newer 0
scenario same-commit    cur   ""  true  cur   0
scenario race           base  1   true  cur   2
scenario no-check       newer ""  false cur   1
scenario unknown-order  other ""  true  cur   1

[ "$fails" = 0 ] || { echo "$fails scenario(s) failed"; exit 1; }
echo "all docker-retag scenarios passed"
