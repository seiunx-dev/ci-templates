#!/usr/bin/env python3
"""Unit tests for the "Build scanner arguments" step of sonar.yml.

The step's `run:` script is taken from the workflow file itself and executed in a temporary
directory (the checkout) with the env the workflow passes, so what is tested is what runs.

    python3 tests/sonar_args_test.py
"""
import os
import pathlib
import shlex
import subprocess
import sys
import tempfile
import textwrap
import unittest

import yaml

ROOT = pathlib.Path(__file__).resolve().parent.parent
WORKFLOW = ROOT / ".github" / "workflows" / "sonar.yml"
MC = "sonar.issue.ignore.multicriteria"
PIN = "ciTemplatesPins"


def step_script() -> str:
    doc = yaml.safe_load(WORKFLOW.read_text())
    for step in doc["jobs"]["scan"]["steps"]:
        if step.get("id") == "args":
            assert step.get("shell", "").startswith("python3"), step.get("shell")
            return step["run"]
    raise AssertionError("no step with id 'args' in sonar.yml")


SCRIPT = step_script()


def run(files=None, extra="", version="", auto="true", ignore="true"):
    """Run the step; return its arguments as a dict (-Dkey=value) plus the raw list."""
    with tempfile.TemporaryDirectory() as tmp:
        tmp = pathlib.Path(tmp)
        for name, content in (files or {}).items():
            path = tmp / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(textwrap.dedent(content))
        out = tmp / "github_output"
        env = dict(os.environ, EXTRA=extra, VERSION=version, AUTO=auto, IGNORE_PINS=ignore, GITHUB_OUTPUT=str(out))
        proc = subprocess.run([sys.executable, "-c", SCRIPT], cwd=tmp, env=env, capture_output=True, text=True)
        if proc.returncode:
            raise AssertionError(f"step failed:\n{proc.stdout}\n{proc.stderr}")
        line = out.read_text()
    assert line.startswith("args=") and line.endswith("\n") and line.count("\n") == 1, line
    argv = shlex.split(line[len("args="):])
    props = {}
    for a in argv:
        if a.startswith("-D"):
            k, _, v = a[2:].partition("=")
            assert k not in props, f"duplicate -D{k} in {argv}"
            props[k] = v
    return props, argv


class TemplatePins(unittest.TestCase):
    def assert_pin_rule(self, props):
        self.assertEqual(props[f"{MC}.{PIN}.ruleKey"], "githubactions:S7637")
        self.assertEqual(props[f"{MC}.{PIN}.resourceKey"], ".github/workflows/**")

    def test_no_properties_file(self):
        props, _ = run()
        self.assertEqual(props[MC], PIN)
        self.assert_pin_rule(props)

    def test_merges_ids_from_properties(self):
        props, _ = run({"sonar-project.properties": """\
            sonar.projectKey=x
            # sonar.issue.ignore.multicriteria=commented
            sonar.issue.ignore.multicriteria=e1,e2
            sonar.issue.ignore.multicriteria.e1.ruleKey=rust:S1
            sonar.issue.ignore.multicriteria.e1.resourceKey=src/**
            """})
        self.assertEqual(props[MC], f"e1,e2,{PIN}")
        self.assert_pin_rule(props)
        # the repo's own per-id keys stay in the properties file, untouched
        self.assertNotIn(f"{MC}.e1.ruleKey", props)

    def test_properties_syntax_variants(self):
        props, _ = run({"sonar-project.properties": """\
            sonar.issue.ignore.multicriteria : a1 , \\
                a2,\\
              a3
            """})
        self.assertEqual(props[MC], f"a1,a2,a3,{PIN}")

    def test_blank_separator_and_last_definition_wins(self):
        props, _ = run({"sonar-project.properties": """\
            sonar.issue.ignore.multicriteria old
            sonar.issue.ignore.multicriteria   new1,new2
            """})
        self.assertEqual(props[MC], f"new1,new2,{PIN}")

    def test_id_already_listed_is_not_duplicated(self):
        props, _ = run({"sonar-project.properties": f"{MC}={PIN},e1\n"})
        self.assertEqual(props[MC], f"{PIN},e1")

    def test_merges_ids_from_args_and_drops_the_original(self):
        props, argv = run(
            {"sonar-project.properties": f"{MC}=e1\n"},
            extra=f"-Dsonar.qualitygate.wait=true -D{MC}=x1,e1",
        )
        self.assertEqual(props[MC], f"e1,x1,{PIN}")
        self.assertEqual(props["sonar.qualitygate.wait"], "true")
        self.assertEqual(sum(a.startswith(f"-D{MC}=") for a in argv), 1)

    def test_project_settings_from_args(self):
        props, _ = run(
            {"sonar-project.properties": f"{MC}=wrong\n", "cfg/sonar.properties": f"{MC}=s1\n"},
            extra="-Dproject.settings=cfg/sonar.properties",
        )
        self.assertEqual(props[MC], f"s1,{PIN}")
        self.assertEqual(props["project.settings"], "cfg/sonar.properties")

    def test_opt_out(self):
        props, _ = run({"sonar-project.properties": f"{MC}=e1\n"}, ignore="false")
        self.assertNotIn(MC, props)
        self.assertNotIn(f"{MC}.{PIN}.ruleKey", props)


class ProjectVersion(unittest.TestCase):
    def test_empty_is_not_passed(self):
        props, _ = run({"Cargo.toml": '[package]\nname = "x"\nversion = "1.2.3"\n'})
        self.assertNotIn("sonar.projectVersion", props)

    def test_explicit(self):
        props, _ = run(version="9.9.9")
        self.assertEqual(props["sonar.projectVersion"], "9.9.9")

    def test_auto_cargo_package(self):
        props, _ = run({"Cargo.toml": '[package]\nname = "x"\nversion = "6.27.1"\n'}, version="auto")
        self.assertEqual(props["sonar.projectVersion"], "6.27.1")

    def test_auto_cargo_workspace(self):
        props, _ = run({"Cargo.toml": """\
            [workspace]
            members = ["a"]
            [workspace.package]
            version = "2.0.0"
            [package]
            name = "x"
            version.workspace = true
            """}, version="auto")
        self.assertEqual(props["sonar.projectVersion"], "2.0.0")

    def test_auto_package_json_and_pyproject(self):
        props, _ = run({"package.json": '{"name": "x", "version": "0.4.0"}'}, version="auto")
        self.assertEqual(props["sonar.projectVersion"], "0.4.0")
        props, _ = run({"pyproject.toml": '[project]\nname = "x"\nversion = "3.1.0"\n'}, version="auto")
        self.assertEqual(props["sonar.projectVersion"], "3.1.0")

    def test_auto_without_manifest(self):
        props, _ = run(version="auto")
        self.assertNotIn("sonar.projectVersion", props)


class ReportPaths(unittest.TestCase):
    def test_only_downloaded_files(self):
        props, _ = run({"coverage/lcov-rust.info": "x", "coverage/python.xml": "x"})
        self.assertEqual(props["sonar.rust.lcov.reportPaths"], "coverage/lcov-rust.info")
        self.assertEqual(props["sonar.python.coverage.reportPaths"], "coverage/python.xml")
        self.assertNotIn("sonar.go.coverage.reportPaths", props)

    def test_opt_out(self):
        props, _ = run({"coverage/go.out": "x"}, auto="false")
        self.assertNotIn("sonar.go.coverage.reportPaths", props)

    def test_quoted_extra_args_are_kept_verbatim(self):
        _, argv = run(extra='-Dsonar.exclusions="a b/**" -Dsonar.qualitygate.wait=true')
        self.assertIn("-Dsonar.exclusions=a b/**", argv)


if __name__ == "__main__":
    unittest.main(verbosity=2)
