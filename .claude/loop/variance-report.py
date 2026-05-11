#!/usr/bin/env python3
"""Per-task variance report — flag high-CV tasks for sign-inversion early-warn.

Reads loop reports across iterations; for each (task, fixture) computes
coefficient of variation (CV = stdev / mean) of tokens, turns, files, cost.
Flags any (task, metric) pair whose CV exceeds threshold (default 30%) —
high variance means fitness accept/reject signal on that task is unreliable
(per devlog #25 sign-inversion: T03 flipped sign between fixtures due to
unmeasured fixture-side variance, producing false ACCEPTs).

Reads:
  - .claude/loop/reports/iter-NNNN-<task>-<fixture>.json
  - .claude/loop/STATE.md baseline_snapshot (optional; used to compare
    observed CV against synthetic 20% CV proxy)

Writes (stdout):
  - default: human-readable table per (task, fixture) — n, mean, stdev, CV%, flag
  - --json: machine-readable JSON
  - --flagged-only: print only rows with CV > threshold

Exit:
  0 always when --no-fail (default).
  1 if --fail-on-flag set AND ≥1 flagged row exists.

Usage:
  variance-report.py [--reports-glob GLOB] [--state PATH]
                     [--threshold PCT] [--min-n N]
                     [--json] [--flagged-only] [--fail-on-flag]
"""

from __future__ import annotations
import argparse
import json
import re
import sys
from pathlib import Path
from statistics import mean as _mean, stdev as _stdev
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
    """Extract canonical metrics (shared schema with aggregate-metrics.py)."""
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
    }


def collect(reports_glob: str) -> dict[tuple[str, str], list[dict]]:
    """Returns {(task, fixture): [metrics, ...]} across all iterations."""
    by_key: dict[tuple[str, str], list[dict]] = {}
    for p in sorted(Path().glob(reports_glob)):
        parsed = parse_iter_filename(p)
        if not parsed:
            continue
        _iter_n, task_id, fixture = parsed
        try:
            r = load_report(p)
        except (json.JSONDecodeError, OSError):
            continue
        by_key.setdefault((task_id, fixture), []).append(extract_metrics(r))
    return by_key


METRICS = ("tokens", "turns", "files", "cost_usd")


def cv_of(values: Iterable[float]) -> tuple[float, float, float]:
    """Returns (mean, stdev, cv_pct). cv_pct = 0 when mean == 0 or n < 2."""
    vs = [float(v) for v in values]
    if len(vs) < 2:
        return (vs[0] if vs else 0.0, 0.0, 0.0)
    m = _mean(vs)
    s = _stdev(vs)
    cv = (s / m * 100.0) if m else 0.0
    return m, s, cv


def compute(by_key: dict[tuple[str, str], list[dict]],
            threshold_pct: float,
            min_n: int) -> list[dict]:
    """Returns one row per (task, fixture, metric); flag set if CV > threshold."""
    rows: list[dict] = []
    for (task, fixture), ms in sorted(by_key.items()):
        n = len(ms)
        for metric in METRICS:
            m, s, cv = cv_of(m_[metric] for m_ in ms)
            flag = (n >= min_n) and (cv > threshold_pct)
            rows.append({
                "task": task,
                "fixture": fixture,
                "metric": metric,
                "n": n,
                "mean": m,
                "stdev": s,
                "cv_pct": cv,
                "flag": flag,
                "below_min_n": n < min_n,
            })
    return rows


def print_table(rows: list[dict], threshold_pct: float, flagged_only: bool) -> None:
    visible = [r for r in rows if r["flag"]] if flagged_only else rows
    if not visible:
        msg = "(no rows flagged)" if flagged_only else "(no reports found)"
        print(msg)
        return
    print(f"{'task':<5} {'fixture':<32} {'metric':<9} {'n':>2}  "
          f"{'mean':>10}  {'stdev':>10}  {'CV%':>6}  flag")
    print("-" * 88)
    for r in visible:
        mark = "FLAG" if r["flag"] else ("n<min" if r["below_min_n"] else "")
        print(f"{r['task']:<5} {r['fixture'][:32]:<32} {r['metric']:<9} "
              f"{r['n']:>2}  {r['mean']:>10.2f}  {r['stdev']:>10.2f}  "
              f"{r['cv_pct']:>6.1f}  {mark}")
    n_flagged = sum(1 for r in rows if r["flag"])
    print(f"\nthreshold: CV > {threshold_pct:.0f}%; flagged rows: {n_flagged}/{len(rows)}")


def main() -> int:
    p = argparse.ArgumentParser(description=(__doc__ or "").split("\n", 1)[0])
    p.add_argument("--reports-glob", default=".claude/loop/reports/iter-*.json")
    p.add_argument("--state", default=".claude/loop/STATE.md")
    p.add_argument("--threshold", type=float, default=30.0,
                   help="CV%% above which row is flagged (default 30)")
    p.add_argument("--min-n", type=int, default=3,
                   help="minimum replicas before CV is meaningful (default 3)")
    p.add_argument("--json", action="store_true")
    p.add_argument("--flagged-only", action="store_true")
    p.add_argument("--fail-on-flag", action="store_true",
                   help="exit 1 if any row flagged")
    args = p.parse_args()

    by_key = collect(args.reports_glob)
    rows = compute(by_key, args.threshold, args.min_n)

    if args.json:
        out = {
            "threshold_pct": args.threshold,
            "min_n": args.min_n,
            "rows": rows,
            "n_flagged": sum(1 for r in rows if r["flag"]),
        }
        json.dump(out, sys.stdout, indent=2, default=str)
        sys.stdout.write("\n")
    else:
        print_table(rows, args.threshold, args.flagged_only)

    if args.fail_on_flag and any(r["flag"] for r in rows):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
