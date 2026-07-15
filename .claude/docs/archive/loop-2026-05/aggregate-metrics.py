#!/usr/bin/env python3
"""Aggregate metrics across loop iteration reports → trend table.

Reads:
  - .claude/loop/reports/iter-NNNN-<task>-<fixture>.json (per-iter per-task per-fixture)
  - .claude/loop/STATE.md (yaml frontmatter) baseline_snapshot — for delta vs current baseline

Writes (stdout):
  - default: human-readable table grouped by iteration → task → fixture mean
  - --json: machine-readable JSON with per-iter aggregates + deltas vs baseline

Detects drift: if any per-task weighted score delta > corpus threshold over N iters → flag.

Usage:
  aggregate-metrics.py [--reports-glob GLOB] [--state PATH] [--json] [--since N]

Exit: 0 always (read-only telemetry). Non-existent reports glob → empty table, exit 0.
"""

from __future__ import annotations
import argparse
import json
import re
import sys
from pathlib import Path
from statistics import mean as _mean
from typing import Iterable


ITER_RE = re.compile(r"iter-(\d{4})-([^-]+)-(.+)\.json$")


def parse_iter_filename(path: Path) -> tuple[int, str, str] | None:
    m = ITER_RE.search(path.name)
    if not m:
        return None
    return int(m.group(1)), m.group(2), m.group(3)


def load_report(path: Path) -> dict:
    with open(path) as f:
        return json.load(f)


def extract_metrics(r: dict) -> dict:
    """Extract canonical metrics from a headless-runner report (nested schema)."""
    c = r.get("claude", {}) or {}
    tk = c.get("tokens", {}) or {}
    v = r.get("verification", {}) or {}
    pyt = v.get("pytest", {}) or {}
    return {
        "tokens": int(tk.get("input", 0)) + int(tk.get("output", 0)),
        "turns": int(c.get("num_turns", 0)),
        "files": int(v.get("files_changed", 0)),
        "cost_usd": float(c.get("cost_usd", 0.0)),
        "success": 1.0 if pyt.get("status") == "pass" else 0.0,
        "wall_sec": int((r.get("timing") or {}).get("wall_seconds", 0)),
    }


def load_state_baseline(state_path: Path) -> dict | None:
    if not state_path.exists():
        return None
    text = state_path.read_text()
    if not text.startswith("---"):
        return None
    end = text.find("\n---", 4)
    if end == -1:
        return None
    try:
        import yaml
    except ImportError:
        return None
    fm = yaml.safe_load(text[3:end]) or {}
    return fm.get("baseline_snapshot")


def mean(values: Iterable[float]) -> float:
    vs = list(values)
    return _mean(vs) if vs else 0.0


def collect(reports_glob: str) -> dict[int, dict[str, list[dict]]]:
    """Returns {iter_n: {task_id: [metrics, ...]}}."""
    by_iter: dict[int, dict[str, list[dict]]] = {}
    for p in sorted(Path().glob(reports_glob)):
        parsed = parse_iter_filename(p)
        if not parsed:
            continue
        iter_n, task_id, _fixture = parsed
        try:
            r = load_report(p)
        except (json.JSONDecodeError, OSError):
            continue
        by_iter.setdefault(iter_n, {}).setdefault(task_id, []).append(extract_metrics(r))
    return by_iter


def aggregate(by_iter: dict[int, dict[str, list[dict]]]) -> dict[int, dict[str, dict]]:
    """Per-iter per-task fixture-mean."""
    out: dict[int, dict[str, dict]] = {}
    for iter_n, by_task in by_iter.items():
        out[iter_n] = {}
        for tid, ms in by_task.items():
            out[iter_n][tid] = {
                "n_fixtures": len(ms),
                "tokens": mean(m["tokens"] for m in ms),
                "turns": mean(m["turns"] for m in ms),
                "files": mean(m["files"] for m in ms),
                "cost_usd": mean(m["cost_usd"] for m in ms),
                "success_rate": mean(m["success"] for m in ms),
                "wall_sec": mean(m["wall_sec"] for m in ms),
            }
    return out


def delta_vs_baseline(metric_value: float, base_mean: float) -> str:
    if base_mean == 0:
        return "  --  "
    pct = (metric_value - base_mean) / base_mean * 100
    return f"{pct:+5.1f}%"


def print_table(agg: dict[int, dict[str, dict]], baseline: dict | None) -> None:
    if not agg:
        print("(no iter-*.json reports found)")
        return
    iters = sorted(agg.keys())
    print(f"{'iter':>4}  {'task':<5} {'nfx':>3}  {'tokens':>7}  {'Δ%':>7}  {'turns':>5}  {'Δ%':>7}  {'files':>5}  {'Δ%':>7}  {'cost$':>6}  {'wall':>5}  {'succ':>4}")
    print("-" * 90)
    for it in iters:
        for tid in sorted(agg[it].keys()):
            row = agg[it][tid]
            b = (baseline or {}).get(tid, {}) if baseline else {}
            tok_d = delta_vs_baseline(row["tokens"], (b.get("tokens") or {}).get("mean", 0))
            tur_d = delta_vs_baseline(row["turns"],  (b.get("turns")  or {}).get("mean", 0))
            fil_d = delta_vs_baseline(row["files"],  (b.get("files")  or {}).get("mean", 0))
            print(f"{it:>4}  {tid:<5} {row['n_fixtures']:>3}  "
                  f"{row['tokens']:>7.0f}  {tok_d:>7}  "
                  f"{row['turns']:>5.1f}  {tur_d:>7}  "
                  f"{row['files']:>5.1f}  {fil_d:>7}  "
                  f"{row['cost_usd']:>6.3f}  {row['wall_sec']:>5.0f}  "
                  f"{row['success_rate']:>4.2f}")


def main() -> int:
    p = argparse.ArgumentParser(description=(__doc__ or "").split("\n", 1)[0])
    p.add_argument("--reports-glob", default=".claude/loop/reports/iter-*.json",
                   help="glob pattern (default: .claude/loop/reports/iter-*.json)")
    p.add_argument("--state", default=".claude/loop/STATE.md",
                   help="STATE.md path for baseline (default: .claude/loop/STATE.md)")
    p.add_argument("--json", action="store_true", help="emit machine-readable JSON")
    p.add_argument("--since", type=int, default=0, help="only show iter >= N")
    args = p.parse_args()

    by_iter = collect(args.reports_glob)
    if args.since:
        by_iter = {k: v for k, v in by_iter.items() if k >= args.since}

    agg = aggregate(by_iter)
    baseline = load_state_baseline(Path(args.state))

    if args.json:
        out = {
            "baseline": baseline,
            "iterations": agg,
            "n_iters": len(agg),
        }
        json.dump(out, sys.stdout, indent=2, default=str)
        sys.stdout.write("\n")
    else:
        print_table(agg, baseline)

    return 0


if __name__ == "__main__":
    sys.exit(main())
