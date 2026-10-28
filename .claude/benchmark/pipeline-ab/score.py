#!/usr/bin/env python3
"""pipeline-ab scoring.

  score.py run <task> <arm>-<rep>   — score one run (hidden oracle, own suite, mutation, cost, human load)
  score.py summary                  — per task x arm table: min / median / max

Mutation score: AST mutants on the lines the agent added or changed under src/, run against the agent's
own test suite (the hidden oracle is never used for it). It measures how well the agent's tests pin its
own code — the variable the TDD decision is about.
"""
import ast
import json
import os
import pathlib
import random
import re
import shutil
import statistics
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

HERE = pathlib.Path(__file__).resolve().parent
RESULTS = pathlib.Path(os.environ.get("PAB_RESULTS", HERE / "results"))
TASKS = HERE / "tasks"
MAX_MUTANTS = int(os.environ.get("PAB_MAX_MUTANTS", "100"))
MUTANT_TIMEOUT = 60
PY = sys.executable


def junit(path):
    if not path.exists():
        return {"tests": 0, "passed": 0, "passed_ids": set(), "collect_error": True}
    root = ET.parse(path).getroot()
    tests, ok = 0, set()
    for case in root.iter("testcase"):
        tests += 1
        if not {child.tag for child in case} & {"failure", "error", "skipped"}:
            ok.add(f"{case.get('classname')}::{case.get('name')}")
    errors = sum(int(s.get("errors", 0)) for s in root.iter("testsuite"))
    return {"tests": tests, "passed": len(ok), "passed_ids": ok, "collect_error": tests == 0 and errors > 0}


def pytest(args, cwd, env, xml, timeout=900):
    try:
        subprocess.run([PY, "-m", "pytest", "-q", "-p", "no:cacheprovider", f"--junitxml={xml}", *args],
                       cwd=cwd, env=env, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        pass
    return junit(pathlib.Path(xml))


def changed_lines(ws, base):
    """{relpath: set(lines)} for added/changed lines under src/, incl. untracked files."""
    tmpd = tempfile.mkdtemp()
    env = dict(os.environ, GIT_INDEX_FILE=os.path.join(tmpd, "index"))
    subprocess.run(["git", "read-tree", base], cwd=ws, env=env, capture_output=True)
    subprocess.run(["git", "add", "-A"], cwd=ws, env=env, capture_output=True)
    diff = subprocess.run(["git", "diff", "--cached", "-U0", base, "--", "src"], cwd=ws, env=env,
                          capture_output=True, text=True).stdout
    shutil.rmtree(tmpd, ignore_errors=True)
    out, cur = {}, None
    for line in diff.splitlines():
        if line.startswith("+++ "):
            cur = None if line.endswith("/dev/null") else line[6:]
        elif line.startswith("@@") and cur and cur.endswith(".py"):
            m = re.search(r"\+(\d+)(?:,(\d+))?", line)
            start, n = int(m.group(1)), int(m.group(2) or 1)
            out.setdefault(cur, set()).update(range(start, start + n))
    return out


SWAP_CMP = {ast.Lt: ast.LtE, ast.LtE: ast.Lt, ast.Gt: ast.GtE, ast.GtE: ast.Gt, ast.Eq: ast.NotEq,
            ast.NotEq: ast.Eq, ast.In: ast.NotIn, ast.NotIn: ast.In, ast.Is: ast.IsNot, ast.IsNot: ast.Is}
SWAP_BIN = {ast.Add: ast.Sub, ast.Sub: ast.Add, ast.Mult: ast.Div, ast.Div: ast.Mult}


class Mutator(ast.NodeTransformer):
    """Pass 1 (target=None) collects candidates; pass 2 applies candidate #target."""

    def __init__(self, lines, target=None):
        self.lines, self.target, self.found = lines, target, []

    def _hit(self, node, kind):
        if getattr(node, "lineno", None) not in self.lines:
            return False
        k = len(self.found)
        self.found.append((node.lineno, kind))
        return k == self.target

    def visit_Compare(self, node):
        self.generic_visit(node)
        for i, op in enumerate(node.ops):
            if type(op) in SWAP_CMP and self._hit(node, f"cmp:{type(op).__name__}"):
                node.ops[i] = SWAP_CMP[type(op)]()
        return node

    def visit_BinOp(self, node):
        self.generic_visit(node)
        if type(node.op) in SWAP_BIN and self._hit(node, f"bin:{type(node.op).__name__}"):
            node.op = SWAP_BIN[type(node.op)]()
        return node

    def visit_BoolOp(self, node):
        self.generic_visit(node)
        if self._hit(node, "bool"):
            node.op = ast.Or() if isinstance(node.op, ast.And) else ast.And()
        return node

    def visit_Constant(self, node):
        if isinstance(node.value, bool):
            if self._hit(node, "const:bool"):
                return ast.copy_location(ast.Constant(not node.value), node)
        elif isinstance(node.value, (int, float)) and self._hit(node, "const:num"):
            return ast.copy_location(ast.Constant(node.value + 1), node)
        return node

    def visit_If(self, node):
        self.generic_visit(node)
        if self._hit(node, "if:negate"):
            node.test = ast.UnaryOp(ast.Not(), node.test)
        return node

    def visit_Return(self, node):
        self.generic_visit(node)
        if node.value is not None and not (isinstance(node.value, ast.Constant) and node.value.value is None) \
                and self._hit(node, "return:none"):
            node.value = ast.Constant(None)
        return node

    def visit_Raise(self, node):
        self.generic_visit(node)
        if self._hit(node, "raise:pass"):
            return ast.copy_location(ast.Pass(), node)
        return node


def mutation(wsc, files, baseline_ok):
    """A mutant is killed when any test that passes on the agent's code fails (or the suite breaks/hangs)."""
    mutants = []
    for rel, lines in files.items():
        src = (wsc / rel).read_text()
        try:
            m = Mutator(lines)
            m.visit(ast.parse(src))
        except SyntaxError:
            continue
        mutants += [(rel, k, kind) for k, (_, kind) in enumerate(m.found)]
    total = len(mutants)
    if not mutants:
        return {"mutants_total": 0, "sampled": 0, "killed": 0, "score": None}
    rng = random.Random(0)
    sample = sorted(rng.sample(mutants, min(MAX_MUTANTS, total)))
    killed, kinds = 0, {}
    env = dict(os.environ, PYTHONDONTWRITEBYTECODE="1")
    xml = wsc.parent / "mut.xml"
    for rel, k, kind in sample:
        path = wsc / rel
        orig = path.read_text()
        tree = ast.parse(orig)
        Mutator(files[rel], target=k).visit(tree)
        path.write_text(ast.unparse(ast.fix_missing_locations(tree)))
        xml.unlink(missing_ok=True)
        try:
            subprocess.run([PY, "-m", "pytest", "-q", "-p", "no:cacheprovider", f"--junitxml={xml}", "."],
                           cwd=wsc, env=env, capture_output=True, timeout=MUTANT_TIMEOUT)
            r = junit(xml)
            dead = r["collect_error"] or bool(baseline_ok - r["passed_ids"])
        except subprocess.TimeoutExpired:
            dead = True
        path.write_text(orig)
        killed += dead
        kinds.setdefault(kind, [0, 0])
        kinds[kind][0] += dead
        kinds[kind][1] += 1
    return {"mutants_total": total, "sampled": len(sample), "killed": killed,
            "score": round(killed / len(sample), 3), "by_kind": kinds}


def patch_stats(patch):
    files, src_add, test_add, cur = set(), 0, 0, ""
    for line in patch.splitlines():
        if line.startswith("+++ "):
            cur = line[6:]
            files.add(cur)
        elif line.startswith("+") and not line.startswith("+++"):
            if re.search(r"(^|/)tests?/|(^|/)test_[^/]*\.py$", cur):
                test_add += 1
            elif cur.startswith("src/"):
                src_add += 1
    return {"files_changed": len(files), "src_lines_added": src_add, "test_lines_added": test_add}


def calls_stats(rdir):
    dev_cost = user_cost = 0.0
    dev_out_tok = 0
    agent_chars = 0
    sessions = set()
    subagents = 0
    for f in sorted((rdir / "calls").glob("*.json")):
        c = json.loads(f.read_text())
        cost = c.get("total_cost_usd") or 0.0
        if c.get("role") == "user":
            user_cost += cost
            continue
        dev_cost += cost
        dev_out_tok += (c.get("usage") or {}).get("output_tokens", 0)
        agent_chars += len(c.get("result") or "")
        sessions.add(c.get("session"))
        st = c.get("subagent_stats") or {}
        if isinstance(st, dict):
            subagents += st.get("spawned", 0) or 0
    return {"dev_cost_usd": round(dev_cost, 3), "user_cost_usd": round(user_cost, 3),
            "dev_output_tokens": dev_out_tok, "agent_chars_to_human": agent_chars,
            "dev_sessions": len(sessions), "subagents": subagents}


def leak_check(meta):
    """Grep the dev sessions' own transcripts for any touch of the benchmark repo or the oracle."""
    slug = re.sub(r"[^A-Za-z0-9]", "-", meta["workspace"])
    pdir = pathlib.Path("~/.claude/projects").expanduser() / slug
    hits = []
    if pdir.exists():
        for f in pdir.glob("*.jsonl"):
            text = f.read_text(errors="replace")
            if "USERSIM" in text or "Your private notes are the ground truth" in text:
                continue  # the simulator's own session legitimately holds the notes
            for needle in ("pipeline-ab", "Harnesses-Claude", "NOTES.md", "test_acceptance.py"):
                if needle in text:
                    hits.append(f"{f.name}:{needle}")
    return hits


def run_oracle(src_root, task, tmp):
    oracle = tmp / "oracle"
    if not oracle.exists():
        shutil.copytree(TASKS / task / "oracle", oracle)
    env = dict(os.environ, PYTHONPATH=str(src_root), PYTHONDONTWRITEBYTECODE="1")
    acc = pytest([str(oracle / "test_acceptance.py")], tmp, env, tmp / "acc.xml")
    reg = pytest([str(oracle / "test_regression.py")], tmp, env, tmp / "reg.xml")
    return acc, reg


def calibrate(task):
    """Expected oracle sizes from the reference solution; also asserts reference=100%, pristine acceptance=0."""
    with tempfile.TemporaryDirectory() as tmp:
        tmp = pathlib.Path(tmp)
        ref = tmp / "ref"
        shutil.copytree(TASKS / task / "repo", ref)
        subprocess.run(["patch", "-s", "-p1", "-i", str(TASKS / task / "reference/reference.patch")], cwd=ref,
                       check=True)
        acc, reg = run_oracle(ref / "src", task, tmp)
        pristine = tmp / "pristine"
        pristine.mkdir()
        pa, pr = run_oracle(TASKS / task / "repo/src", task, pristine)
    counts = {"acceptance": acc["tests"], "regression": reg["tests"]}
    ok = (acc["passed"] == acc["tests"] > 0 and reg["passed"] == reg["tests"] > 0 and pa["passed"] == 0
          and pr["passed"] == pr["tests"])
    (TASKS / task / "oracle_counts.json").write_text(json.dumps(counts))
    print(f"{task}: reference acc {acc['passed']}/{acc['tests']} reg {reg['passed']}/{reg['tests']}; "
          f"pristine acc {pa['passed']} reg {pr['passed']}/{pr['tests']} -> {'OK' if ok else 'FAIL'}")
    return ok


def score_run(task, name):
    rdir = RESULTS / task / name
    meta = json.loads((rdir / "meta.json").read_text())
    ws = pathlib.Path(meta["workspace"])
    counts = json.loads((TASKS / task / "oracle_counts.json").read_text())
    files = changed_lines(ws, meta["base"])
    with tempfile.TemporaryDirectory() as tmp:
        tmp = pathlib.Path(tmp)
        wsc = tmp / "ws"
        shutil.copytree(ws, wsc, ignore=shutil.ignore_patterns(".git", "__pycache__", ".pytest_cache"))
        subprocess.run(["chmod", "-R", "u+w", str(wsc)])
        acc, reg = run_oracle(wsc / "src", task, tmp)
        own = pytest(["."], wsc, dict(os.environ, PYTHONDONTWRITEBYTECODE="1"), tmp / "own.xml")
        mut = mutation(wsc, files, own["passed_ids"]) if own["passed"] else {"score": None}
    res = {
        "task": task, "run": name, "arm": meta["arm"],
        "acceptance": {"passed": acc["passed"], "total": counts["acceptance"],
                       "interface_broken": acc["collect_error"]},
        "regression": {"passed": reg["passed"], "total": counts["regression"]},
        "own_suite": {"passed": own["passed"], "total": own["tests"]},
        "mutation": mut,
        "patch": patch_stats((rdir / "final.patch").read_text()),
        "cost": calls_stats(rdir),
        "wall_s": meta.get("wall_s"),
        "user_turns": sum(s.get("user_turns", 0) for s in meta.get("stages", [])),
        "errors": meta.get("errors", []),
        "acceptance_tampered": meta.get("acceptance_tampered"),
        "overrun": meta.get("overrun", []),
        "leaks": leak_check(meta),
    }
    (rdir / "score.json").write_text(json.dumps(res, ensure_ascii=False, indent=1))
    a = res["acceptance"]
    print(f"{task} {name}: acc {a['passed']}/{a['total']} reg {res['regression']['passed']}/"
          f"{res['regression']['total']} mut {mut.get('score')} cost ${res['cost']['dev_cost_usd']} "
          f"wall {res['wall_s']}s turns {res['user_turns']} leaks {len(res['leaks'])}"
          f"{' INTERFACE-BROKEN' if acc['collect_error'] else ''}")
    return res


def bracket(xs):
    xs = [x for x in xs if x is not None]
    if not xs:
        return "—"
    return f"{min(xs):g} / {statistics.median(xs):g} / {max(xs):g}"


def summary():
    rows = ["| task | arm | n | acceptance % | regression % | mutation score | dev cost $ | wall min | user turns | agent chars |",
            "|---|---|---|---|---|---|---|---|---|---|"]
    for tdir in sorted(p for p in RESULTS.iterdir() if p.is_dir()):
        for arm in "VSFRP":
            sc = [json.loads(f.read_text()) for f in sorted(tdir.glob(f"{arm}-*/score.json"))]
            if not sc:
                continue
            pct = lambda d: round(100 * d["passed"] / d["total"], 1) if d["total"] else 0.0
            rows.append("| " + " | ".join([
                tdir.name, arm, str(len(sc)),
                bracket([pct(s["acceptance"]) for s in sc]),
                bracket([pct(s["regression"]) for s in sc]),
                bracket([s["mutation"].get("score") for s in sc]),
                bracket([s["cost"]["dev_cost_usd"] for s in sc]),
                bracket([round((s["wall_s"] or 0) / 60, 1) for s in sc]),
                bracket([s["user_turns"] for s in sc]),
                bracket([s["cost"]["agent_chars_to_human"] for s in sc]),
            ]) + " |")
    print("min / median / max per cell\n")
    print("\n".join(rows))


if __name__ == "__main__":
    if sys.argv[1:2] == ["run"]:
        score_run(sys.argv[2], sys.argv[3])
    elif sys.argv[1:2] == ["calibrate"]:
        sys.exit(0 if calibrate(sys.argv[2]) else 1)
    elif sys.argv[1:2] == ["summary"]:
        summary()
    else:
        sys.exit(__doc__)
