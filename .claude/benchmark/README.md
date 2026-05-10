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
- Tier 1: **scaffolding ready** — task definitions valid, fixture present; actual Claude invocation остаётся manual (`claude --bare --print --add-dir <fixture>` для CI)
- Tier 2: **scaffolding ready** — eval sets defined для skills, runner validates structure; actual trigger evaluation manual

## Reports

Каждый behavior-changing change — attach benchmark report в `reports/<tier>-<name>-<date>.md`. Template — `reports/README.md`.

## Roadmap

- Tier 1 full automation: `claude --bare --print` orchestrator с output parsing для tokens/turns/files metrics
- Tier 2 full automation: per-query skill discovery probe + accuracy aggregation
- Cross-harness comparison fixtures: clone select community harness'ов (everything-claude-code, claude-code-harness, Superpowers) для quantitative comparison на same task suite
