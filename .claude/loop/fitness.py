#!/usr/bin/env python3
"""Deterministic accept/reject scorer for self-improvement loop.

Reads:
  - STATE.md (yaml frontmatter) → baseline_snapshot {task: {metric: {mean, sigma}, ...}, success_rate}
  - candidate reports (glob of JSONs from headless-runner) → per-task metrics
  - corpus.yml → fitness weights + thresholds + variance.sigma_multiplier
  - --tier0 pass|fail status

Writes (stdout):
  ACCEPT
  REJECT: <reason>

Exit: 0 = ACCEPT, 1 = REJECT, 2 = usage/IO error.

Logic:
  1. tier0 != pass → REJECT
  2. success_rate < baseline → REJECT (hard)
  3. For each train task: variance-check delta (|delta| <= 2σ → noise, no signal)
  4. Aggregate weighted_score = 0.5·tokens_pct + 0.3·turns_norm + 0.2·files_norm
  5. weighted_score regression > threshold → REJECT
  6. else → ACCEPT
"""

from __future__ import annotations
import argparse
import glob
import json
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    print("REJECT: python yaml module missing (pip install pyyaml)", file=sys.stderr)
    sys.exit(2)


def load_state_baseline(state_md_path: Path) -> dict | None:
    """Extract YAML frontmatter baseline_snapshot from STATE.md."""
    text = state_md_path.read_text()
    if not text.startswith("---"):
        return None
    end = text.find("\n---", 4)
    if end == -1:
        return None
    fm = yaml.safe_load(text[3:end]) or {}
    return fm.get("baseline_snapshot")


def load_corpus(corpus_path: Path) -> dict:
    return yaml.safe_load(corpus_path.read_text())


def load_candidate_reports(report_glob: str) -> dict[str, list[dict]]:
    """Returns {task_id: [report, ...]} aggregated across fixtures."""
    by_task: dict[str, list[dict]] = {}
    for path in sorted(glob.glob(report_glob)):
        with open(path) as f:
            r = json.load(f)
        tid = r.get("task_id") or r.get("task") or Path(path).stem.split("-")[0]
        by_task.setdefault(tid, []).append(r)
    return by_task


def mean(values: list[float]) -> float:
    return sum(values) / len(values) if values else 0.0


def compute_task_metrics(reports: list[dict]) -> dict[str, float]:
    """Aggregate per-fixture reports for one task → mean tokens/turns/files/success."""
    if not reports:
        return {"tokens": 0, "turns": 0, "files": 0, "success_rate": 0.0}
    tokens = mean([r.get("tokens_total", r.get("tokens", 0)) for r in reports])
    turns = mean([r.get("turns", 0) for r in reports])
    files = mean([r.get("files_touched", r.get("files", 0)) for r in reports])
    success_vals = [1.0 if r.get("success") else 0.0 for r in reports]
    success_rate = mean(success_vals)
    return {"tokens": tokens, "turns": turns, "files": files, "success_rate": success_rate}


def variance_pass(delta: float, baseline_sigma: float, multiplier: float) -> bool:
    """True if |delta| exceeds noise threshold (worth treating as signal)."""
    return abs(delta) > baseline_sigma * multiplier


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--baseline-state", required=True)
    p.add_argument("--candidate-reports", required=True, help="glob pattern")
    p.add_argument("--tier0", required=True, choices=["pass", "fail"])
    p.add_argument("--corpus", default=None, help="path to corpus.yml (default: <loop>/corpus.yml)")
    args = p.parse_args()

    if args.tier0 != "pass":
        print("REJECT: tier0-fail")
        return 1

    state_path = Path(args.baseline_state)
    corpus_path = Path(args.corpus) if args.corpus else state_path.parent / "corpus.yml"

    baseline = load_state_baseline(state_path)
    if not baseline:
        print("REJECT: baseline_snapshot missing — run variance baseline first")
        return 1

    corpus = load_corpus(corpus_path)
    weights = corpus["fitness"]["weights"]
    thresholds = corpus["fitness"]["thresholds"]
    sigma_mult = corpus["variance"]["sigma_multiplier"]

    candidate = load_candidate_reports(args.candidate_reports)
    if not candidate:
        print(f"REJECT: no candidate reports matched {args.candidate_reports}")
        return 1

    # Aggregate per-task candidate metrics
    cand_metrics = {tid: compute_task_metrics(rs) for tid, rs in candidate.items()}

    # Hard constraint: success_rate
    train_tasks = [
        tid for tid, cfg in corpus["tasks"].items()
        if cfg.get("split") == "train" and tid in cand_metrics
    ]
    if not train_tasks:
        print("REJECT: no training tasks in candidate reports")
        return 1

    for tid in train_tasks:
        cand_sr = cand_metrics[tid]["success_rate"]
        base_sr = baseline.get(tid, {}).get("success_rate", 1.0)
        if cand_sr < base_sr:
            print(f"REJECT: task {tid} success_rate {cand_sr:.2f} < baseline {base_sr:.2f}")
            return 1

    # Weighted cost score with variance guard
    deltas_by_task: dict[str, dict] = {}
    for tid in train_tasks:
        b = baseline.get(tid, {})
        c = cand_metrics[tid]

        # variance-guarded deltas (set to 0 if within noise)
        d = {}
        for metric in ("tokens", "turns", "files"):
            base_mean = b.get(metric, {}).get("mean", 0.0)
            base_sigma = b.get(metric, {}).get("sigma", 0.0)
            raw_delta = c[metric] - base_mean
            if variance_pass(raw_delta, base_sigma, sigma_mult):
                d[metric] = raw_delta
            else:
                d[metric] = 0.0  # noise, ignore
        deltas_by_task[tid] = d

    # Weighted score: normalize each metric by baseline mean (% delta for tokens, abs for turns/files)
    def weighted_score_one(tid: str) -> float:
        b = baseline.get(tid, {})
        d = deltas_by_task[tid]

        tok_base = b.get("tokens", {}).get("mean", 1.0) or 1.0
        turns_base = b.get("turns", {}).get("mean", 1.0) or 1.0
        files_base = b.get("files", {}).get("mean", 1.0) or 1.0

        return (
            weights["tokens"] * (d["tokens"] / tok_base)
            + weights["turns"] * (d["turns"] / turns_base)
            + weights["files"] * (d["files"] / files_base)
        )

    per_task_score = {tid: weighted_score_one(tid) for tid in train_tasks}
    avg_score = mean(list(per_task_score.values()))
    max_score = thresholds["weighted_score_delta_max"]

    if avg_score > max_score:
        worst_tid, worst_score = max(per_task_score.items(), key=lambda kv: kv[1])
        print(
            f"REJECT: avg weighted score delta {avg_score:+.3f} > threshold {max_score:.3f} "
            f"(worst task {worst_tid}: {worst_score:+.3f})"
        )
        return 1

    print(f"ACCEPT (avg_score={avg_score:+.3f}, threshold={max_score:.3f})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
