# Harness Benchmark Infrastructure

3-tier validation методология для harness changes. Closing measurement gap: structural + behavioral evidence для каждого предлагаемого обновления.

## Quick start

```bash
bash .claude/benchmark/run-all.sh            # все tiers последовательно
bash .claude/benchmark/static-checks.sh      # только Tier 0 (fast, pre-commit blocker)
bash .claude/benchmark/tier1/run-tier1.sh    # Tier 1 task suite на fixture
bash .claude/benchmark/tier2/run-tier2.sh    # Tier 2 skill trigger evals
```

## Структура

- `static-checks.sh` — Tier 0 (fast, pre-commit blocker, <10s budget)
- `tier1/` — pilot project task suite (T01-T07 + extensions)
- `tier2/` — per-component evals (skill trigger accuracy, agent prompt corpus)
- `fixtures/` — synthetic test projects, self-contained в repo
- `reports/` — saved benchmark output, optional history
- `run-all.sh` — orchestrate all tiers

Full methodology — `.claude/docs/benchmark.md`.

## Когда какой tier

| Trigger | Tier 0 | Tier 1 | Tier 2 |
|---------|:------:|:------:|:------:|
| Pre-commit (любой harness change) | ✓ | — | — |
| Behavior-changing principle update | ✓ | ✓ | — |
| New/changed skill | ✓ | ✓ | ✓ |
| New/changed agent | ✓ | ✓ | ✓ |
| New/changed hook | ✓ | ✓ (smoke) | — |
| Retire/trim component | ✓ | ✓ | — |

## Current automation state

- Tier 0: **fully automated** (`static-checks.sh`, 14 checks, 44ms runtime)
- Tier 1: **operational** (devlog #24) — `headless-runner.sh` runs real `claude --print` on fixture clone, captures JSON metrics, optional pytest judge. Supports `--inject-from <dir>` for cross-harness comparison.
- Tier 2: **scaffolding ready** — eval sets defined для skills, runner validates structure; actual trigger evaluation manual

## Reports

Каждый behavior-changing change — attach benchmark report в `reports/<tier>-<name>-<date>.md`. Template — `reports/README.md`.

## Roadmap

- Tier 1 polyglot tasks (T04-T07): refactor, docs, ops, research — added as need arises
- Tier 2 full automation: per-query skill discovery probe + accuracy aggregation
- Cross-harness comparison expansion (T03+ multi-fixture): первый baseline в `reports/CROSS-HARNESS-COMPARISON.md` (T01/T02 × 4 harness variants, 2026-05-11)
