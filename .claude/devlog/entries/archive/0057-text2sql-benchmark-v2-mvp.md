---
id: 57
date: 2026-05-29
title: "text2sql benchmark v2 MVP"
tags: [benchmark, feature]
status: complete
---

# text2sql benchmark v2 MVP

## Контекст
Оператор: текущий text2sql-бенчмарк примитивен (решается мгновенно), хотя просит e2e-тест против
живой связки ollama+Oracle(docker); метрики надо расширить/переписать. Попросил «несколько агентов»
посмотреть production-проект `AI_analyst_for_work/AI_analyst_migration` и подчерпнуть оттуда задач.

## Разведка (4 агента, read-only, фоном)
4 линзы (домен / реальные задачи / e2e-пайплайн / качество-метрики). Синтез → `.claude/benchmark/
text2sql-v2-design.md`. Ключевые выводы:
- Сложность домена — не в числе таблиц (1 денормализованная snapshot-таблица `client_product`), а в
  плотном слое инвариантов: two-step AVG для balance-полей, иерархия итог/компонент, двойная
  семантика `MONTH_DT` (закрытый EOM vs текущая дата выгрузки), событийные даты vs снимки, флаги
  активности vs объёмы, Oracle-диалект. `core/sql/validator.py` (2541 строк авто-фиксов) = прямое
  доказательство, на чём ошибается наивный NL→SQL.
- Текущий раннер судит pipeline-status, не корректность (аналог `compare_runs.py` сам себя
  дисквалифицирует в README: `BOTH_OK` ≠ «верно»). Опаснейшая ошибка домена — уверенный неверный
  ответ при `status=success` (silent-empty, неверный год/период, SUM вместо AVG, галлюцинация).

## Решения (через AskUserQuestion)
- Форма задачи: **узкий NL→SQL + golden** (агент строит gen+validate+execute против живого Oracle;
  судим корректность результата на фикстуре), не полный pipeline и не расширение старой задачи.
- Старт: **MVP = фикстура + golden + авто-оси 1-4 на 5 задачах** (T1/T3/T6/T8/T10), цель — доказать,
  что метрики ловят traps.

## Сделано (`.claude/benchmark/text2sql-v2/`)
- `fixture.py` — single source of truth: `ROWS` (42 строки, 6 клиентов) намеренно провоцируют каждый
  trap; те же данные эмитят `seed.sql` И вычисляют golden → golden не дрейфует от загруженного.
- `tasks.py` — 5 задач с golden (вычислен из `ROWS`) + regex-anchors (ось 2) + правило агрегации (ось 4).
- `scorer.py` — оси 1-4 (детерминированный gate): numeric vs golden ±tol; SQL-anchors; empty-honesty
  (детект F1 silent-empty); aggregation-semantics (balance → two-step, не SUM/прямой AVG).
- `test_scorer.py` — **18/18**: для каждой задачи GOOD-решение gate-PASS, NAIVE (trap) gate-FAIL,
  причём NAIVE пойман именно на той оси, что задумана (T1→ax1, T3→ax4 ×2, T6→ax2, T8→ax2, T10→ax3).
- `README.md` + `seed.sql` (generated).

## Проверка
Golden совпали с ручным расчётом (T1=441; T3 two-step {Intl:600,Large:3000,Middle:60,SME:20}; T6
OTHER=150/PNL=1323; T8={1002,1006}; T10=600). `test_scorer.py` 18/18; ruff clean. Метрики доказанно
дискриминируют good vs trap — в отличие от примитивного pass/fail раннера.

## Затронутые файлы
- `.claude/benchmark/text2sql-v2/{fixture,tasks,scorer,test_scorer}.py`, `README.md`, `seed.sql`
- `.claude/benchmark/text2sql-v2-design.md` (синтез разведки, отдельный коммит ранее)

## Related / next
- Не доделано (next): live-Oracle runner (загрузить seed в docker-Oracle, прогнать агента-под-тестом,
  скормить scorer); остальные задачи (T2/T4/T5/T7/T9 + guardrail G1/G2) и оси 5-9 (reliability/
  stability + LLM-judge faithfulness/consistency/depth).
- Связано с #52 (single-shot зануляет ценность practice-слоя) — этот бенчмарк меряет КАЧЕСТВО, шаг к
  правильному мульти-сессийному замеру.
