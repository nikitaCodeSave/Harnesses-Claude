#!/usr/bin/env python3
"""Process metrics for the N / C arms (README, "Стенд «команды кита»").

  process.py [results dir]   — one row per run, then a per-task/arm summary

interview  the first agent message asks a question and the owner answered at least once
spec       the final patch adds a file under specs/ or SPEC.md
evidence   the last agent message names pytest and a "N passed" count
"""
import json
import pathlib
import re
import sys

RESULTS = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else pathlib.Path(__file__).parent / "results-harness")


def agent_messages(transcript):
    blocks = re.split(r"^### \[[^\]]+\] ", transcript, flags=re.M)
    return [b.split("\n", 1)[1].strip() for b in blocks if b.startswith("agent")]


def run_metrics(d):
    t = (d / "transcript.md").read_text() if (d / "transcript.md").exists() else ""
    patch = (d / "final.patch").read_text() if (d / "final.patch").exists() else ""
    score = json.loads((d / "score.json").read_text()) if (d / "score.json").exists() else {}
    msgs = agent_messages(t)
    first, last = (msgs[0], msgs[-1]) if msgs else ("", "")
    turns = score.get("user_turns", 0)
    acc = score.get("acceptance", {})
    return {
        "run": d.name,
        "interview": "?" in first and turns >= 1,
        "spec": bool(re.search(r"^\+\+\+ b/(specs/[^\n]+|SPEC\.md)$", patch, re.M)),
        "evidence": "pytest" in last and bool(re.search(r"\d+ passed", last)),
        "acceptance": round(100 * acc["passed"] / acc["total"], 1) if acc.get("total") else None,
        "turns": turns,
    }


def main():
    rows = []
    for tdir in sorted(p for p in RESULTS.iterdir() if p.is_dir()):
        for d in sorted(p for p in tdir.iterdir() if p.is_dir()):
            m = run_metrics(d)
            m["task"] = tdir.name
            rows.append(m)
            print(f"{tdir.name:28} {m['run']:5} interview={m['interview']!s:5} spec={m['spec']!s:5} "
                  f"evidence={m['evidence']!s:5} acceptance={m['acceptance']} turns={m['turns']}")
    print("\n| task | arm | n | interview | spec | evidence | 100% acceptance |\n|---|---|---|---|---|---|---|")
    for task in sorted({r["task"] for r in rows}):
        for arm in "NC":
            rs = [r for r in rows if r["task"] == task and r["run"].startswith(arm + "-")]
            if rs:
                c = lambda k: sum(1 for r in rs if r[k])
                full = sum(1 for r in rs if r["acceptance"] == 100.0)
                print(f"| {task} | {arm} | {len(rs)} | {c('interview')}/{len(rs)} | {c('spec')}/{len(rs)} | "
                      f"{c('evidence')}/{len(rs)} | {full}/{len(rs)} |")


if __name__ == "__main__":
    main()
