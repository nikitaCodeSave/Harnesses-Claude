# Harness Benchmark Infrastructure

4-layer measurement framework: проверка что harness changes делают то, ради чего harness существует — не overhead, а реальный lift качества на задачах с высокой ambient exploration cost.

Full methodology — `.claude/docs/benchmark.md`. Источники evidence: Anthropic SWE-bench-Verified, Boris Cherny (howborisusesclaudecode.com), Addy Osmani (Agent Harness Engineering), Skill Creator eval (2026-03).

## Quick start

```bash
bash .claude/benchmark/run-all.sh            # все слои последовательно (placeholder)
bash .claude/benchmark/static-checks.sh      # Layer A только — fast, pre-commit blocker
bash .claude/benchmark/headless-runner.sh \  # Layer B+C один task на одном fixture
    --task tier1/tasks/T01-add-health-endpoint.yaml \
    --fixture fixtures/sample-py-app
```

Cross-harness comparison: `--inject-from <alt-harness-dir>` подменяет наш `.claude/` на чужой.

## Layers

| Layer | Что | Cost | Файл |
|---|---|---|---|
| **A** — Structural | invariants harness'а (14 checks) | <10s | `static-checks.sh` |
| **B** — Behavioral matrix | task pass/fail на fixture × task type | minutes-hours | `headless-runner.sh` + `tier1/` |
| **C** — Trajectory quality | skills/subagents/invariant pings/workflow markers | parsed from B | extended `headless-runner.sh` (P2) |
| **D** — Statistical protocol | n=3 minimum, bracket [min,med,max], sign-inversion gate | n×B multiplier | per-run reports + aggregate `reports/<change>/summary.md` |

## Структура

```
.claude/benchmark/
├── README.md              — этот файл
├── static-checks.sh       — Layer A
├── headless-runner.sh     — Layer B+C runner
├── run-all.sh             — orchestrate all layers
├── bootstrap-fixtures.sh  — set up external fixtures
├── tier1/                 — task definitions (yaml), tier1-naming preserved для backward-compat
├── tier2/                 — per-skill eval sets (Layer C для skills)
├── fixtures/              — synthetic in-repo + external clones
└── reports/               — per-run JSON + aggregate summaries
```

## Когда какой layer

| Trigger | A | B | C | D |
|---------|:------:|:------:|:------:|:------:|
| Pre-commit любой change | ✓ | — | — | — |
| Behavior-changing principle | ✓ | ✓ subset | ✓ | ✓ |
| New/changed skill | ✓ | ✓ skill-relevant | ✓ | ✓ |
| New/changed agent | ✓ | ✓ agent-relevant | ✓ | ✓ |
| New/changed hook | ✓ | ✓ smoke | partial | — |
| Retire/trim component | ✓ | ✓ subset | ✓ | ✓ |
| ADR с numerical claim | ✓ | ✓ | ✓ | **required** |

«Subset» — sparse cell selection per scope, не full matrix. Right-sizing — за main thread'ом.

## Current automation state

- **Layer A**: fully automated (14 checks, 44ms).
- **Layer B**: operational. 5 tasks (T01-T04 + T03e) × 3 fixtures. Headless runner с pytest judge.
- **Layer C**: partial — token/turn/cost capture есть. Trajectory parsing (skills/subagents/invariant pings/workflow markers) — work-in-progress (P2, 2026-05-11).
- **Layer D**: applied ad-hoc на T03 (4×4 confirmed −24% median harness vs baseline). Не protocol-default yet.
- **Stop-hook two-gate**: `.claude/hooks/stop-validation.sh`.

## Reports

Per-run: `reports/<task>-<fixture>-<harness>-runN.json` — JSON со всеми метриками.
Aggregate: `reports/<change-name>/summary.md` — markdown с bracket table + CV + sign-inversion verdict.
Template — `reports/README.md`.

## Roadmap

- **P1+P2 (active 2026-05-11)**: trajectory parsing + docs aligned + T01-T04 re-prog.
- **P3**: первая legend fixture `legacy-no-tests` (modernization, expected high harness ROI).
- **P4**: trip-wire / Neg-invariant tasks (honeypot prompts на invariants).
- **P5**: stat protocol enforced default.
- **P6**: F-ambiguous tasks (criteria-judge не binary pytest).

См. полный rationale + axis (harness ROI ∝ exploration cost) в `.claude/docs/benchmark.md`.
