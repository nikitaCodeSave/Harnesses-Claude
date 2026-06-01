"""Multi-session A/B: does the GLOBAL ~/.claude practice layer help Claude build a
better NL->SQL analyst ACROSS SESSION BOUNDARIES? (devlog #63.)

Single-shot A/B (#52, #61) systematically nulls the continuity pillar (#54): the
whole build lives in one context, so nothing has to survive a boundary. This driver
exercises continuity: the build is split into 3 stages, each a SEPARATE
`claude --print --no-session-persistence` in the SAME persisted workdir. The only
state-carriers across the boundary are (a) the code in the workdir — identical for
both arms — and (b) for the harness arm only, whatever the global practice layer
(CLAUDE.md §6 continuity + session-context.sh SessionStart hook) causes the agent to
write to `<workdir>/.claude/{devlog,progress}` and re-surface next session.

Arms (identical except the global layer; same toggle as ab_runner.py, verified #60):
  harness    : claude --print with the default ~/.claude (full practice layer).
  noharness  : CLAUDE_CONFIG_DIR -> bare dir carrying ONLY OAuth creds.

Design (B): the full domain spec is given ONLY at stage S1. S2/S3 get thin prompts
that name the new question types but NOT the domain traps (two-step AVG of balances,
CREATE_DT-not-MONTH_DT, MAX(MONTH_DT)-not-synthesised-EOM, PNL-no-double-count). So
whether those rules survive to S2/S3 depends on the continuity layer. Caveat: the
noharness arm has no mechanism to persist the spec beyond the code itself — that is
precisely the delta under measurement, not an unfair handicap.

Metrics (v2 oracle is deterministic, 5/5/5 -> repeats=1):
  - per-stage gate_pass /12 trajectory (full suite scored after EACH stage);
  - cross-stage regression: tasks green after S1 that go red after S3 (where
    continuity bites hardest — esp. T9's balance AVG, first seen in S1's T3);
  - mechanism check: did the arm create .claude/{devlog,progress} between stages?

    python3 ab/ab_multisession.py --stub          # pipeline check, no claude
    python3 ab/ab_multisession.py --arms both      # full run (6 claude sessions)
"""
from __future__ import annotations

import argparse
import json
import os
import pathlib
import subprocess
import sys
import tempfile

_V2 = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(_V2))
import runner  # noqa: E402
from ab_runner import BuiltImplSolver, _bare_config_dir  # noqa: E402

_STAGES_DIR = _V2 / "ab" / "stages"
BUILD_PROMPT = (_V2 / "ab" / "build_prompt.md").read_text(encoding="utf-8")

STAGES = ["S1", "S2", "S3"]
BUILD_MODEL = os.getenv("AB_BUILD_MODEL", "claude-sonnet-4-6")
BUILD_TIMEOUT = int(os.getenv("AB_BUILD_TIMEOUT", "2400"))

# Neutral handoff instruction (--prime-continuity). IDENTICAL for both arms, so the
# toggle stays the only difference: the harness arm, guided by global CLAUDE.md §6,
# writes the note into .claude/progress (and the SessionStart hook auto-surfaces it
# next stage); the noharness arm writes wherever it chooses, with no auto-surfacing.
# Appended to S1/S2 (the stages that have a "next session"); not to S3 (final).
_HANDOFF = (
    "\n\n## Передача следующей сессии\n"
    "Это многосессионная сборка — в конце ЭТОЙ сессии оставь для следующей сессии "
    "краткую заметку: текущее состояние проекта + ключевые доменные решения/правила, "
    "которые ты применил (чтобы следующая сессия их не переоткрывала и не сломала). "
    "Способ и место ведения такой заметки — на твоё усмотрение.\n"
)
PRIME_CONTINUITY = False  # set by --prime-continuity


def stage_prompt(stage: str) -> str:
    header = (_STAGES_DIR / f"{stage}.md").read_text(encoding="utf-8")
    # S1 carries the full domain spec; S2/S3 are deliberately thin (see Design B).
    prompt = header + BUILD_PROMPT if stage == "S1" else header
    if PRIME_CONTINUITY and stage in ("S1", "S2"):
        prompt += _HANDOFF
    return prompt


def _mechanism_snapshot(workdir: str) -> dict:
    """Did a continuity trail get written? Counts the harness-canonical locations
    (.claude/{devlog,progress}) AND any other handoff-like notes at the workdir root
    (so the noharness arm's free-form NOTES.md / HANDOFF.md is detected too)."""
    root = pathlib.Path(workdir)
    base = root / ".claude"
    def _count(p: pathlib.Path, glob: str) -> int:
        return len(list(p.glob(glob))) if p.is_dir() else 0
    canonical: dict = {
        "devlog_entries": _count(base / "devlog" / "entries", "*.md"),
        "progress_files": _count(base / "progress", "*.md"),
    }
    # Free-form handoff notes at root (exclude code/test READMEs we can't attribute).
    other = sorted(f.name for f in root.glob("*.md")
                   if any(k in f.name.upper()
                          for k in ("NOTE", "HANDOFF", "PROGRESS", "STATE", "CONTEXT", "SESSION")))
    canonical["other_notes"] = other
    return canonical


def _score(workdir: str) -> dict:
    """Score the current solve.py over the full 12-task suite (live oracle)."""
    rep = runner.run_benchmark(solver=BuiltImplSolver(workdir), repeats=1)
    per_task = {t["id"]: bool(t["gate_pass"]) for t in rep["tasks"]}
    return {"mode": rep["mode"], "gate_pass": rep["summary"]["gate_pass"],
            "n_tasks": rep["summary"]["n_tasks"], "per_task": per_task}


def _run_stage(stage: str, workdir: str, env: dict) -> None:
    subprocess.run(
        ["claude", "--print", "--model", BUILD_MODEL,
         "--permission-mode", "bypassPermissions", "--no-session-persistence",
         stage_prompt(stage)],
        cwd=workdir, env=env, timeout=BUILD_TIMEOUT, capture_output=True, text=True,
    )


def run_arm(arm: str, stub: bool) -> dict:
    workdir = tempfile.mkdtemp(prefix=f"ab-ms-{arm}-")
    env = dict(os.environ)
    if arm == "noharness":
        env["CLAUDE_CONFIG_DIR"] = _bare_config_dir()
    # CLAUDE_PROJECT_DIR drives the SessionStart hook's read root; pin it to the
    # workdir so the harness arm's continuity hook reads THIS build's trail.
    env["CLAUDE_PROJECT_DIR"] = workdir

    trajectory = []
    for stage in STAGES:
        if stub:
            # Stub: skip claude; ReferenceSolver proves the scoring/trajectory wiring.
            score = runner.run_benchmark(solver=runner.ReferenceSolver(), repeats=1)
            score = {"mode": score["mode"], "gate_pass": score["summary"]["gate_pass"],
                     "n_tasks": score["summary"]["n_tasks"],
                     "per_task": {t["id"]: bool(t["gate_pass"]) for t in score["tasks"]}}
            mech = {"devlog_entries": 0, "progress_files": 0}
        else:
            _run_stage(stage, workdir, env)
            mech = _mechanism_snapshot(workdir)
            score = (_score(workdir) if (pathlib.Path(workdir) / "solve.py").exists()
                     else {"mode": "n/a", "gate_pass": 0, "n_tasks": 12,
                           "per_task": {}, "note": "solve.py not produced"})
        print(f"  [{arm}/{stage}] gate_pass={score['gate_pass']}/{score['n_tasks']} "
              f"devlog={mech['devlog_entries']} progress={mech['progress_files']}")
        trajectory.append({"stage": stage, "score": score, "mechanism": mech})
    return {"arm": arm, "workdir": workdir, "trajectory": trajectory}


def _regression(traj: list[dict]) -> list[str]:
    """Tasks green at S1 that are red at the final stage (continuity loss signal)."""
    s1 = traj[0]["score"]["per_task"]
    sf = traj[-1]["score"]["per_task"]
    return sorted(tid for tid, ok in s1.items() if ok and not sf.get(tid, False))


def compare(arms: list[dict]) -> dict:
    print("\n=== multi-session A/B ===")
    summary = {}
    for a in arms:
        traj = a["trajectory"]
        final = traj[-1]["score"]["gate_pass"]
        path = " -> ".join(str(s["score"]["gate_pass"]) for s in traj)
        reg = _regression(traj)
        left_trail = any(s["mechanism"]["devlog_entries"] or s["mechanism"]["progress_files"]
                         or s["mechanism"].get("other_notes") for s in traj)
        print(f"  {a['arm']:10} trajectory(gate/12)={path}  final={final}  "
              f"regressions={reg or '[]'}  left_trail={left_trail}")
        summary[a["arm"]] = {"trajectory": [s["score"]["gate_pass"] for s in traj],
                             "final": final, "regressions": reg, "left_trail": left_trail}
    if len(arms) == 2:
        h, n = arms[0]["arm"], arms[1]["arm"]
        d = summary[h]["final"] - summary[n]["final"]
        print(f"  delta final ({h} - {n}): {d:+d}")
        summary["delta_final"] = d
    return summary


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--stub", action="store_true", help="validate pipeline without claude")
    ap.add_argument("--arms", default="both", choices=["both", "harness", "noharness"])
    ap.add_argument("--prime-continuity", action="store_true",
                    help="append an identical neutral handoff instruction to S1/S2 "
                         "(makes the continuity write actually happen, so the read-side "
                         "delta — harness auto-surface vs noharness manual — is testable)")
    ap.add_argument("--out", default="/tmp/ab_multisession.json")
    args = ap.parse_args()

    global PRIME_CONTINUITY
    PRIME_CONTINUITY = args.prime_continuity

    arm_names = ["harness", "noharness"] if args.arms == "both" else [args.arms]
    arms = []
    for arm in arm_names:
        print(f"--- arm {arm} (stub={args.stub}) ---")
        arms.append(run_arm(arm, args.stub))
    summary = compare(arms)
    out = {"build_model": BUILD_MODEL, "stub": args.stub,
           "prime_continuity": PRIME_CONTINUITY, "arms": arms, "summary": summary}
    pathlib.Path(args.out).write_text(json.dumps(out, ensure_ascii=False, default=str, indent=2),
                                      encoding="utf-8")
    print(f"\nwrote {args.out}")


if __name__ == "__main__":
    main()
