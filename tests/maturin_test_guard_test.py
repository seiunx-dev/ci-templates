#!/usr/bin/env python3
"""The smoke-test guard of maturin-wheels.yml, and loose boolean comparisons in general.

A target that omits `test` has `matrix.t.test == null`, and GitHub expressions compare null
and false as equal (both coerce to 0). `matrix.t.test != false` therefore skipped the smoke
test for every target without an explicit `"test": true`. The guard is now
`toJSON(matrix.t.test) != 'false'`, which is false only for a literal false.

This test checks that
- both gated steps of maturin-wheels.yml use that guard;
- the `maturin-test-guard` job of self-test.yml, which evaluates the guard on GitHub over
  targets with `test` omitted / false / true, uses the very same expression;
- no workflow or action compares an expression against a bare `true` / `false` literal, which
  has the same null pitfall for any optional matrix key or untyped value.

    python3 tests/maturin_test_guard_test.py
"""
import pathlib
import re
import unittest

import yaml

ROOT = pathlib.Path(__file__).resolve().parent.parent
WORKFLOWS = ROOT / ".github" / "workflows"
GUARD = "toJSON(matrix.t.test) != 'false'"
GATED_STEPS = ("Smoke test", "Wheel tests")

EXPR = re.compile(r"\$\{\{(.*?)\}\}", re.S)
LOOSE_BOOL = re.compile(r"(?:[!=]=\s*(?:true|false)\b)|(?:\b(?:true|false)\s*[!=]=)")


def load(path):
    return yaml.safe_load(path.read_text())


def expressions(node):
    """Yield every expression in a workflow / action document: `if:` values (with or without
    ${{ }}) and every ${{ }} inside any other string."""
    if isinstance(node, dict):
        for key, value in node.items():
            if key == "if" and isinstance(value, str):
                found = EXPR.findall(value)
                yield from (found if found else [value])
            else:
                yield from expressions(value)
    elif isinstance(node, list):
        for item in node:
            yield from expressions(item)
    elif isinstance(node, str):
        yield from EXPR.findall(node)


def files():
    yield from sorted(WORKFLOWS.glob("*.yml"))
    yield from sorted((ROOT / "actions").glob("*/action.yml"))


class MaturinGuard(unittest.TestCase):
    def test_gated_steps_use_the_null_safe_guard(self):
        steps = load(WORKFLOWS / "maturin-wheels.yml")["jobs"]["wheels"]["steps"]
        by_name = {s.get("name"): s for s in steps}
        for name in GATED_STEPS:
            with self.subTest(step=name):
                cond = by_name[name]["if"]
                self.assertIn(GUARD, cond)
                self.assertEqual(cond.count("matrix.t.test"), 1, cond)

    def test_self_test_evaluates_the_same_guard(self):
        job = load(WORKFLOWS / "self-test.yml")["jobs"]["maturin-test-guard"]
        guard_steps = [s for s in job["steps"] if s.get("id") == "guard"]
        self.assertEqual(len(guard_steps), 1)
        self.assertEqual(guard_steps[0]["if"], GUARD)
        cases = {repr(t.get("test", "<omitted>")): t["expect"] for t in job["strategy"]["matrix"]["t"]}
        self.assertEqual(cases, {"'<omitted>'": "ran", "False": "skipped", "True": "ran"})
        ci_ok = load(WORKFLOWS / "self-test.yml")["jobs"]["ci-ok"]["needs"]
        self.assertIn("maturin-test-guard", ci_ok)

    def test_no_loose_boolean_comparisons(self):
        offenders = []
        for path in files():
            for expr in expressions(load(path)):
                if LOOSE_BOOL.search(expr):
                    offenders.append(f"{path.relative_to(ROOT)}: {expr.strip()}")
        self.assertEqual(offenders, [], "compare against a string, e.g. toJSON(x) != 'false'")

    def test_lint_catches_the_old_guard(self):
        old = {"steps": [{"if": "inputs.smoke-import != '' && matrix.t.test != false"},
                         {"run": "echo ${{ false == matrix.x }}"}]}
        self.assertEqual(sum(bool(LOOSE_BOOL.search(e)) for e in expressions(old)), 2)
        ok = {"steps": [{"if": GUARD}, {"run": '[ "$CHECK" != true ]'}]}
        self.assertFalse(any(LOOSE_BOOL.search(e) for e in expressions(ok)))


if __name__ == "__main__":
    unittest.main(verbosity=2)
