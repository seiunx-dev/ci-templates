#!/usr/bin/env python3
"""Static checks for this template repo.

- every *.yml / *.yaml parses;
- every call of a reusable workflow of this repo passes only declared inputs/secrets,
  passes all required inputs, and uses literal values of the declared type;
- every use of a composite action of this repo passes only declared inputs;
- every normal job has timeout-minutes;
- every third-party action is pinned to a full commit SHA;
- with --clones DIR (DIR/<repo>/ = a checkout of each migrated repo): every script, Dockerfile
  or *.ref file a caller runs or references exists in that checkout or is shipped in
  <callers>/<owner>__<repo>/repo-files/ (actionlint cannot see a `run:` target that is missing).

Caller files outside this repo are checked too:
  python3 tools/check_callers.py path/to/repo            # its .github/workflows/*.yml
  python3 tools/check_callers.py ci.yml release.yml       # single files
  python3 tools/check_callers.py --callers DIR [--clones DIR]  # DIR/<owner>__<repo>/*.yml sets

Run from anywhere: python3 tools/check_callers.py [paths ...] [--callers DIR] [--clones DIR]
"""
import argparse
import pathlib
import re
import sys

import yaml

ROOT = pathlib.Path(__file__).resolve().parent.parent
SELF = "seiunx-dev/ci-templates"
errors: list[str] = []
cli = argparse.ArgumentParser()
cli.add_argument("paths", nargs="*", type=pathlib.Path, help="caller repos (their .github/workflows) or workflow files")
cli.add_argument("--callers", type=pathlib.Path, default=ROOT / "callers", help="directory of <owner>__<repo>/ caller sets")
cli.add_argument("--clones", type=pathlib.Path, help="directory with one checkout per repo (named like the repo); needs --callers")
args = cli.parse_args()


def load(path: pathlib.Path):
    try:
        return yaml.safe_load(path.read_text())
    except yaml.YAMLError as exc:
        errors.append(f"{path}: YAML error: {exc}")
        return None


def on_block(doc):
    return doc.get("on", doc.get(True)) if isinstance(doc, dict) else None


def yaml_files(root: pathlib.Path):
    return sorted(p for p in root.rglob("*") if p.suffix in (".yml", ".yaml") and p.is_file() and ".git" not in p.parts)


files = yaml_files(ROOT)
if args.callers.is_dir() and not args.callers.resolve().is_relative_to(ROOT):
    files += yaml_files(args.callers)
for extra in args.paths:
    if extra.is_dir():
        wf = extra / ".github" / "workflows"
        files += sorted(p for p in (wf if wf.is_dir() else extra).glob("*.y*ml") if p.is_file())
    elif extra.is_file():
        files.append(extra)
    else:
        errors.append(f"{extra}: no such file or directory")
files = sorted({p.resolve() for p in files})
docs = {p: load(p) for p in files}

workflows = {}
for p in (ROOT / ".github" / "workflows").glob("*.yml"):
    doc = docs.get(p.resolve())
    on = on_block(doc) or {}
    if isinstance(on, dict) and "workflow_call" in on:
        call = on["workflow_call"] or {}
        workflows[p.name] = {"inputs": call.get("inputs") or {}, "secrets": call.get("secrets") or {}}

actions = {}
for p in (ROOT / "actions").glob("*/action.yml"):
    doc = docs.get(p.resolve()) or {}
    actions[p.parent.name] = doc.get("inputs") or {}

EXPR = re.compile(r"\$\{\{.*\}\}", re.S)


def check_value(where, name, spec, value):
    if isinstance(value, str) and EXPR.search(value):
        return
    kind = spec.get("type", "string")
    ok = {
        "boolean": isinstance(value, bool),
        "number": isinstance(value, (int, float)) and not isinstance(value, bool),
        "string": isinstance(value, str),
    }[kind]
    if not ok:
        errors.append(f"{where}: input '{name}' expects {kind}, got {value!r}")


def check_uses_workflow(where, ref, job):
    m = re.match(rf"(?:{re.escape(SELF)}/|\./)\.github/workflows/([\w.-]+\.yml)(?:@.+)?$", ref)
    if not m:
        return
    name = m.group(1)
    if name not in workflows:
        errors.append(f"{where}: unknown reusable workflow {name}")
        return
    spec = workflows[name]
    given = job.get("with") or {}
    for k, v in given.items():
        if k not in spec["inputs"]:
            errors.append(f"{where}: {name} has no input '{k}'")
        else:
            check_value(where, k, spec["inputs"][k], v)
    for k, s in spec["inputs"].items():
        if (s or {}).get("required") and k not in given:
            errors.append(f"{where}: {name} requires input '{k}'")
    secrets = job.get("secrets")
    if isinstance(secrets, dict):
        for k in secrets:
            if k not in spec["secrets"]:
                errors.append(f"{where}: {name} declares no secret '{k}'")
    for bad in ("steps", "runs-on", "timeout-minutes", "container", "services"):
        if bad in job:
            errors.append(f"{where}: a job that calls a reusable workflow cannot set '{bad}'")


def check_step(where, step):
    uses = step.get("uses")
    if not uses:
        return
    m = re.match(rf"{re.escape(SELF)}/actions/([\w-]+)@", uses)
    if m:
        name = m.group(1)
        if name not in actions:
            errors.append(f"{where}: unknown composite action {name}")
            return
        for k in step.get("with") or {}:
            if k not in actions[name]:
                errors.append(f"{where}: action {name} has no input '{k}'")
        for k, s in actions[name].items():
            if (s or {}).get("required") and k not in (step.get("with") or {}):
                errors.append(f"{where}: action {name} requires input '{k}'")
        return
    if uses.startswith("./") or uses.startswith("docker://"):
        return
    if not re.search(r"@[0-9a-f]{40}$", uses.split()[0]):
        errors.append(f"{where}: '{uses}' is not pinned to a full commit SHA")


for p, doc in docs.items():
    if not isinstance(doc, dict):
        continue
    rel = p.relative_to(ROOT) if p.is_relative_to(ROOT) else p
    if p.name == "action.yml":
        for i, step in enumerate((doc.get("runs") or {}).get("steps") or []):
            check_step(f"{rel} step {i}", step)
        continue
    if "jobs" not in doc:
        continue
    for jid, job in (doc.get("jobs") or {}).items():
        where = f"{rel}:{jid}"
        if "uses" in job:
            check_uses_workflow(where, job["uses"], job)
            continue
        if "timeout-minutes" not in job:
            errors.append(f"{where}: missing timeout-minutes")
        for i, step in enumerate(job.get("steps") or []):
            check_step(f"{where} step {i}", step)

# ---------------------------------------------------------------- referenced repo files
REF = re.compile(
    r"(?<![\w./$-])(?:\./)?("
    r"(?:[\w.-]+/)*[\w.-]+\.(?:sh|py|mjs|ps1|ref)"   # scripts and pin files
    r"|(?:[\w.-]+/)*Dockerfile[\w.-]*"                # Dockerfiles
    r")(?![\w/*-])"
)


def strings(node):
    if isinstance(node, str):
        yield node
    elif isinstance(node, dict):
        for v in node.values():
            yield from strings(v)
    elif isinstance(node, list):
        for v in node:
            yield from strings(v)


def check_repo_files(caller_dir: pathlib.Path, clone: pathlib.Path):
    shipped = caller_dir / "repo-files"
    for f in sorted(caller_dir.glob("*.yml")):
        doc = docs.get(f.resolve())
        if not isinstance(doc, dict) or "jobs" not in doc:
            continue
        for jid, job in (doc.get("jobs") or {}).items():
            texts = list(strings(job.get("with") or {}))
            dirs = [""]
            wd = ((job.get("defaults") or {}).get("run") or {}).get("working-directory")
            if wd:
                dirs.append(wd)
            wd = (job.get("with") or {}).get("working-directory")
            if isinstance(wd, str):
                dirs.append(wd)
            for step in job.get("steps") or []:
                texts += [step.get("run") or ""] + list(strings(step.get("with") or {}))
                if step.get("working-directory"):
                    dirs.append(step["working-directory"])
            for text in texts:
                for ref in REF.findall(text):
                    if "{" in ref or "$" in ref:
                        continue
                    cands = [pathlib.Path(d) / ref for d in dirs]
                    if not any((clone / c).exists() or (shipped / c).exists() for c in cands):
                        errors.append(f"{f}:{jid}: '{ref}' is neither in the repo nor in repo-files/")


if args.clones:
    checked = 0
    if not args.callers.is_dir():
        errors.append(f"--clones needs a caller directory; {args.callers} does not exist (pass --callers DIR)")
    for caller_dir in sorted(args.callers.iterdir()) if args.callers.is_dir() else []:
        clone = args.clones / caller_dir.name.split("__", 1)[1]
        if not clone.is_dir():
            errors.append(f"{caller_dir}: no checkout at {clone}")
            continue
        check_repo_files(caller_dir, clone)
        checked += 1
    print(f"checked referenced files of {checked} callers against {args.clones}")

print(f"checked {len(files)} YAML files, {len(workflows)} reusable workflows, {len(actions)} actions")
if errors:
    print("\n".join(errors))
    sys.exit(1)
print("OK")
