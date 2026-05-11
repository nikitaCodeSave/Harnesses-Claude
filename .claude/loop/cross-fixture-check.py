#!/usr/bin/env python3
"""Cross-fixture variance comparator — flag same-task sign inversion across fixtures.

Reads loop reports across iterations; for each task observed on ≥2 fixtures
computes per-fixture mean and reports two diagnostics:

  1. SPREAD: relative cross-fixture spread per metric = max_mean / min_mean - 1.
     Flag when spread > --spread-threshold (default 30%) AND each fixture has
     n ≥ --min-n reports. Spread means same task gives substantially different
     metrics on different fixtures — accept/reject signal on train fixture
     might not generalize.

  2. SIGN_INVERSION: when STATE.md baseline is provided, compute per-fixture
     delta vs baseline_snapshot[task].<metric>.mean. If two fixtures'
     baseline-relative deltas have OPPOSITE signs AND each |delta| exceeds
     --noise-threshold (default 10%) → flag SIGN_INVERSION. This is the
     direct lesson of devlog #25: T03 flipped sign between FastApi-Base and
     full-stack-fastapi-template, producing a false ACCEPT.

Reads:
  - .claude/loop/reports/iter-NNNN-<task>-<fixture>.json
  - .claude/loop/STATE.md baseline_snapshot (optional; needed only for
    SIGN_INVERSION detection)

Writes (stdout):
  - default: human-readable table per (task, metric) — fixture means, spread%,
    sign-inversion flag
  - --json: machine-readable JSON
  - --flagged-only: only rows with any flag

Exit:
  0 always when --no-fail (default).
  1 if --fail-on-flag set AND ≥1 row flagged (spread OR sign_inversion).

Usage:
  cross-fixture-check.py [--reports-glob GLOB] [--state PATH]
                          [--spread-threshold PCT] [--noise-threshold PCT]
                          [--min-n N]
                          [--json] [--flagged-only] [--fail-on-flag]
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
    """Extract canonical metrics (shared schema with variance-report.py)."""
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


def collect(reports_glob: str) -> dict[str, dict[str, list[dict]]]:
    """Returns {task: {fixture: [metrics, ...]}} across all iterations."""
    by_task: dict[str, dict[str, list[dict]]] = {}
    for p in sorted(Path().glob(reports_glob)):
        parsed = parse_iter_filename(p)
        if not parsed:
            continue
        _iter_n, task_id, fixture = parsed
        try:
            r = load_report(p)
        except (json.JSONDecodeError, OSError):
            continue
        by_task.setdefault(task_id, {}).setdefault(fixture, []).append(extract_metrics(r))
    return by_task


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


METRICS = ("tokens", "turns", "files", "cost_usd")


def mean(values: Iterable[float]) -> float:
    vs = [float(v) for v in values]
    return _mean(vs) if vs else 0.0


def spread_pct(values: Iterable[float]) -> float:
    """Returns (max/min - 1) * 100 percent. 0 when min == 0 or single value."""
    vs = [float(v) for v in values]
    if len(vs) < 2:
        return 0.0
    lo, hi = min(vs), max(vs)
    if lo == 0:
        return 0.0
    return (hi / lo - 1.0) * 100.0


def baseline_mean(baseline: dict | None, task: str, metric: str) -> float:
    if not baseline:
        return 0.0
    t = baseline.get(task) or {}
    m = t.get(metric) or {}
    return float(m.get("mean", 0.0))


def compute(by_task: dict[str, dict[str, list[dict]]],
            baseline: dict | None,
            spread_threshold_pct: float,
            noise_threshold_pct: float,
            min_n: int) -> list[dict]:
    """One row per (task, metric) where task has ≥2 fixtures observed."""
    rows: list[dict] = []
    for task, by_fixture in sorted(by_task.items()):
        fixtures = sorted(by_fixture.keys())
        if len(fixtures) < 2:
            continue
        for metric in METRICS:
            fx_means: dict[str, float] = {}
            fx_n: dict[str, int] = {}
            for fx in fixtures:
                ms = by_fixture[fx]
                fx_means[fx] = mean(m[metric] for m in ms)
                fx_n[fx] = len(ms)
            sp = spread_pct(fx_means.values())
            all_min_n = all(n >= min_n for n in fx_n.values())
            spread_flag = all_min_n and sp > spread_threshold_pct

            base = baseline_mean(baseline, task, metric)
            sign_inversion = False
            deltas_pct: dict[str, float] = {}
            if base > 0:
                for fx, m_val in fx_means.items():
                    deltas_pct[fx] = (m_val - base) / base * 100.0
                exceed = {fx: d for fx, d in deltas_pct.items()
                          if abs(d) > noise_threshold_pct}
                if len(exceed) >= 2:
                    signs = {1 if d > 0 else -1 for d in exceed.values()}
                    if len(signs) > 1:
                        sign_inversion = True

            rows.append({
                "task": task,
                "metric": metric,
                "fixtures": fixtures,
                "fixture_means": fx_means,
                "fixture_n": fx_n,
                "spread_pct": sp,
                "spread_flag": spread_flag,
                "baseline_mean": base,
                "deltas_pct": deltas_pct,
                "sign_inversion": sign_inversion,
                "below_min_n": not all_min_n,
            })
    return rows


def any_flag(row: dict) -> bool:
    return bool(row["spread_flag"] or row["sign_inversion"])


def print_table(rows: list[dict], spread_th: float, noise_th: float,
                flagged_only: bool) -> None:
    visible = [r for r in rows if any_flag(r)] if flagged_only else rows
    if not visible:
        if flagged_only:
            print("(no rows flagged)")
        else:
            print("(no tasks with ≥2 fixtures observed)")
        return
    print(f"{'task':<5} {'metric':<9} {'fixtures':<40} "
          f"{'spread%':>8}  {'flags':<24}")
    print("-" * 92)
    for r in visible:
        fx_summary = ",".join(f"{fx[:14]}={r['fixture_means'][fx]:.0f}"
                              for fx in r["fixtures"])
        flags = []
        if r["spread_flag"]:
            flags.append("SPREAD")
        if r["sign_inversion"]:
            flags.append("SIGN_INV")
        if r["below_min_n"] and not flags:
            flags.append("n<min")
        flag_s = ",".join(flags)
        print(f"{r['task']:<5} {r['metric']:<9} {fx_summary[:40]:<40} "
              f"{r['spread_pct']:>7.1f}  {flag_s:<24}")
    n_spread = sum(1 for r in rows if r["spread_flag"])
    n_sign = sum(1 for r in rows if r["sign_inversion"])
    print(f"\nspread threshold: > {spread_th:.0f}%; noise threshold: > {noise_th:.0f}%; "
          f"spread-flagged: {n_spread}; sign-inversion: {n_sign}; total rows: {len(rows)}")


def main() -> int:
    p = argparse.ArgumentParser(description=(__doc__ or "").split("\n", 1)[0])
    p.add_argument("--reports-glob", default=".claude/loop/reports/iter-*.json")
    p.add_argument("--state", default=".claude/loop/STATE.md")
    p.add_argument("--spread-threshold", type=float, default=30.0,
                   help="cross-fixture spread%% above which row is flagged (default 30)")
    p.add_argument("--noise-threshold", type=float, default=10.0,
                   help="per-fixture |delta vs baseline|%% below which delta is "
                        "treated as noise for sign-inversion detection (default 10)")
    p.add_argument("--min-n", type=int, default=2,
                   help="minimum reports per fixture before spread is meaningful "
                        "(default 2)")
    p.add_argument("--json", action="store_true")
    p.add_argument("--flagged-only", action="store_true")
    p.add_argument("--fail-on-flag", action="store_true",
                   help="exit 1 if any row flagged (SPREAD or SIGN_INVERSION)")
    args = p.parse_args()

    by_task = collect(args.reports_glob)
    baseline = load_state_baseline(Path(args.state))
    rows = compute(by_task, baseline, args.spread_threshold,
                   args.noise_threshold, args.min_n)

    if args.json:
        out = {
            "spread_threshold_pct": args.spread_threshold,
            "noise_threshold_pct": args.noise_threshold,
            "min_n": args.min_n,
            "rows": rows,
            "n_spread_flagged": sum(1 for r in rows if r["spread_flag"]),
            "n_sign_inversion": sum(1 for r in rows if r["sign_inversion"]),
        }
        json.dump(out, sys.stdout, indent=2, default=str)
        sys.stdout.write("\n")
    else:
        print_table(rows, args.spread_threshold, args.noise_threshold,
                    args.flagged_only)

    if args.fail_on_flag and any(any_flag(r) for r in rows):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
