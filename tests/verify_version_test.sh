#!/usr/bin/env bash
# Runs the step of actions/verify-version against a fixture Cargo.toml for each event / ref
# combination that matters: only a tag push sets is-tag=true (and must match the manifest);
# workflow_dispatch on a tag ref, on a branch, and a branch push are dry runs.
#
#   bash tests/verify_version_test.sh
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

python3 - "$root/actions/verify-version/action.yml" "$work/step.sh" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
step = next(s for s in doc["runs"]["steps"] if s.get("id") == "v")
open(sys.argv[2], "w").write(step["run"])
PY
printf '[package]\nname = "x"\nversion = "1.2.3"\n' > "$work/Cargo.toml"

fail=0
# run EVENT REF_TYPE REF_NAME EXPECT_EXIT EXPECT_IS_TAG EXPECT_TAG
run() {
  local out="$work/out" rc=0
  : > "$out"
  (cd "$work" && GITHUB_EVENT_NAME=$1 GITHUB_REF_TYPE=$2 GITHUB_REF_NAME=$3 GITHUB_SHA=0123456789abcdef \
    GITHUB_OUTPUT="$out" SOURCE=cargo MANIFEST="" EXTRA="" PREFIX=v bash -e step.sh >/dev/null 2>&1) || rc=$?
  local is_tag tag
  is_tag=$(sed -n 's/^is-tag=//p' "$out"); tag=$(sed -n 's/^tag=//p' "$out")
  if [ "$rc" != "$4" ] || { [ "$rc" = 0 ] && { [ "$is_tag" != "$5" ] || [ "$tag" != "$6" ]; }; }; then
    echo "FAIL: $1 $2 $3 -> exit=$rc is-tag=$is_tag tag=$tag (want exit=$4 is-tag=$5 tag=$6)"; fail=1
  else
    echo "ok:   $1 $2 $3 -> exit=$rc is-tag=${is_tag:--} tag=${tag:--}"
  fi
}
run push              tag    v1.2.3 0 true  v1.2.3
run push              tag    v9.9.9 1 ""    ""
run workflow_dispatch tag    v1.2.3 0 false ""
run workflow_dispatch tag    v9.9.9 0 false ""
run workflow_dispatch branch main   0 false ""
run push              branch main   0 false ""
run push              tag    other  0 false ""
exit "$fail"
