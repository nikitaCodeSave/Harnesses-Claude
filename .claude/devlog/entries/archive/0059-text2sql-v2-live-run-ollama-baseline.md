---
id: 59
date: 2026-05-29
title: "text2sql v2 live run ollama baseline"
tags: [benchmark, feature]
status: complete
---

# text2sql v2 live run ollama baseline

## Контекст
Оператор: «выполняй самостоятельно» по двум остаткам бенчмарка v2 — (1) закрыть live-mode `_shape`
для wide `number_map` с производными ключами; (2) подключить реального агента (`AgentSolver`) +
поднять docker-Oracle+ollama. Оператор подтвердил креды (`.env`): dev_user/dev_password/XEPDB1,
ollama `alibayram/Qwen3-30B-A3B-Instruct-2507`. Стек уже был поднят (Oracle XE docker healthy, ollama).

## Сделано
**Item 1 — live shaping (закрыто):**
- Per-task `shape` в `tasks.py` (scalar/ids/map_kv/map_row/map_pivot) вместо хрупкой эвристики
  wide/long. Scorer сверяет ключи `number_map` **case-insensitively** (Oracle аплкейсит алиасы).
- Reference-SQL алиасит колонки под golden-ключи; T5 считает delta/delta_pct, T6 PNL_TOTAL, T9
  пивотит по сегментам — производные ключи теперь появляются в live. T7 сведён к одному
  live-исполнимому statement'у.

**Item 2 — реальный агент + изоляция:**
- `OracleConfig` читает проектные `AI_ANALYST_ORACLE_USERNAME/PASSWORD/DSN`. Фикстура грузится в
  **изолированную** `client_product_bench` (`seed_oracle.py`, клон схемы) — рабочая `client_product`
  не тронута; executor прозрачно переписывает имя таблицы.
- `OllamaSolver` — агент-под-тестом: NL→SQL через ollama (stdlib urllib, без SDK-зависимости),
  refusal при `NO_SQL`. `_one_run` не исполняет пустой SQL (refusal сохраняет статус).

## Проверка (на реальном стеке)
- **ReferenceSolver LIVE: 12/12 gate_pass, 12/12 stable, G1/G2 refused** — shaping корректен на живом
  Oracle, включая производные ключи (T5/T6) и pivot (T9).
- **Реальный ollama-агент (qwen3, тонкий schema-hint): 5/12.** Проходит лёгкие (T1/T2/T7/T10) + отказ
  на погоду (G2); валит доменные traps: T3/T9 — `AVG(CA_LCY_SUM)` напрямую (ось 4), T4/T5 — SQL error,
  T6/T8 — неверное число (ось 1); **G1 — фабрикация**: выдал балансовые поля как «кредитная
  нагрузка/просрочка» + галлюцинированный ИНН (refusal-ось поймала). Это и есть дискриминация
  качества, которой нет у pass/fail-раннера. Отчёт:
  `.claude/benchmark/reports/2026-05-29-text2sql-v2-ollama-baseline/`.
- Offline: test_scorer 39/39, test_judge 19/19, test_runner 42/42 (+14 shaping/rewrite/extract), ruff clean.

## Затронутые файлы
- `text2sql-v2/{tasks,scorer,runner,test_runner}.py`, `seed_oracle.py` (new), `README.md`
- `reports/2026-05-29-text2sql-v2-ollama-baseline/{report.json,summary.md}` (new)

## Примечания
- `client_product_bench` оставлен в dev-Oracle (изолирован, безвреден) — позволяет повторные прогоны.
- Известное ограничение из #58 (live `_shape`) — **закрыто**.

## Related / next
- #57 MVP, #58 интеграция. Теперь бенчмарк v2 полностью рабочий e2e на живом Oracle+ollama.
- Next: прогнать агента с полным доменным промптом проекта (vs тонкий hint) — измерить дельту;
  оси 7-9 (judge) в живом прогоне; мульти-сессийный practice-замер.
