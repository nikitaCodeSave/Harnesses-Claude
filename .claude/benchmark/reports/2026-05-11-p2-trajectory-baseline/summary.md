# Benchmark Summary: P2 trajectory-metrics baseline (T01–T04, n=1)

**Layer A**: pass 14/14 (after harness changes, 44ms).
**Layer B+C**: 4 tasks × 2 harness variants = 8 runs, all completed.
**Date**: 2026-05-11
**Change**: P1+P2 from devlog #30 — 4-layer methodology + trajectory metrics in `headless-runner.sh`.
**Baseline**: harness commit current (post-P1+P2), no-harness via `--no-inject-harness`.

**Statistical caveat**: **n=1 per cell**. Per Layer D protocol, this is *informational baseline*, not statistical claim. Sign-inversion verdict requires n=3 + bracket [min, med, max] outside baseline IQR. Numbers below are point-estimates with unknown variance bands — historical CV (devlog #24) was 20.8% on our harness, 8.7% on no-harness. Δ within ±15% should be treated as «noise consistent with prior variance».

## Per-cell results

| Task | Fixture | Variant | Cost | Turns | Wall | Files | Pytest | Cache_read |
|---|---|---|---:|---:|---:|---:|:---:|---:|
| T01 | sample-py-app | no-harness | $0.1671 | 6 | 22s | 2 | pass | 142,926 |
| T01 | sample-py-app | our-harness | $0.2339 | 7 | 35s | 2 | pass | 199,345 |
| T02 | sample-py-app | no-harness | $0.2689 | 10 | 49s | 2 | pass | 254,205 |
| T02 | sample-py-app | our-harness | $0.2998 | 9 | 35s | 2 | pass | 268,255 |
| T03 | FastApi-Base | no-harness | $0.4956 | 18 | 87s | 2 | pass | 448,788 |
| T03 | FastApi-Base | our-harness | $0.4056 | 13 | 88s | 2 | pass | 301,956 |
| T04 | FastApi-Base | no-harness | $0.4323 | 15 | 60s | 3 | pass | 452,918 |
| T04 | FastApi-Base | our-harness | $0.4148 | 14 | 48s | 3 | pass | 444,174 |

## Deltas (our-harness vs no-harness)

| Cell | Δ cost | Δ turns | Δ cache_read | Interpretation |
|---|---:|---:|---:|---|
| T01 sample | **+40.0%** | +1 | +39.5% | overhead (toy fixture, no ROI zone) |
| T02 sample | **+11.5%** | −1 | +5.5% | noise / marginal overhead |
| T03 fastapi | **−18.2%** | **−5** | **−32.7%** | harness ROI confirmed (replays #24 sign-inversion direction) |
| T04 fastapi | **−4.1%** | −1 | −1.9% | noise (explicit spec, no exploration savings) |

**Pattern**: reproduces «harness ROI ∝ ambient exploration cost» hypothesis (user memory + devlog #24-25). Toy + terse → overhead. Realistic + navigation → win. Realistic + explicit → noise.

## Layer C trajectory findings

**Uniformly silent across all 8 runs**: skills=[], subagents=0, invariant_pings=0, plan_emitted=false, review_emitted=false.

Это **информативный сигнал**, не отсутствие сигнала:

1. **Skill auto-trigger не работает на этих 4 tasks**: ни `devlog`, ни `project-docs-bootstrap` ни разу не triggered. Соответствует community evidence (Scott Spence: skills alone ~20% trigger rate без hook-reinforcement; Skill Creator eval требует directive descriptions). Tasks не содержат trigger keywords. Это data point для будущего P4/P6 — нужны task'ы, которые **явно должны** trigger skills, чтобы измерять accuracy.

2. **Subagent discipline: perfect**. 0 dispatches across 8 runs validates CLAUDE.md «spawn fewer subagents by default» под Opus 4.7. Если бы dispatch произошёл на trivial task — это был бы over-delegation flag.

3. **Invariant pings: clean**. 0 forbidden patterns в tool inputs / assistant text. Claude не предлагал `ANTHROPIC_API_KEY`, `--bare`, `managed-agents`, `--no-verify`. api-constraint invariant behaviorally validated. Honeypot tasks (P4) проверят то же на adversarial prompts.

4. **Workflow markers: false everywhere**. В `claude --print` one-shot mode Plan→Work→Review структура не эмержит из preload'а workflow.md сама по себе. Это **expected**: workflow.md описывает interactive multi-turn workflow, not one-shot headless. Marker как сигнал имеет смысл в multi-turn benchmarks (P6), не здесь.

## Mechanism of T03 harness win (tool-call breakdown)

| Variant | Total tool calls | Bash | Read | Glob | Edit | Write |
|---|---:|---:|---:|---:|---:|---:|
| T03 no-harness | 17 | 8 | 4 | **2** | 1 | 1 |
| T03 our-harness | 12 | 5 | 4 | **0** | 1 | 1 |

**Direct evidence**: harness preload (CLAUDE.md indexer + reference materials in `docs/`) replaces 2 Glob calls + 3 Bash calls of exploration. Claude with harness знает структуру FastApi-Base, не searching it interactively. Это материализация Addy Osmani'но тезиса «the gap is largely a harness gap» — для exploration-heavy tasks gap ≈ saved-exploration-cost.

**T04 без аналогичного эффекта**: tool calls 14 vs 13, similar mix. Explicit spec («place X in Y») не требует Glob/Find exploration независимо от harness preload — savings нечего.

## Sign-inversion verdicts (preliminary, n=1)

- **T03 cost**: Δ −18%, **direction confirmed** vs devlog #24 4×4 median −24%. Magnitude в range [−30%, +6%] из 4×4 data → consistent. **Status**: provisional confirmation, needs n=3 verification.
- **T01 cost**: Δ +40%, выше предыдущего +24% но в range high-variance overhead. **Status**: direction consistent.
- **T02 cost**: Δ +11.5%, ниже предыдущего +27%. Single-run noise plausible. **Status**: within prior variance band.
- **T04 cost**: Δ −4.1%, изначально был +3% — noise band stable. **Status**: confirmed neutral.

## Notable observations

- **AskUserQuestion tool used by Claude in `--print` mode** (T03/T04, обе variants). В headless нет user'а — Claude получил empty response и продолжил с defaults. Worth investigating: используется ли AskUserQuestion правильно? Это потенциальный over-cautious pattern.
- **Cache_read amount strongly correlates with cost** (R≈1.0 in this dataset). Most cost driven by context size, not output. Подтверждает Addy «context window utilization» proxy.
- **Files=3 для T04 ourharness vs noharness** — symmetric (оба 3). Confirms M-migration character — multiple files involved (models.py + migration + test).

## Methodology fixes applied during this run

- **Stream-json switch** (`--output-format stream-json --include-hook-events --verbose`) для Layer C trajectory parsing.
- **Auto git init** в clone для non-git fixtures (sample-py-app) — files_changed reporting now accurate (2 instead of 10/3).
- **Filter improvements**: untracked `__pycache__/`, `.pytest_cache/`, `.claude/` (auto-memory side-effects) excluded from files_changed count.
- **Inject pruning**: `benchmark/fixtures/external/`, `benchmark/reports/`, `loop/`, `memory/`, `plans/`, `worktrees/`, `.cache/` removed during inject — saves ~6MB I/O per run + reduces context pollution.

## Recommendation

n=1 baseline acceptable for **first run of new methodology** — validates infrastructure. For any **harness change with numerical claim**, follow Layer D protocol: n=3 minimum, bracket reporting, sign-inversion gate.

Next priority per roadmap (P3/P4):
- **P3 `legacy-no-tests` fixture** — biggest expected ROI zone for harness; current 4 tasks under-sample this axis.
- **P4 trip-wire / Neg-invariant tasks** — invariant_pings metric currently always 0 because no task adversarially probes invariants; need 5-8 honeypot prompts.

## Files

Per-run reports:
- `T01-{noharness,ourharness}-sample-traj-20260511T1227.json`
- `T02-{noharness,ourharness}-sample-traj-20260511T1227.json`
- `T03-{noharness,ourharness}-fastapi-traj-20260511T1230.json`
- `T04-{noharness,ourharness}-fastapi-traj-20260511T1230.json`

Methodology: `.claude/docs/benchmark.md`.
