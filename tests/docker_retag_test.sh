#!/usr/bin/env bash
# Runs the "Move tags" step of docker-retag.yml against stubbed `docker` and `gh` commands to
# cover the ordering guard (tag holds an older / newer / no commit, a concurrent run of an older
# commit overwriting the tag right after this write, once or on every write, check-ancestry off,
# the recheck-delay value and no wait after the final write). The registry path
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
open(sys.argv[2], "w").write(step["run"])
PY

mkdir "$work/bin"
# Registry stub: $STATE holds the commit the :main tag's image was built from (empty = no tag).
# With RACE=n, the first n writes are immediately overwritten by a run of the commit "older".
cat > "$work/bin/docker" <<'SH'
#!/usr/bin/env bash
case "$*" in
  *"imagetools inspect"*":main --format"*)
    r=$(cat "$STATE"); [ -n "$r" ] || exit 1
    echo "{\"linux/amd64\":{\"config\":{\"Labels\":{\"org.opencontainers.image.revision\":\"$r\"}}}}" ;;
  *"imagetools inspect"*) exit 0 ;;
  *"imagetools create"*)
    echo "$*" >> "$STATE.writes"
    raced=$(cat "$STATE.raced" 2> /dev/null || echo 0)
    if [ "$raced" -lt "${RACE:-0}" ]; then echo $((raced + 1)) > "$STATE.raced"; echo older > "$STATE"
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
# sleep stub: records the recheck waits instead of waiting.
cat > "$work/bin/sleep" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$STATE.sleeps"
SH
chmod +x "$work/bin/"*

fails=0
# scenario <name> <start commit> <race> <check> <expected final commit> <expected writes>
#          [<expected sleeps, joined by ,> [<recheck-delay>]]
scenario() {
  local state="$work/$1"
  echo "$2" > "$state"; : > "$state.writes"; : > "$state.sleeps"; : > "$work/out"
  STATE=$state RACE=$3 CHECK=$4 DELAY=${8:-10} PATH="$work/bin:$PATH" GITHUB_OUTPUT="$work/out" \
    GITHUB_SHA=cur GITHUB_REPOSITORY=o/r IMAGE=ghcr.io/o/r DIGEST=sha256:d TAGS=$'  main \n' \
    bash -euo pipefail "$work/step.sh" > "$work/log" 2>&1 || { echo "FAIL $1: step failed"; cat "$work/log"; fails=$((fails + 1)); return; }
  local final writes sleeps; final=$(cat "$state"); writes=$(wc -l < "$state.writes" | tr -d ' ')
  sleeps=$(tr '\n' ',' < "$state.sleeps"); sleeps=${sleeps%,}
  if [ "$final" = "$5" ] && [ "$writes" = "$6" ] && { [ -z "${7+x}" ] || [ "$sleeps" = "$7" ]; }; then
    echo "ok   $1 (final=$final writes=$writes sleeps=[$sleeps])"
  else
    echo "FAIL $1: final=$final writes=$writes sleeps=[$sleeps], expected final=$5 writes=$6 sleeps=[${7-any}]"
    cat "$work/log"; fails=$((fails + 1))
  fi
  grep -q -- "--prefer-index=false --tag ghcr.io/o/r:main ghcr.io/o/r@sha256:d" "$state.writes" || [ "$6" = 0 ] \
    || { echo "FAIL $1: unexpected create arguments"; cat "$state.writes"; fails=$((fails + 1)); }
}

scenario older-tag      base  ""  true  cur   1 "10"
scenario new-tag        ""    ""  true  cur   1 "10"
scenario newer-tag      newer ""  true  newer 0 ""
scenario same-commit    cur   ""  true  cur   0 ""
scenario race           base  1   true  cur   2 "10,10"
scenario race-twice     base  2   true  cur   3 "10,10"   # no wait after the third (final) write
scenario race-always    base  3   true  older 3 "10,10"   # documented limit: three writes at most
scenario no-check       newer ""  false cur   1 ""
scenario unknown-order  other ""  true  cur   1 "10"
scenario short-delay    base  1   true  cur   2 "3,3" 3

# recheck-delay must be a whole number of seconds.
if DELAY=2.5 CHECK=true STATE=$work/x GITHUB_SHA=cur IMAGE=ghcr.io/o/r TAGS=main PATH="$work/bin:$PATH" \
  GITHUB_OUTPUT="$work/out" bash -euo pipefail "$work/step.sh" > "$work/log" 2>&1; then
  echo "FAIL bad-delay: accepted 2.5"; fails=$((fails + 1))
elif grep -q "recheck-delay must be a whole number" "$work/log"; then
  echo "ok   bad-delay"
else
  echo "FAIL bad-delay: failed for another reason"; cat "$work/log"; fails=$((fails + 1))
fi

[ "$fails" = 0 ] || { echo "$fails scenario(s) failed"; exit 1; }
echo "all docker-retag scenarios passed"
