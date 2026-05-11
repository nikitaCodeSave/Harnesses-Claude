---
iteration: 10
started: 2026-05-11T03:30:00Z
mode: smoke-v2-running
baseline_source: "extracted from .claude/benchmark/reports/T0{1,2,3}-B-ourharness*.json (devlog #24, #25); T01/T02 refreshed iter-0009; T04 first holdout iter-0005"
baseline_snapshot:
  T01:
    tokens: {mean: 1766, sigma: 482, n: 9, synthetic_sigma: true, note: "iter-0009 12in+1754out=1766; baseline updated on accept"}
    turns:  {mean: 7, sigma: 1.8, n: 9, synthetic_sigma: true}
    files:  {mean: 10, sigma: 2.0, n: 9, synthetic_sigma: true, note: "iter-0001 accept — fallback find-newer count, excludes .claude inject artifacts"}
    cost_usd: {mean: 0.238, sigma: 0.06, n: 9, synthetic_sigma: true}
    success_rate: 1.0
    fixtures: [sample-py-app]
  T02:
    tokens: {mean: 2344, sigma: 600, n: 9, synthetic_sigma: true, note: "iter-0009 15in+2329out=2344 (delta -462 vs prev 2806 within 2σ=1200 noise — T02 drift further toward low end of window)"}
    turns:  {mean: 10, sigma: 2.6, n: 9, synthetic_sigma: true}
    files:  {mean: 11, sigma: 2.2, n: 9, synthetic_sigma: true}
    cost_usd: {mean: 0.322, sigma: 0.08, n: 9, synthetic_sigma: true}
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
last_accept_iteration: 9
total_accepted: 8
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

**Status**: 8 consecutive ACCEPTs (iter-0001 H-001 loop-status, iter-0002 H-002 aggregate-metrics, iter-0003 H-003 stop-hook regression gate, iter-0004 H-004 session-context STATE inject, iter-0006 H-005 cost-warn hook, iter-0007 H-006 bootstrap-fixtures.sh, iter-0008 H-007 variance-report.py, iter-0009 H-008 cross-fixture-check.py) + iter-0005 first HOLDOUT pass. T03/T04 both pytest=skipped (headless-runner.sh PYTEST_TARGETS scope bug since iter-0003). iter-0009 H-008 added `.claude/loop/cross-fixture-check.py` (272 LOC) + `test_cross_fixture_check.py` (211 LOC, 17 tests all pass): groups reports by task→fixture→[metrics], for tasks with ≥2 fixtures computes (a) cross-fixture spread = max/min - 1 per metric (flag when > 30% AND each fixture has n ≥ min_n=2 reports); (b) sign-inversion vs baseline_snapshot — when ≥2 fixtures' baseline-relative deltas have OPPOSITE signs AND each |delta| > noise threshold (10%) → flag. Direct #25 lesson: T03 had flipped sign between FastApi-Base and full-stack-fastapi-template causing false ACCEPT. Real-data run against current iter-0002..iter-0009 reports: T01/T02 only on sample-py-app, T03/T04 only on full-stack-fastapi-template — no task has ≥2 fixtures yet → tool correctly reports "(no tasks with ≥2 fixtures observed)". Synthetic CLI smoke: 1000 vs 3000 tokens across two fixtures → spread=200% flagged; with synthetic baseline=2000 fxA=-50%/fxB=+50% → SIGN_INVERSION flagged; --fail-on-flag → exit 1. yaml import gracefully falls back when not available (same pattern as aggregate-metrics.py / variance-report.py — sign_inversion needs yaml for STATE.md parse; spread doesn't). Benchmark T01 (7 turns, $0.238, tokens=1766, files=10, pytest=pass) + T02 (10 turns, $0.322, tokens=2344, files=11, pytest=pass) on sample-py-app; T03 excluded from fitness glob (PYTEST_TARGETS infra blocker since iter-0003). Fitness ACCEPT avg_score=+0.000 (T01 tokens delta +160 vs μ=1606 within 2σ=964; T02 tokens delta -462 vs μ=2806 within 2σ=1200; turns/files/cost all within noise). Open infra debt unchanged: (a) PYTEST_TARGETS recursive scan; (b) T04 fixture_filter↔baseline mismatch; (c) PROMPT.md inject-from path semantic mismatch; (d) NEW — corpus has zero task observed on ≥2 fixtures, so cross-fixture-check.py is currently a tripwire-only tool (active value emerges when same task ran on multi-fixture).

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
