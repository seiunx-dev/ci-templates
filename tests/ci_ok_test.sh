#!/usr/bin/env bash
# Runs the step of actions/ci-ok against a stubbed `gh` (which prints this run's finished jobs as
# the step's --jq would, or fails like an API error) and a no-op `sleep`. CI OK must fail when a
# needed job failed or was cancelled, and also when needs looks green but a job of the run was
# cancelled (a reusable-workflow leg no runner picked up), timed out or failed. Skipped jobs pass.
#
#   bash tests/ci_ok_test.sh
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

python3 - "$root/actions/ci-ok/action.yml" "$work/step.sh" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
open(sys.argv[2], "w").write(doc["runs"]["steps"][0]["run"])
PY
mkdir -p "$work/bin"
# gh stub: the first $ERRORS calls fail, later ones print $JOBS (one "name<TAB>conclusion" per line).
cat > "$work/bin/gh" <<'SH'
#!/usr/bin/env bash
n=$(( $(cat "$CALLS" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$CALLS"
if [ "$n" -le "$ERRORS" ]; then echo "HTTP 403: Resource not accessible by integration" >&2; exit 1; fi
printf '%b' "$JOBS"
SH
printf '#!/bin/sh\nexit 0\n' > "$work/bin/sleep"
chmod +x "$work/bin/gh" "$work/bin/sleep"

ok='{"rust":{"result":"success","outputs":{}},"sonar":{"result":"skipped","outputs":{}}}'
green='Rust / Lint\tsuccess\nRust / Test\tsuccess\nRust / MSRV\tskipped\n'
fail=0
# run NAME EXPECT_EXIT EXPECT_CALLS NEEDS JOBS [API_ERRORS] [IGNORE]
run() {
  local name=$1 want_rc=$2 want_calls=$3 rc=0 calls
  rm -f "$work/calls"
  PATH="$work/bin:$PATH" CALLS="$work/calls" ERRORS="${6:-0}" JOBS="$5" NEEDS="$4" IGNORE="${7:-}" \
    GH_TOKEN=x GITHUB_REPOSITORY=o/r GITHUB_RUN_ID=1 bash "$work/step.sh" > "$work/log" 2>&1 || rc=$?
  calls=$(cat "$work/calls" 2>/dev/null || echo 0)
  if [ "$rc" != "$want_rc" ] || [ "$calls" != "$want_calls" ]; then
    echo "FAIL: $name -> exit=$rc calls=$calls (want exit=$want_rc calls=$want_calls)"; sed 's/^/      /' "$work/log"; fail=1
  else
    echo "ok:   $name -> exit=$rc calls=$calls"
  fi
}
run "all green, skipped passes"                0 1 "$ok" "$green"
run "no needs, no jobs"                        0 1 '{}' ""
run "needed job failed"                        1 1 '{"rust":{"result":"failure"}}' "$green"
run "needed job cancelled"                     1 1 '{"rust":{"result":"cancelled"}}' "$green"
run "needs green, a leg was cancelled"         1 1 "$ok" "${green}rust-ci on macOS / Test\tcancelled\n"
run "needs green, a leg timed out"             1 1 "$ok" "${green}Rust / Test (x)\ttimed_out\n"
run "needs green, a job failed"                1 1 "$ok" "${green}Docker / Build\tfailure\n"
run "startup failure"                          1 1 "$ok" "${green}Sonar / Scan\tstartup_failure\n"
run "neutral passes"                           0 1 "$ok" "${green}Sonar / Scan\tneutral\n"
run "ignore-jobs pattern"                      0 1 "$ok" "${green}rust-ci on macOS / Test\tcancelled\n" 0 $'  rust-ci on macOS / *  \nother'
run "ignore-jobs does not match"               1 1 "$ok" "${green}rust-ci on Windows / Test\tcancelled\n" 0 "rust-ci on macOS / *"
run "ignore-jobs never excuses a needed job"   1 1 '{"mac":{"result":"cancelled"}}' "rust-ci on macOS / Test\tcancelled\n" 0 "*"
run "API error retried"                        0 3 "$ok" "$green" 2
run "API error 3x fails (permission hint)"     1 3 "$ok" "$green" 3
grep -q "permissions: actions: read" "$work/log" || { echo "FAIL: no actions: read hint after API errors"; fail=1; }
run "needs is not JSON"                        1 0 'not json' "$green"
exit "$fail"
