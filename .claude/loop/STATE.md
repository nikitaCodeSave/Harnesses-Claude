---
iteration: 0
started: null
mode: pre-smoke
baseline_source: "extracted from .claude/benchmark/reports/T0{1,2,3}-B-ourharness*.json (devlog #24, #25)"
baseline_snapshot:
  T01:
    tokens: {mean: 2114, sigma: 423, n: 1, synthetic_sigma: true}
    turns:  {mean: 9, sigma: 1.8, n: 1, synthetic_sigma: true}
    files:  {mean: 90, sigma: 18, n: 1, synthetic_sigma: true, note: "includes harness inject artifacts"}
    cost_usd: {mean: 0.28, sigma: 0.06, n: 1, synthetic_sigma: true}
    success_rate: 1.0
    fixtures: [sample-py-app]
  T02:
    tokens: {mean: 3002, sigma: 600, n: 1, synthetic_sigma: true}
    turns:  {mean: 13, sigma: 2.6, n: 1, synthetic_sigma: true}
    files:  {mean: 11, sigma: 2.2, n: 1, synthetic_sigma: true}
    cost_usd: {mean: 0.39, sigma: 0.08, n: 1, synthetic_sigma: true}
    success_rate: 1.0
    fixtures: [sample-py-app]
  T03:
    tokens: {mean: 3979, sigma: 746, n: 4, synthetic_sigma: false}
    turns:  {mean: 10.25, sigma: 2.63, n: 4, synthetic_sigma: false}
    files:  {mean: 3, sigma: 0, n: 4, synthetic_sigma: false}
    cost_usd: {mean: 0.39, sigma: 0.08, n: 4, synthetic_sigma: false}
    success_rate: 1.0
    fixtures: [FastApi-Base]
  T04:
    tokens: {mean: 2832, sigma: 566, n: 1, synthetic_sigma: true}
    turns:  {mean: 14, sigma: 2.8, n: 1, synthetic_sigma: true}
    files:  {mean: 4, sigma: 0.8, n: 1, synthetic_sigma: true}
    cost_usd: {mean: 0.43, sigma: 0.09, n: 1, synthetic_sigma: true}
    success_rate: 1.0
    fixtures: [FastApi-Base]
in_flight_hypothesis: null
last_accept_iteration: 0
total_accepted: 0
total_rejected: 0
total_proposals: 0
total_holdout_runs: 0
---

# Loop state

**Status**: pre-smoke. Baseline populated from existing reports. Ready for smoke loop.

## Baseline caveats

- **T01/T02/T04 sigma synthetic**: n=1 единичная точка; sigma = 20% CV proxy (per T03 empirical CV).
  Real sigma replaces synthetic после первого variance pass.
- **T01 files=90 includes harness inject artifacts** (cp -r .claude/ → 87 files счёт). Use files
  metric carefully для T01 — variance guard fitness может игнорировать как noise.
- **T03 files=3 sigma=0** (4 consistent runs) — most reliable baseline точка.

## Smoke target

Ready to run `LOOP_MAX_ITER=2 LOOP_BUDGET_USD=10 ./.claude/loop/run.sh` после corpus + backlog finalization.

## Schema

(см. STATE.md schema documented in `.claude/loop/README.md`)
