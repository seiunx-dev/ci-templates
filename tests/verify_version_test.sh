#!/usr/bin/env bash
# Runs the step of actions/verify-version against a fixture Cargo.toml for each event / ref
# combination that matters: only a tag push sets is-tag=true (and must match the manifest);
# workflow_dispatch on a tag ref, on a branch, and a branch push are dry runs. The `go` source
# reads `Version = "..."` from a Go file and strips the tag prefix.
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
mkdir -p "$work/version" "$work/other"
printf 'package version\n\n// Overridden with -ldflags -X.\nvar (\n\tVersion   = "v2.0.0-rc3"\n\tCommit    = "unknown"\n)\n' > "$work/version/version.go"
printf 'package other\n\nconst Version string = "2.0.0-rc3"\n' > "$work/other/v.go"
printf 'package other\n\nvar Version = "dev"\n' > "$work/other/dev.go"

fail=0
# [SOURCE=.. MANIFEST=.. EXTRA=.. WANT_VERSION=..] run EVENT REF_TYPE REF_NAME EXPECT_EXIT EXPECT_IS_TAG EXPECT_TAG
run() {
  local out="$work/out" rc=0
  : > "$out"
  (cd "$work" && GITHUB_EVENT_NAME=$1 GITHUB_REF_TYPE=$2 GITHUB_REF_NAME=$3 GITHUB_SHA=0123456789abcdef \
    GITHUB_OUTPUT="$out" SOURCE="${SOURCE:-cargo}" MANIFEST="${MANIFEST:-}" EXTRA="${EXTRA:-}" PREFIX=v \
    bash -e step.sh >/dev/null 2>&1) || rc=$?
  local is_tag tag version
  is_tag=$(sed -n 's/^is-tag=//p' "$out"); tag=$(sed -n 's/^tag=//p' "$out"); version=$(sed -n 's/^version=//p' "$out")
  if [ "$rc" != "$4" ] || { [ "$rc" = 0 ] && { [ "$is_tag" != "$5" ] || [ "$tag" != "$6" ] ||
      { [ -n "${WANT_VERSION:-}" ] && [ "$version" != "$WANT_VERSION" ]; }; }; }; then
    echo "FAIL: ${SOURCE:-cargo} $1 $2 $3 -> exit=$rc is-tag=$is_tag tag=$tag version=$version (want exit=$4 is-tag=$5 tag=$6 version=${WANT_VERSION:-any})"; fail=1
  else
    echo "ok:   ${SOURCE:-cargo} $1 $2 $3 -> exit=$rc is-tag=${is_tag:--} tag=${tag:--} version=${version:--}"
  fi
}
run push              tag    v1.2.3 0 true  v1.2.3
run push              tag    v9.9.9 1 ""    ""
run workflow_dispatch tag    v1.2.3 0 false ""
run workflow_dispatch tag    v9.9.9 0 false ""
run workflow_dispatch branch main   0 false ""
run push              branch main   0 false ""
run push              tag    other  0 false ""
# go: var block with the prefix in the literal (default path version/version.go)
SOURCE=go WANT_VERSION=2.0.0-rc3 run push              tag    v2.0.0-rc3 0 true  v2.0.0-rc3
SOURCE=go                        run push              tag    v2.0.0     1 ""    ""
SOURCE=go WANT_VERSION=2.0.0-rc3 run workflow_dispatch branch main       0 false ""
# go: typed const without the prefix, as the primary and as an extra path
SOURCE=go MANIFEST=other/v.go WANT_VERSION=2.0.0-rc3 run push tag v2.0.0-rc3 0 true v2.0.0-rc3
SOURCE=go EXTRA=other/v.go WANT_VERSION=2.0.0-rc3 run push tag v2.0.0-rc3 0 true v2.0.0-rc3
SOURCE=go EXTRA=other/dev.go run push tag v2.0.0-rc3 1 "" ""
# none: the version comes from the tag only
SOURCE=none WANT_VERSION=3.1.4 run push tag v3.1.4 0 true v3.1.4
SOURCE=none WANT_VERSION=0.0.0-dev.0123456 run workflow_dispatch branch main 0 false ""
exit "$fail"
