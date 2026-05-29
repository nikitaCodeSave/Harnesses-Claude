#!/usr/bin/env python3
"""
grade.py — battle-test grader.

Sub-commands invoked by battle-test-runner.sh:
    detect            — detect deliverable entry point + provision venv
    run-questions     — invoke deliverable on each NL question, capture answers
    grade-fq          — auto-grade F-Q1..Q5 by heuristic comparison to ground truth
    grade-tb-auto     — auto-grade scriptable T/B items (structure, deps, pytest, README, latency)

Usage:
    grade.py <subcommand> [options]

Designed to fail loud + return structured JSON so runner can aggregate even when
intermediate phases partially fail.
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

try:
    import yaml
except ImportError:
    print("FAIL: pyyaml required. pip install pyyaml", file=sys.stderr)
    sys.exit(2)


# ─── Phase 4: detect deliverable + provision venv ────────────────────────────

def cmd_detect(args: argparse.Namespace) -> int:
    clone = Path(args.clone_dir)
    if not clone.is_dir():
        return _fail_out(args.output, {"status": "fail", "reason": f"clone not found: {clone}"})

    result: dict[str, Any] = {
        "status": "ok",
        "entry_kind": None,
        "entry_module": None,
        "entry_script": None,
        "invocation_cmd": None,
        "venv_path": None,
        "venv_status": None,
        "install_log_tail": "",
    }

    # Detect entry-point per prompt.txt convention:
    #   1. pyproject.toml + package dir with __main__.py → python -m <pkg> "Q"
    #   2. main.py at clone root → python main.py "Q"
    #   3. src/<pkg>/__main__.py → python -m <pkg> "Q" (with src/ in pythonpath)

    pyproject = clone / "pyproject.toml"
    main_py = clone / "main.py"

    # Try pyproject-based module detection
    module = None
    if pyproject.exists():
        content = pyproject.read_text(errors="replace")
        # Look for [project].name or [tool.poetry].name
        m = re.search(r'^\s*name\s*=\s*["\']([\w_-]+)["\']', content, re.MULTILINE)
        if m:
            pkg_name = m.group(1).replace("-", "_")
            # Check for __main__.py in package dir
            for base in (clone, clone / "src"):
                pkg_dir = base / pkg_name
                if (pkg_dir / "__main__.py").exists():
                    module = pkg_name
                    result["entry_kind"] = "module"
                    result["entry_module"] = pkg_name
                    if base.name == "src":
                        result["invocation_cmd"] = f'PYTHONPATH=src .venv/bin/python -m {pkg_name}'
                    else:
                        result["invocation_cmd"] = f'.venv/bin/python -m {pkg_name}'
                    break

    if module is None and main_py.exists():
        result["entry_kind"] = "script"
        result["entry_script"] = "main.py"
        result["invocation_cmd"] = ".venv/bin/python main.py"

    if result["invocation_cmd"] is None:
        # Last-resort scan: any *_main.py / cli.py / app.py at root or src/
        for cand_name in ("cli.py", "app.py", "run.py", "assistant.py"):
            for base in (clone, clone / "src"):
                cand = base / cand_name
                if cand.exists():
                    rel = cand.relative_to(clone)
                    result["entry_kind"] = "fallback_script"
                    result["entry_script"] = str(rel)
                    result["invocation_cmd"] = f".venv/bin/python {rel}"
                    break
            if result["invocation_cmd"]:
                break

    if result["invocation_cmd"] is None:
        result["status"] = "fail"
        result["reason"] = "no entry point found (looked for pyproject+module/__main__, main.py, cli.py, app.py, run.py, assistant.py)"
        return _write_out(args.output, result)

    # Provision venv
    venv_dir = clone / ".venv"
    result["venv_path"] = str(venv_dir)
    install_log = clone / ".bench-install.log"

    if venv_dir.exists():
        result["venv_status"] = "preexisting"
    else:
        # Strictly python -m venv (no uv per operator policy)
        rc = _run([sys.executable, "-m", "venv", str(venv_dir)], cwd=clone, log=install_log)
        if rc != 0:
            result["venv_status"] = f"venv_create_failed (exit {rc})"
            result["install_log_tail"] = _tail(install_log)
            return _write_out(args.output, result, status="fail")

    pip = venv_dir / "bin" / "pip"

    # Install per pyproject (-e .) or requirements.txt or default deps
    if pyproject.exists():
        rc = _run([str(pip), "install", "-e", "."], cwd=clone, log=install_log, timeout=300)
        result["venv_status"] = f"pyproject_install (rc={rc})"
    elif (clone / "requirements.txt").exists():
        rc = _run([str(pip), "install", "-r", "requirements.txt"], cwd=clone, log=install_log, timeout=300)
        result["venv_status"] = f"requirements_install (rc={rc})"
    else:
        # Best-effort default deps based on prompt expectations
        rc = _run([str(pip), "install", "oracledb>=2.5.0", "openai>=1.0", "python-dotenv"],
                  cwd=clone, log=install_log, timeout=300)
        result["venv_status"] = f"default_deps_install (rc={rc})"

    result["install_log_tail"] = _tail(install_log)
    if rc != 0:
        return _write_out(args.output, result, status="partial")

    return _write_out(args.output, result)


# ─── Phase 5: run 5 questions ────────────────────────────────────────────────

def cmd_run_questions(args: argparse.Namespace) -> int:
    clone = Path(args.clone_dir)
    questions = yaml.safe_load(Path(args.questions).read_text())["questions"]
    detect = json.loads(Path(args.detect).read_text())
    inv = detect.get("invocation_cmd")
    if not inv:
        return _fail_out(args.output, {"status": "fail", "reason": "no invocation_cmd from detect"})

    answers: list[dict[str, Any]] = []
    for q in questions:
        qid = q["id"]
        nl = q["nl"]
        # invocation_cmd is shell-style; wrap with shell, pass NL as last arg
        # Quote NL carefully
        cmd = f'{inv} {_shquote(nl)}'
        start = time.monotonic()
        try:
            proc = subprocess.run(
                ["bash", "-c", cmd],
                cwd=clone,
                capture_output=True,
                text=True,
                timeout=args.timeout_sec,
            )
            wall = time.monotonic() - start
            answers.append({
                "id": qid,
                "nl": nl,
                "stdout": proc.stdout[-4000:],
                "stderr": proc.stderr[-2000:],
                "exit_code": proc.returncode,
                "wall_seconds": round(wall, 2),
                "status": "ok" if proc.returncode == 0 else "exit_nonzero",
            })
        except subprocess.TimeoutExpired:
            wall = time.monotonic() - start
            answers.append({
                "id": qid, "nl": nl,
                "stdout": "", "stderr": f"<timeout after {args.timeout_sec}s>",
                "exit_code": 124, "wall_seconds": round(wall, 2), "status": "timeout",
            })
        except Exception as e:
            answers.append({
                "id": qid, "nl": nl,
                "stdout": "", "stderr": f"<exception: {e}>",
                "exit_code": -1, "wall_seconds": 0.0, "status": "exception",
            })

    Path(args.output).write_text(json.dumps({"status": "ok", "answers": answers}, ensure_ascii=False, indent=2))
    return 0


# ─── Phase 6: grade F-Q* ─────────────────────────────────────────────────────

def cmd_grade_fq(args: argparse.Namespace) -> int:
    questions = yaml.safe_load(Path(args.questions).read_text())["questions"]
    answers_data = json.loads(Path(args.answers).read_text())
    answers = {a["id"]: a for a in answers_data.get("answers", [])}

    scores: dict[str, Any] = {}
    total = 0
    for q in questions:
        qid = q["id"]
        a = answers.get(qid)
        if not a or a["status"] != "ok":
            scores[qid] = {"score": 0, "max": 6, "verdict": "fail",
                           "reason": f"no answer or status={a['status'] if a else 'missing'}"}
            continue
        text = a["stdout"]
        score, verdict, reason = _grade_question(qid, text)
        scores[qid] = {"score": score, "max": 6, "verdict": verdict, "reason": reason}
        total += score

    out = {"status": "ok", "per_question": scores, "total": total, "max": 30}
    Path(args.output).write_text(json.dumps(out, ensure_ascii=False, indent=2))
    return 0


def _grade_question(qid: str, text: str) -> tuple[int, str, str]:
    """Return (score 0/3/6, verdict pass/partial/fail, reason)."""
    text_lc = text.lower()
    if qid == "Q1":
        # Expected: 10 distinct customers in Large segment
        if re.search(r'\b10\b|десят[ьи]', text):
            return 6, "pass", "found 10 / десять"
        if re.search(r'\b9\b|\b11\b', text):
            return 3, "partial", "off-by-one (9 or 11)"
        return 0, "fail", "no number 10/9/11 found"

    if qid == "Q2":
        # Top 5 orgs (any order with tolerable swap)
        expected = ["лизинг", "транслогистик", "нефтехимпром", "металлинвест", "пенсионный"]
        found = sum(1 for e in expected if e in text_lc)
        if found == 5:
            return 6, "pass", f"all 5 orgs found"
        if found == 4:
            return 3, "partial", f"4/5 orgs found"
        return 0, "fail", f"only {found}/5 orgs found"

    if qid == "Q3":
        # Expected: Large + positive growth ~+19%/545M
        has_large = bool(re.search(r'\blarge\b', text_lc))
        has_growth = bool(re.search(r'(\+?1[8-9]%|\+?20%|54[0-9]|545|рост|вырос|growth)', text_lc))
        if has_large and has_growth:
            return 6, "pass", "Large + growth signal"
        if has_large:
            return 3, "partial", "Large named but без growth detail"
        if re.search(r'\bregion\b', text_lc):
            return 3, "partial", "Region (тоже положительный, но мизерный)"
        return 0, "fail", "Large not named as growth leader"

    if qid == "Q4":
        # Expected: СМИРНОВ + 2 clients
        has_smirnov = bool(re.search(r'смирнов', text_lc))
        has_two = bool(re.search(r'\b2\b|\bдве?\b', text))
        if has_smirnov and has_two:
            return 6, "pass", "СМИРНОВ + 2 clients"
        if has_smirnov:
            return 3, "partial", "СМИРНОВ but without 2"
        if has_two and re.search(r'(international|международн)', text_lc):
            return 3, "partial", "2 clients but без СМИРНОВ"
        return 0, "fail", "neither СМИРНОВ nor 2-clients found"

    if qid == "Q5":
        # 6 hubs with counts within ±1
        expected = [
            ("москв", 32),
            ("north-west", 17),
            ("ural", 11),
            ("siberia", 8),
            ("south", 7),
            ("volga", 7),
        ]
        # Extract pairs heuristic: hub name within window of a number
        found_pairs = 0
        for hub, exp_val in expected:
            # Find hub mention, then look for number within 30 chars
            m = re.search(re.escape(hub) + r'.{0,30}?(\d+)', text_lc)
            if m:
                v = int(m.group(1))
                if abs(v - exp_val) <= 1:
                    found_pairs += 1
        if found_pairs >= 6:
            return 6, "pass", "all 6 hubs within ±1"
        if found_pairs >= 4:
            return 3, "partial", f"{found_pairs}/6 hubs within ±1"
        return 0, "fail", f"only {found_pairs}/6 hubs match"

    return 0, "fail", f"unknown question {qid}"


# ─── Phase 7: scriptable T/B auto-grade ──────────────────────────────────────

def cmd_grade_tb_auto(args: argparse.Namespace) -> int:
    clone = Path(args.clone_dir)
    answers_data = json.loads(Path(args.questions_result).read_text()) if Path(args.questions_result).exists() else {}
    answers = answers_data.get("answers", [])

    items: dict[str, Any] = {}

    # T1 — Project structure (6 pts)
    t1 = _grade_t1_structure(clone)
    items["T1"] = t1

    # T2 — Dependency management (4 pts)
    t2 = _grade_t2_deps(clone)
    items["T2"] = t2

    # T5 — Tests (8 pts)
    t5 = _grade_t5_tests(clone)
    items["T5"] = t5

    # T6 — Documentation (4 pts)
    t6 = _grade_t6_docs(clone)
    items["T6"] = t6

    # B4 — Latency / cost (5 pts) from Phase 5 timings
    b4 = _grade_b4_latency(answers)
    items["B4"] = b4

    total = sum(it["score"] for it in items.values())
    out = {"status": "ok", "items": items, "total": total, "max": 27}  # 6+4+8+4+5 = 27 actually
    # Recompute max from actual maxes
    out["max"] = sum(it["max"] for it in items.values())
    Path(args.output).write_text(json.dumps(out, ensure_ascii=False, indent=2))
    return 0


def _grade_t1_structure(clone: Path) -> dict:
    py_files = list(clone.rglob("*.py"))
    py_files = [p for p in py_files if ".venv" not in p.parts and "__pycache__" not in p.parts]
    has_src_or_pkg = any(p.parent.name not in ("", clone.name) for p in py_files)
    has_tests_dir = (clone / "tests").is_dir() or any("test" in p.parts for p in py_files)
    has_pyproject = (clone / "pyproject.toml").exists() or (clone / "setup.py").exists()
    n_py = len(py_files)

    if n_py >= 4 and has_src_or_pkg and has_tests_dir and has_pyproject:
        return {"score": 6, "max": 6, "verdict": "pass",
                "reason": f"{n_py} py files, src/pkg structure, tests dir, pyproject"}
    if n_py >= 2 and (has_pyproject or has_src_or_pkg):
        return {"score": 3, "max": 6, "verdict": "partial",
                "reason": f"{n_py} py files, partial structure (pyproject={has_pyproject}, tests={has_tests_dir})"}
    return {"score": 0, "max": 6, "verdict": "fail",
            "reason": f"only {n_py} py files, no structure"}


def _grade_t2_deps(clone: Path) -> dict:
    pyproject = clone / "pyproject.toml"
    reqs = clone / "requirements.txt"
    content = ""
    if pyproject.exists():
        content = pyproject.read_text(errors="replace")
    elif reqs.exists():
        content = reqs.read_text(errors="replace")
    else:
        return {"score": 0, "max": 4, "verdict": "fail", "reason": "no pyproject.toml or requirements.txt"}

    has_oracledb = "oracledb" in content.lower()
    has_openai = "openai" in content.lower()
    has_version_constraint = bool(re.search(r'(oracledb|openai)\s*[>=~]', content.lower()))

    if has_oracledb and has_openai and has_version_constraint:
        return {"score": 4, "max": 4, "verdict": "pass",
                "reason": "oracledb + openai with version constraints"}
    if has_oracledb and has_openai:
        return {"score": 2, "max": 4, "verdict": "partial",
                "reason": "deps listed but unpinned"}
    return {"score": 0, "max": 4, "verdict": "fail",
            "reason": f"oracledb={has_oracledb} openai={has_openai}"}


def _grade_t5_tests(clone: Path) -> dict:
    test_files = [p for p in clone.rglob("test_*.py") if ".venv" not in p.parts]
    test_files += [p for p in clone.rglob("*_test.py") if ".venv" not in p.parts]
    if not test_files:
        return {"score": 0, "max": 8, "verdict": "fail", "reason": "no test_*.py / *_test.py found"}

    pytest = clone / ".venv" / "bin" / "pytest"
    if not pytest.exists():
        # Try generic pytest
        pytest_cmd = ["pytest", "--tb=no", "-q", "--no-header"]
    else:
        pytest_cmd = [str(pytest), "--tb=no", "-q", "--no-header"]

    try:
        rc = subprocess.run(pytest_cmd, cwd=clone, capture_output=True,
                            text=True, timeout=180).returncode
    except Exception:
        rc = 99

    if rc == 0:
        return {"score": 8, "max": 8, "verdict": "pass",
                "reason": f"{len(test_files)} test files, pytest passes"}
    if rc in (1, 2):  # tests collected but fail
        return {"score": 4, "max": 8, "verdict": "partial",
                "reason": f"{len(test_files)} test files, pytest exit={rc}"}
    return {"score": 0, "max": 8, "verdict": "fail",
            "reason": f"pytest exit={rc} (collection or env issue)"}


def _grade_t6_docs(clone: Path) -> dict:
    readme_candidates = [clone / "README.md", clone / "Readme.md", clone / "readme.md"]
    readme = next((r for r in readme_candidates if r.exists()), None)
    if readme is None:
        return {"score": 0, "max": 4, "verdict": "fail", "reason": "no README"}
    lines = len(readme.read_text(errors="replace").splitlines())
    if lines >= 50:
        return {"score": 4, "max": 4, "verdict": "pass", "reason": f"README {lines} lines"}
    if lines >= 15:
        return {"score": 2, "max": 4, "verdict": "partial", "reason": f"README {lines} lines (brief)"}
    return {"score": 0, "max": 4, "verdict": "fail", "reason": f"README {lines} lines (stub)"}


def _grade_b4_latency(answers: list[dict]) -> dict:
    if not answers:
        return {"score": 0, "max": 5, "verdict": "fail", "reason": "no Phase 5 data"}
    walls = [a.get("wall_seconds", 0) for a in answers if a.get("status") == "ok"]
    if not walls:
        return {"score": 0, "max": 5, "verdict": "fail", "reason": "all questions failed"}
    walls.sort()
    median = walls[len(walls) // 2]
    if median < 30:
        return {"score": 5, "max": 5, "verdict": "pass", "reason": f"median wall {median:.1f}s"}
    if median < 60:
        return {"score": 2, "max": 5, "verdict": "partial", "reason": f"median wall {median:.1f}s"}
    return {"score": 0, "max": 5, "verdict": "fail", "reason": f"median wall {median:.1f}s"}


# ─── Helpers ─────────────────────────────────────────────────────────────────

def _run(cmd: list[str], cwd: Path, log: Path, timeout: int = 120) -> int:
    try:
        with open(log, "ab") as f:
            f.write(f"\n--- {' '.join(cmd)} ---\n".encode())
            p = subprocess.run(cmd, cwd=cwd, stdout=f, stderr=subprocess.STDOUT, timeout=timeout)
            return p.returncode
    except subprocess.TimeoutExpired:
        return 124
    except Exception as e:
        with open(log, "a") as f:
            f.write(f"\n[exception] {e}\n")
        return 99


def _tail(path: Path, n: int = 30) -> str:
    if not path.exists():
        return ""
    try:
        return "\n".join(path.read_text(errors="replace").splitlines()[-n:])
    except Exception:
        return ""


def _shquote(s: str) -> str:
    """Single-quote a string for shell, escaping inner single quotes."""
    return "'" + s.replace("'", "'\\''") + "'"


def _fail_out(out_path: str, payload: dict) -> int:
    payload.setdefault("status", "fail")
    Path(out_path).write_text(json.dumps(payload, ensure_ascii=False, indent=2))
    return 1


def _write_out(out_path: str, payload: dict, status: str = "ok") -> int:
    payload.setdefault("status", status)
    Path(out_path).write_text(json.dumps(payload, ensure_ascii=False, indent=2))
    return 0


# ─── Entry ───────────────────────────────────────────────────────────────────

def main() -> int:
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)

    pd = sub.add_parser("detect")
    pd.add_argument("--clone-dir", required=True)
    pd.add_argument("--output", required=True)

    pq = sub.add_parser("run-questions")
    pq.add_argument("--clone-dir", required=True)
    pq.add_argument("--questions", required=True)
    pq.add_argument("--detect", required=True)
    pq.add_argument("--timeout-sec", type=int, default=120)
    pq.add_argument("--output", required=True)

    pf = sub.add_parser("grade-fq")
    pf.add_argument("--questions", required=True)
    pf.add_argument("--answers", required=True)
    pf.add_argument("--output", required=True)

    pt = sub.add_parser("grade-tb-auto")
    pt.add_argument("--clone-dir", required=True)
    pt.add_argument("--questions-result", required=True)
    pt.add_argument("--output", required=True)

    args = p.parse_args()
    return {
        "detect": cmd_detect,
        "run-questions": cmd_run_questions,
        "grade-fq": cmd_grade_fq,
        "grade-tb-auto": cmd_grade_tb_auto,
    }[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
