#!/usr/bin/env bash
# Runs the step of actions/wait-for-checks against a stubbed `gh` (which replays one check-run
# state per call) and a no-op `sleep`. Only "completed success" may pass. With timeout-minutes 0
# (release-gate `wait-minutes: 0`) the step must look once and fail at once while the check is
# missing / queued / in progress, retrying only failed API calls (at most 3 times).
#
#   bash tests/wait_for_checks_test.sh
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

python3 - "$root/actions/wait-for-checks/action.yml" "$work/step.sh" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
open(sys.argv[2], "w").write(doc["runs"]["steps"][0]["run"])
PY
mkdir -p "$work/bin"
# gh stub: prints the next line of $STATES (the --jq result); "api-error" makes the call fail.
cat > "$work/bin/gh" <<'SH'
#!/usr/bin/env bash
n=$(( $(cat "$CALLS" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$CALLS"
line=$(sed -n "${n}p" "$STATES"); [ -n "$line" ] || line=$(tail -n1 "$STATES")
[ "$line" = api-error ] && exit 1
echo "$line"
SH
printf '#!/bin/sh\nexit 0\n' > "$work/bin/sleep"
chmod +x "$work/bin/gh" "$work/bin/sleep"

fail=0
# run NAME TIMEOUT EXPECT_EXIT EXPECT_CALLS STATE...
run() {
  local name=$1 timeout=$2 want_rc=$3 want_calls=$4 rc=0 calls; shift 4
  printf '%s\n' "$@" > "$work/states"; rm -f "$work/calls"
  PATH="$work/bin:$PATH" STATES="$work/states" CALLS="$work/calls" GH_TOKEN=x GITHUB_REPOSITORY=o/r \
    CHECK="CI OK" SHA=0123456789abcdef TIMEOUT="$timeout" bash "$work/step.sh" > "$work/log" 2>&1 || rc=$?
  calls=$(cat "$work/calls")
  if [ "$rc" != "$want_rc" ] || [ "$calls" != "$want_calls" ]; then
    echo "FAIL: $name -> exit=$rc calls=$calls (want exit=$want_rc calls=$want_calls)"; sed 's/^/      /' "$work/log"; fail=1
  else
    echo "ok:   $name -> exit=$rc calls=$calls"
  fi
}
run "check-once: already green"            0 0 1 "completed success"
run "check-once: still running fails now"  0 1 1 "in_progress null" "completed success"
run "check-once: queued fails now"         0 1 1 "queued null" "completed success"
run "check-once: no check run yet"         0 1 1 "missing" "completed success"
run "check-once: red"                      0 1 1 "completed failure"
run "check-once: cancelled"                0 1 1 "completed cancelled"
run "check-once: API error retried"        0 0 3 api-error api-error "completed success"
run "check-once: API error 4x gives up"    0 1 4 api-error api-error api-error api-error "completed success"
run "check-once: API error then running"   0 1 2 api-error "in_progress null" "completed success"
run "poll: waits until green"             30 0 3 "queued null" "in_progress null" "completed success"
run "poll: waits, then red"               30 1 2 "in_progress null" "completed failure"
run "poll: API error keeps waiting"       30 0 2 api-error "completed success"
grep -q 'timeout-minutes is 0' "$work/log" && { echo "FAIL: poll mode printed the check-once message"; fail=1; }
exit "$fail"
