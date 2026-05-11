---
iteration: 9
started: 2026-05-11T03:30:00Z
mode: smoke-v2-running
baseline_source: "extracted from .claude/benchmark/reports/T0{1,2,3}-B-ourharness*.json (devlog #24, #25); T01/T02 refreshed iter-0008; T04 first holdout iter-0005"
baseline_snapshot:
  T01:
    tokens: {mean: 1606, sigma: 482, n: 8, synthetic_sigma: true, note: "iter-0008 12in+1594out=1606; baseline updated on accept"}
    turns:  {mean: 7, sigma: 1.8, n: 8, synthetic_sigma: true}
    files:  {mean: 10, sigma: 2.0, n: 8, synthetic_sigma: true, note: "iter-0001 accept — fallback find-newer count, excludes .claude inject artifacts"}
    cost_usd: {mean: 0.233, sigma: 0.06, n: 8, synthetic_sigma: true}
    success_rate: 1.0
    fixtures: [sample-py-app]
  T02:
    tokens: {mean: 2806, sigma: 600, n: 8, synthetic_sigma: true, note: "iter-0008 15in+2791out=2806 (delta -395 vs prev 3201 within 2σ=1200 noise — T02 drift back toward iter-0006 levels)"}
    turns:  {mean: 10, sigma: 2.6, n: 8, synthetic_sigma: true}
    files:  {mean: 11, sigma: 2.2, n: 8, synthetic_sigma: true}
    cost_usd: {mean: 0.333, sigma: 0.08, n: 8, synthetic_sigma: true}
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
last_accept_iteration: 8
total_accepted: 7
total_rejected: 0
total_proposals: 0
total_holdout_runs: 1
last_holdout:
  iteration: 5
  task: T04
  fixture: full-stack-fastapi-template
  result: pass
  notes: "first holdout — no prior to compare for overfit-detect. Tier0=pass; Claude exit=0, 24 turns, $0.91, files=4 (correctly placed in backend/app/* and backend/tests/* per fixture conventions, not src/users/* per task literal); pytest=skipped (PYTEST_TARGETS scope bug — same infra issue blocking T03 since iter-0003). Tokens 11721 (in+out), turns 24, cost $0.91 establish first holdout reading; future holdouts compare against these absolute values for overfit signal. Caveat: T04 baseline_snapshot.T04 (n=1, mean tokens=2832) was historically from removed FastApi-Base fixture (different layout) — corpus.yml T04 fixture_filter mismatch; absolute holdout↔train comparison not meaningful until either (a) T04 task rewritten for full-stack-fastapi-template layout or (b) FastApi-Base re-added as fixture inside .claude/."
---

# Loop state

**Status**: 7 consecutive ACCEPTs (iter-0001 H-001 loop-status, iter-0002 H-002 aggregate-metrics, iter-0003 H-003 stop-hook regression gate, iter-0004 H-004 session-context STATE inject, iter-0006 H-005 cost-warn hook, iter-0007 H-006 bootstrap-fixtures.sh, iter-0008 H-007 variance-report.py) + iter-0005 first HOLDOUT pass (T04 establishes reading; first-holdout pass criteria = Tier0 + Claude exit=0 + no infra crash; no prior holdout to compare against for overfit). T03/T04 both pytest=skipped (headless-runner.sh PYTEST_TARGETS scope bug — only scans top-level tests/ + test_*.py at maxdepth 1; misses fixture's backend/tests/; blocking T03 from fitness since iter-0003, T04 verification narrowed to files_changed only). iter-0008 H-007 added `.claude/loop/variance-report.py` (178 LOC) + `test_variance_report.py` (139 LOC, 12 tests all pass): collects reports across iterations into {(task,fixture): [metrics]}, computes CV (stdev/mean) per metric, flags rows where CV > threshold (default 30%) AND n ≥ min_n (default 3). Run against current 5-iter T01/T02 data: T01 CVs all <8% (1644.8 tokens μ, 130.3 σ → 7.9% CV); T02 CVs all <19% (3005.8 μ, 546.6 σ → 18.2%) — both well within synthetic 20% CV proxy assumed by baseline_snapshot. T03/T04 n=1 each → below_min_n flag, no false alarm. Benchmark T01 (7 turns, $0.233, tokens=1606, files=10, pytest=pass) + T02 (10 turns, $0.333, tokens=2806, files=11, pytest=pass) on sample-py-app; T03 excluded from fitness glob (PYTEST_TARGETS infra blocker since iter-0003). Fitness ACCEPT avg_score=+0.000 (all deltas within 2σ noise: T01 tokens +64 vs μ=1542, T02 tokens -395 vs μ=3201). Open infra debt unchanged: (a) PYTEST_TARGETS recursive scan; (b) T04 fixture_filter↔baseline mismatch; (c) PROMPT.md inject-from path semantic mismatch (proposal candidate).

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
