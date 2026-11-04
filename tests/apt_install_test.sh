#!/usr/bin/env bash
# Runs the step of actions/apt-install against a stubbed `apt-get` (and `sudo` / `sleep`) to cover
# the retry loop: a network phase that stalls past attempt-timeout is killed and retried, the
# unpack phase is never put under the limit, attempt-timeout: 0 means no limit, a bad value fails,
# and three failed attempts fail without a final back-off sleep. Needs GNU `timeout` on PATH.
#
#   bash tests/apt_install_test.sh
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
command -v timeout > /dev/null || { echo "GNU timeout is required"; exit 1; }

python3 - "$root/actions/apt-install/action.yml" "$work/step.sh" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
step = next(s for s in doc["runs"]["steps"] if s.get("name") == "Install apt packages")
open(sys.argv[2], "w").write(step["run"])
PY

mkdir "$work/bin"
real_sleep=$(command -v sleep)
# apt-get stub: logs "<phase> <attempt>" and, per $PLAN ("<phase>:<attempt>:<action>" words),
# stalls (stall = sleeps 30 s) or fails (fail) in a given phase and attempt.
cat > "$work/bin/apt-get" <<SH
#!/usr/bin/env bash
case " \$* " in
  *" update "*) phase=update ;;
  *" --download-only "*) phase=download ;;
  *) phase=install ;;
esac
case " \$* " in *" -o Acquire::http::Timeout=20 "*) ;; *) echo "missing Acquire options: \$*" >&2; exit 9 ;; esac
n=\$(grep -c "^\$phase " "\$LOG" || true); n=\$((n + 1))
echo "\$phase \$n" >> "\$LOG"
for p in \$PLAN; do
  case "\$p" in
    "\$phase:\$n:stall") exec $real_sleep 30 ;;
    "\$phase:\$n:slow") exec $real_sleep 4 ;;
    "\$phase:\$n:fail") exit 100 ;;
  esac
done
exit 0
SH
cat > "$work/bin/sudo" <<'SH'
#!/usr/bin/env bash
exec "$@"
SH
cat > "$work/bin/sleep" <<'SH'
#!/usr/bin/env bash
echo "sleep $*" >> "$LOG"
SH
chmod +x "$work/bin/"*

fails=0
# scenario <name> <attempt-timeout> <plan> <expected exit> <expected log, phases joined by ,>
scenario() {
  local log="$work/$1.log" rc=0
  : > "$log"
  LOG=$log PLAN=$3 ATTEMPT_TIMEOUT=$2 PACKAGES=$'pkg-a\npkg-b' PATH="$work/bin:$PATH" \
    bash -euo pipefail "$work/step.sh" > "$work/out" 2>&1 || rc=$?
  local got; got=$(tr '\n' ',' < "$log"); got=${got%,}
  if [ "$rc" = "$4" ] && [ "$got" = "$5" ]; then
    echo "ok   $1"
  else
    echo "FAIL $1: exit=$rc log=[$got], expected exit=$4 log=[$5]"; cat "$work/out"; fails=$((fails + 1))
  fi
}

scenario plain          180 ""                             0 "update 1,download 1,install 1"
scenario update-stall   2   "update:1:stall"               0 "update 1,sleep 10,update 2,download 1,install 1"
scenario download-stall 2   "download:1:stall"             0 "update 1,download 1,sleep 10,update 2,download 2,install 1"
scenario unpack-unlimited 2 "install:1:slow"               0 "update 1,download 1,install 1"
scenario no-limit       0   "download:1:slow"              0 "update 1,download 1,install 1"
scenario fail-then-ok   180 "install:1:fail"               0 "update 1,download 1,install 1,sleep 10,update 2,download 2,install 2"
scenario all-fail       180 "update:1:fail update:2:fail update:3:fail" 1 "update 1,sleep 10,update 2,sleep 20,update 3"
scenario bad-timeout    3m  ""                             1 ""

# Empty package list: no apt call at all.
: > "$work/empty.log"
if LOG=$work/empty.log PLAN="" ATTEMPT_TIMEOUT=180 PACKAGES=$'\n' PATH="$work/bin:$PATH" \
  bash -euo pipefail "$work/step.sh" && [ ! -s "$work/empty.log" ]; then
  echo "ok   empty-list"
else
  echo "FAIL empty-list"; fails=$((fails + 1))
fi

[ "$fails" = 0 ] || { echo "$fails scenario(s) failed"; exit 1; }
echo "all apt-install scenarios passed"
