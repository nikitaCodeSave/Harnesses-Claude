---
id: 58
date: 2026-05-29
title: "text2sql benchmark v2 full build and integration"
tags: [benchmark, feature, multi-agent]
status: complete
---

# text2sql benchmark v2 full build and integration

## Контекст
После MVP (#57) оператор: «раздай задачи по проведению — бенчмарк v2». Декомпозировал остаток
(задачи + оси 5-9 + live-runner) на 3 параллельных агента в изолированных worktree, по
**непересекающимся файлам** (чистый merge), все от текущего HEAD.

## Раздача (3 агента, worktree, фоном)
- **A — suite**: `fixture.py`/`tasks.py`/`scorer.py`/`test_scorer.py`. Добавил T2/T4/T5/T7/T9 +
  guardrail G1/G2 (новый `golden_kind="refusal"` + refusal-ось). Фикстура расширена (per-client
  `CREATE_DT`, Q3/Q4 2024, `FX_VOLUME_RUB`) — старые golden не сдвинулись (`MAX(MONTH_DT)` остался
  2026-04-22). test_scorer **39/39**.
- **B — judge**: новые `judge.py`/`test_judge.py`. Оси 7-9 (faithfulness/consistency/depth) через
  ollama (env-config), degrade `judge_status="skipped"` без сети. **19/19** на заглушках.
- **C — runner**: новые `runner.py`/`run-bench.sh`/`test_runner.py`. `Solver`-интерфейс
  (`ReferenceSolver` + `AgentSolver`-скелет), оси 5-6 (reliability/stability N≥3), live-Oracle через
  `oracledb` или dry-run degrade (креды только из env). **28/28**.

## Merge + интеграция (main thread)
3 ветки смержены (ort, без конфликтов — файлы непересекались). Интеграция поймала ожидаемый coupling
(C строился против MVP-задач):
1. `ReferenceSolver` знал только T1/T3/T6/T8/T10 → `KeyError` на полной 12-задачной сюите. Расширил
   на все 12 + refusal-ветку для G1/G2 (пробросил `answer` в submission).
2. `_axis5` требовал `sql_present` → refusal-задачи (пустой SQL) ложно gate-fail. Сделал ось 5
   refusal-aware (sql_present/sql_executed/silent-empty = N/A для refusal).
3. T7 reference-SQL не содержал `fx_volume_rub` → ax2-anchor fail. Дополнил вторым statement'ом.
4. Два assert'а для Optional-narrowing (pyright).

## Проверка
Полная интеграция на main: **test_scorer 39/39, test_judge 19/19, test_runner 28/28, ruff clean**.
`runner.run_benchmark()` dry-run по всем 12 задачам → **12/12 gate_pass, 12/12 stable**.

## Известное ограничение (live mode)
`OracleExecutor._shape` мапит строки БД в golden-форму эвристикой. Для wide `number_map` с
**производными** ключами не из SQL-вывода (T5 delta/delta_pct, T6 PNL_TOTAL) live-исполнению нужен
per-task column-aliasing/shaper-hint. Dry-run (result=golden) не затронут. Это главный пункт перед
полным live-прогоном. Задокументировано в README.

## Затронутые файлы
- merge: `.claude/benchmark/text2sql-v2/{fixture,tasks,scorer,test_scorer,judge,test_judge,runner,
  test_runner}.py`, `run-bench.sh`, `seed.sql` (78 строк)
- интеграция (main): `runner.py` (ReferenceSolver 12 задач + refusal + axis5-fix + asserts),
  `README.md` (актуализирован)

## Related / next
- #57 MVP (5 задач, оси 1-4). Теперь 12 задач + 9 осей.
- Next: закрыть live-mode `_shape` (per-task aliasing) → реальный прогон против docker-Oracle;
  подключить реального агента-под-тестом через `AgentSolver` (`claude --print` / пайплайн проекта).
