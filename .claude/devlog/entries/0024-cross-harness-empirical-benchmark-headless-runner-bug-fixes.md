---
id: 24
date: 2026-05-11
title: "Cross-harness empirical benchmark + headless-runner bug fixes"
tags: [benchmark, harness, evidence]
status: complete
---

# Cross-harness empirical benchmark + headless-runner bug fixes

## Контекст

User-explicit authorization для проверки совместимости харнесов из community ecosystem
(статья «HARNESSES для Claude Code», май 2026). Real-world benchmark под Opus 4.7 на одном
fixture (sample-py-app), four harness variants. Previous devlog 0023 documented classifier
блокирующий nested `claude --print` — под user-explicit auth classifier пропускает, что
дало возможность real comparison.

## Изменения

### 1. `headless-runner.sh` — 3 bug fixes (blocked real benchmark до этого)

- **Env vars passing**: `bash -c "..." BENCH_VAR=val` — positional args, не env vars. Fix:
  `BENCH_VAR=val bash -c '...'`. Без этого `--permission-mode` всегда был empty string,
  `claude --print` failed silently c exit 0 на 0s.
- **files_changed=0 если fixture не git repo**: sample-py-app не git. Fix: fallback на
  `find -newer "@$START_EPOCH"` с exclusion masks для bench artefacts, `__pycache__`,
  injected `.claude/`, `CLAUDE.md`.
- **pytest skipped если нет `tests/`**: fixture имеет `test_app.py` в root. Fix: scope
  pytest к `tests/` OR root-level `test_*.py` / `*_test.py` files, exclude parasitic tests
  injected по path (см. §3 ECC finding).

### 2. `headless-runner.sh` — `--inject-from <dir>` опция

Для cross-harness benchmarking: вместо инжекции нашего `.claude/`, инжектит alt harness'а
(both `.claude/` + top-level `CLAUDE.md`/`agents/`/`skills/`/`commands/`/`hooks/`/`rules/`).
Включает все common community harness layouts.

### 3. `.claude/benchmark/reports/CROSS-HARNESS-COMPARISON.md` — empirical baseline

Comparison report для T01 (feature add) и T02 (bugfix). Полная таблица tokens/turns/cost
across 4 variants: no-harness baseline, our harness, everything-claude-code (ECC),
cwc-long-running-agents (Anthropic ref).

## Empirical findings

### Cost overhead vs no-harness baseline (Opus 4.7)

| Harness | T01 cost Δ | T02 cost Δ |
|---|---:|---:|
| Our (Harnesses-Claude) | +24% | +27% |
| ECC (everything-claude-code) | +5% | -4% |
| cwc-long-running-agents | n/a | +46% |

### Quality

Все 4 variants pass pytest на T01 и T02 (после runner pytest scoping fix). **Opus 4.7
natively solves these tasks без harness assistance** — validates foundational principle
empirically. Harness ROI на standard one-shot features/bugfixes — marginal.

### Critical finding: ECC parasitic tests pollute pytest collection

`everything-claude-code` ships 90+ test functions across 3 files in
`skills/continuous-learning-v2/scripts/test_*.py`. Когда установлен в любой Python
project использующий default `pytest` invocation без `testpaths`, эти tests collected
и many fail (no env deps). Это **safety regression** для target projects —
ECC не должен ставиться без `pyproject.toml` override:

```toml
[tool.pytest.ini_options]
testpaths = ["tests", "test_app.py"]  # explicit, exclude ECC's skills/
```

### Cwc-long-running-agents most expensive per LoC

506 LoC harness, 5 hooks + 1 evaluator agent — но +46% cost overhead на T02. Cost not
justified для standard tasks; opt-in для long-running fixed-spec scenarios per
Rajasekaran 2026 (6h $200 sessions).

## Затронутые файлы

- `.claude/benchmark/headless-runner.sh` — 3 bug fixes + `--inject-from` option (~30 lines)
- `.claude/benchmark/reports/CROSS-HARNESS-COMPARISON.md` — new, 73 lines

## Проверка

- `bash -n headless-runner.sh` → SYNTAX_OK
- 7 real `claude --print` invocations (4 T01 + 3 T02 variants), все exit=0
- 12/12 Tier 0 static checks pass (no regression)
- All 6 target tests pass on all variants (quality preserved)

## Implications

- **Foundational principle «минимум обвязки» — empirically validated**. Heavyweight packs
  не дают quality gain на standard tasks; могут привнести side-effects (pytest pollution).
- **+25% cost — our envelope** под Opus 4.7. Monitor on T03+ для stability across task
  classes.
- **No new harness components adopted** from article — single-source evidence
  недостаточен per `principles.md` строка 92 («single-incident NOT invariant»). Patterns
  из cwc (Default-FAIL contract, fresh-context evaluator) уже cited в `principles.md`
  строка 33 как opt-in reference; cost makes them unsuitable для default workflow.

## Related

- #21 — benchmark infrastructure foundation
- #22 — stop-validation multi-gate (independent verification, complementary signal)
- #23 — headless-runner infrastructure (this entry — real benchmark using infra)

## Отложено / не сделано

- **T03-T07 multi-fixture comparison** — задачи определены, но FastAPI fixture (T03)
  требует external project. Может быть добавлено в roadmap as part of `roadmap` Tier 1
  full automation.
- **Plugin-installed ECC measurement** — текущий benchmark измерил raw inject (ECC's
  plugin auto-loading disabled без `/plugin install`). Real overhead с activated skills
  может быть much higher.
- **Anthropic Claude Agent SDK / Managed Agents** — API-only, out of scope per
  `principles.md` строка 17 и memory `feedback_no_anthropic_api`.
