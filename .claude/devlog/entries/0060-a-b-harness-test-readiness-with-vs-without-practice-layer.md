---
id: 60
date: 2026-05-29
title: "A/B harness test readiness (with vs without practice layer)"
tags: [benchmark, harness, multi-agent]
status: complete
---

# A/B harness test readiness (with vs without practice layer)

## Контекст
Оператор: «проведи все необходимые замеры и будь готов к полноценному тесту двух вариантов (с
harness и без него)». Цель — измерить ценность глобального практического слоя `~/.claude` на
качественном оракуле v2. Дизайн зафиксирован (AskUserQuestion): агент-под-тестом = `claude --print`
**строит NL→SQL impl**; переключатель = **глобальный слой `~/.claude` on/off**; судья = v2.

## Необходимые замеры (проведены)
- **Дисперсия оракула**: 3 независимых прохода реального ollama-агента (temp 0.1) → **5/5/5**, каждая
  задача детерминированно 3/3 или 0/3. Оракул v2 — **стабильный инструмент**; Ollama-недетерминизм,
  занулявший #52, здесь отсутствует → n=1 на стороне scoring достаточно. Остаточный шум A/B — только
  стохастика claude-билда (→ `--builds N>1`).
- **Live reference**: ReferenceSolver 12/12 gate_pass, 12/12 stable на реальном Oracle.
- **Real-agent baseline**: ollama (тонкий hint) 5/12 — дискриминирует (см. #59).

## Механизм toggle (подтверждён механически)
`CLAUDE_CONFIG_DIR` релоцирует весь конфиг, но теряет OAuth → `noharness`-arm использует bare-dir с
**только** `.credentials.json` (+ пустой settings.json). Проверка через `--include-hook-events` на
тривиальном промпте: **harness → SessionStart-хуки срабатывают (×4); noharness → 0 hook-событий.**
Значит глобальные CLAUDE.md/hooks/skills действительно отсутствуют в noharness.

## Построено (`text2sql-v2/ab/`)
- `build_prompt.md` — единый для обоих arm: построить NL→SQL для `client_product` с контрактом
  entrypoint `solve.py "<вопрос>"` → SQL (без БД/сети), + тесты.
- `ab_runner.py` — оркестратор: arm harness/noharness (toggle через `CLAUDE_CONFIG_DIR`+creds),
  `claude --print` строит impl, `BuiltImplSolver` оборачивает `solve.py`, v2 судит против bench-Oracle,
  сравнение arm + delta. `--stub` валидирует пайплайн без claude; `--builds N` — повторы билда.

## Проверка готовности
`ab_runner.py --stub --arms both` против живого Oracle: оба arm 12/12, сравнение+delta+отчёт. ruff
clean. Полный прогон (с реальными claude-билдами) — по команде оператора (дорогой: 2×N build-сессий).

## Затронутые файлы
- `text2sql-v2/ab/{build_prompt.md,ab_runner.py,README.md}` (new)
- `reports/2026-05-29-text2sql-v2-ollama-baseline/variance.json` (new)

## Related / next
- #57/#58/#59 — бенчмарк v2. Этот — A/B-обвязка поверх него.
- Готово к запуску: `python3 ab/ab_runner.py --arms both --builds 3` (env Oracle). Даст дельту
  качества harness vs noharness. Caveat: NL→SQL build-task — single-shot билд, continuity-столб
  (#54) не задействован; для его замера нужен мульти-сессийный сценарий (отдельно).
