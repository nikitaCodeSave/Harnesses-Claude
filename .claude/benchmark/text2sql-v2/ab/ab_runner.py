"""A/B harness test: does the GLOBAL ~/.claude practice layer help Claude BUILD a
better NL->SQL analyst? (devlog #60 prep — readiness scaffolding.)

Two arms, identical except the global practice layer:
  harness    : claude --print with the default ~/.claude (CLAUDE.md §5/§6/§7,
               hooks, skills active).
  noharness  : claude --print with CLAUDE_CONFIG_DIR -> a bare config dir that
               carries ONLY the OAuth credentials (no CLAUDE.md / hooks / skills).
               (CLAUDE_CONFIG_DIR alone loses auth; we copy .credentials.json in.)

Each arm builds an impl per ab/build_prompt.md exposing `solve.py` ("<question>"
-> SQL on stdout). The built impl is wrapped as a Solver and scored by the v2
benchmark against the live bench Oracle. Arms are compared on v2 quality.

Noise model: the v2 oracle is deterministic (variance run 5/5/5); the stochastic
part is the claude BUILD, so use --repeats-build N>1 per arm for significance.

    python3 ab/ab_runner.py --stub                 # validate pipeline, no claude
    python3 ab/ab_runner.py --arms both --builds 3 # full A/B (expensive)
"""
from __future__ import annotations

import argparse
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

_V2 = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(_V2))
import runner  # noqa: E402

BUILD_PROMPT = (_V2 / "ab" / "build_prompt.md").read_text(encoding="utf-8")
BUILD_MODEL = os.getenv("AB_BUILD_MODEL", "claude-sonnet-4-6")
BUILD_TIMEOUT = int(os.getenv("AB_BUILD_TIMEOUT", "2400"))
SOLVE_TIMEOUT = int(os.getenv("AB_SOLVE_TIMEOUT", "240"))  # impl makes an ollama call per task


class BuiltImplSolver:
    """Wraps a built impl's `solve.py "<question>"` (prints SQL) as a v2 Solver."""

    def __init__(self, impl_dir: str, timeout: int = SOLVE_TIMEOUT):
        self.impl_dir = impl_dir
        self.timeout = timeout

    def solve(self, task: dict) -> dict:
        # Run with the lab interpreter (has httpx/urllib for the ollama call); the
        # ollama + Oracle env (already exported for the run) is inherited so the
        # built impl can reach the local model. The impl returns SQL; the runner
        # executes it against the bench Oracle.
        try:
            out = subprocess.run(
                [sys.executable, "solve.py", task["nl"]],
                cwd=self.impl_dir, capture_output=True, text=True,
                timeout=self.timeout, env=dict(os.environ),
            )
        except Exception as exc:  # noqa: BLE001
            return {"sql": "", "result": None, "status": "error", "answer": str(exc)[:300]}
        sql = runner._extract_sql(out.stdout)
        if not sql:
            return {"sql": "", "result": None, "status": "refused", "answer": out.stdout[:300]}
        return {"sql": sql, "result": None, "status": "success", "answer": ""}


def _bare_config_dir() -> str:
    """A config dir with ONLY the OAuth credentials — no global practice layer."""
    d = tempfile.mkdtemp(prefix="ab-bare-cfg-")
    os.chmod(d, 0o700)
    creds = os.path.expanduser("~/.claude/.credentials.json")
    if not os.path.exists(creds):
        raise SystemExit("~/.claude/.credentials.json not found — cannot authenticate noharness arm.")
    shutil.copy(creds, os.path.join(d, ".credentials.json"))
    os.chmod(os.path.join(d, ".credentials.json"), 0o600)
    (pathlib.Path(d) / "settings.json").write_text("{}", encoding="utf-8")
    return d


def build_impl(arm: str) -> str:
    """Run `claude --print` to build the impl for one arm; return its workdir."""
    workdir = tempfile.mkdtemp(prefix=f"ab-{arm}-build-")
    env = dict(os.environ)
    if arm == "noharness":
        env["CLAUDE_CONFIG_DIR"] = _bare_config_dir()
    subprocess.run(
        ["claude", "--print", "--model", BUILD_MODEL,
         "--permission-mode", "bypassPermissions", "--no-session-persistence", BUILD_PROMPT],
        cwd=workdir, env=env, timeout=BUILD_TIMEOUT, capture_output=True, text=True,
    )
    if not (pathlib.Path(workdir) / "solve.py").exists():
        print(f"[warn] {arm}: solve.py not produced in {workdir}")
    return workdir


def run_arm(arm: str, stub: bool, repeats: int) -> dict:
    if stub:
        solver = runner.ReferenceSolver()           # validates the scoring pipeline
        workdir = "(stub: ReferenceSolver)"
    else:
        workdir = build_impl(arm)
        solver = BuiltImplSolver(workdir)
    rep = runner.run_benchmark(solver=solver, repeats=repeats)
    rep["arm"] = arm
    rep["workdir"] = workdir
    return rep


def compare(reports: list[dict]) -> None:
    print("\n=== A/B comparison (v2 gate_pass / 12) ===")
    for r in reports:
        s = r["summary"]
        print(f"  {r['arm']:10} mode={r['mode']:8} gate_pass={s['gate_pass']}/{s['n_tasks']} "
              f"stable={s['stable']}")
    if len(reports) == 2:
        a, b = (r["summary"]["gate_pass"] for r in reports)
        print(f"  delta ({reports[0]['arm']} - {reports[1]['arm']}): {a - b:+d}")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--stub", action="store_true", help="validate pipeline without invoking claude")
    ap.add_argument("--arms", default="both", choices=["both", "harness", "noharness"])
    ap.add_argument("--builds", type=int, default=1, help="claude build repeats per arm (significance)")
    ap.add_argument("--repeats", type=int, default=1, help="v2 repeats per task (oracle is deterministic)")
    ap.add_argument("--out", default="/tmp/ab_report.json")
    args = ap.parse_args()

    arms = ["harness", "noharness"] if args.arms == "both" else [args.arms]
    reports = []
    for arm in arms:
        for b in range(args.builds):
            label = arm if args.builds == 1 else f"{arm}#{b + 1}"
            print(f"--- arm {label} (stub={args.stub}) ---")
            rep = run_arm(arm, args.stub, args.repeats)
            rep["arm"] = label
            reports.append(rep)
    compare(reports)
    pathlib.Path(args.out).write_text(json.dumps(reports, ensure_ascii=False, default=str), encoding="utf-8")
    print(f"\nwrote {args.out}")


if __name__ == "__main__":
    main()
