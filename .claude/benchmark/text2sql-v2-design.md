# text2sql benchmark v2 — design (mined from AI_analyst_migration)

owner: @nikitaCodeSave
last-updated: 2026-05-29
status: proposal (pending build-scope approval)

Синтез разведки 4 агентов по `/home/nikita/PROJECTS/AI_analyst_for_work/AI_analyst_migration`
(production банковский AI-аналитик: NL → подвопросы → Oracle-SQL → execute → merge → отчёт;
стек ollama+Oracle через docker). Цель: заменить примитивный `text2sql` бенчмарк (решается
мгновенно, судит pass/fail) на трудный, e2e-честный, с метриками качества.

## Диагноз: почему текущий бенчмарк бесполезен здесь

1. **Судит pipeline-status, не корректность.** Раннер аналога (`dev/validation/compare_runs.py`)
   **сам себя дисквалифицирует** в README: `BOTH_OK` = «оба прогона дали одинаковый SQL», НЕ
   «оба ответили верно». Наш battle-runner аналогично смотрит «SQL выполнился» + структура.
2. **Сложность домена — не в схеме, а в инвариантах.** Одна денормализованная snapshot-таблица
   `client_product` (35 колонок), но плотный слой правил, не выводимых из имён колонок. Прямое
   доказательство — `core/sql/validator.py` (**2541 строк** детерминированных авто-фиксов под
   реальные ошибки наивного NL→SQL).
3. **Наивная реализация с моками LLM/Oracle проходит мгновенно, но валит честный e2e.** Ценность —
   в temporal-резолюции, SQL-самопочинке через EXPLAIN PLAN на живом Oracle, multi-subquestion
   merge, числовой корректности против golden, и в детекте «пустой результат выдан за успех».
4. **Опаснейшая ошибка домена — уверенный неверный ответ при `status=success`** (silent-empty,
   неверный год/период, SUM вместо AVG, галлюцинация семантики числа).

## Доменные инварианты (что делает задачи трудными)

- **Двухшаговый AVG для balance-полей.** `CA_LCY_SUM`, `CA_LCY_RUB_SUM`, `DEP_SUM` имеют
  `aggregation_between_month=AVG`: за период >1 месяца НЕЛЬЗЯ `SUM` и нельзя прямой
  `AVG(field)` — нужно SUM по месяцу → AVG по месяцам. Flow-поля (`PNL_SUM`, `FX_*`, `VED_*`,
  `PL_*`) — `SUM`. Флаги `ACT_1M/ACT_3M` — `MAX`.
- **Иерархия итог/компонент.** `PNL_SUM = PL_CA+PL_DEP+PL_VK+PL_VK_OUT+VED_SUM+FX_MARGIN_RUB+прочее`;
  часть компонентов в таблице отсутствует → «прочий доход» = итог − Σизвестных. Нельзя складывать
  итог с компонентами (двойной счёт). ВК всегда две части (`PL_VK` + `PL_VK_OUT`).
- **Двойная семантика `MONTH_DT`.** Закрытый месяц = EOM (`2025-01-31`); текущий незакрытый =
  последняя дата выгрузки (НЕ конец месяца). «Доход за <текущий месяц>» с `= EOM` → 0 строк.
  Нужно `MAX(MONTH_DT)`. Multi-month BETWEEN стартует с первого дня (`2025-01-01`).
- **Событийные даты vs снимки.** Новые/ушедшие клиенты — по `CREATE_DT`/`CLOSE_DT`, НЕ по
  `MONTH_DT`/`MIN(MONTH_DT)`.
- **Активность = флаг, не объём.** «Перестал быть активным» = `ACT_1M` 1→0 через two-period
  LEFT JOIN + IS NULL, не `VED_VOL>0`.
- **NULL-семантика.** `GROUP_NM` NULL у клиентов без группы → `GROUP BY GROUP_NM` молча теряет их.
- **Oracle-диалект.** `AVG(SUM())` → ORA-00937 (нужен подзапрос); топ-N через `FETCH FIRST`;
  `COUNT(DISTINCT INN)`; LIKE-колонка обязана быть в SELECT+GROUP BY; `UPPER(f) LIKE UPPER('%v%')`.
- **Out-of-scope, звучащий по-банковски.** «Кредитная нагрузка Лукойла?» — данных нет в таблице →
  правильный ответ = отказ, не выдуманный SQL/число.

## Кандидаты задач (градация; источник — реальный каталог 101 вопрос + validation-dataset)

| # | Уровень | NL-вопрос | Что проверяет (trap) |
|---|---|---|---|
| T1 | easy | «Суммарный доход по всем клиентам за декабрь 2024» | happy-path, точное golden-число |
| T2 | easy | «Сколько всего клиентов в базе?» | `COUNT(DISTINCT INN)`, не `COUNT(*)` |
| T3 | medium | «Средние остатки на расчётных счетах по сегментам за 2024» | **two-step AVG** vs прямой AVG/SUM |
| T4 | medium | «Сколько новых клиентов открылось в каждом месяце 2024?» | `CREATE_DT`, не `MONTH_DT` |
| T5 | medium | «Сравни общий доход в 3 и 4 квартале 2024 (разница + %)» | два периода + дельта |
| T6 | hard | «Структура дохода по компонентам за 2024 с долями» | итог≠Σкомпонентов, «прочее», ВК=2 части |
| T7 | hard | «Топ-10 клиентов по PNL за 3 мес + динамика их FX по месяцам» | multi-subquestion + merge по INN |
| T8 | hard | «Какие клиенты перестали проводить ВЭД-платежи в Q4'25 vs Q3?» | two-period LEFT JOIN + IS NULL, DISTINCT |
| T9 | hard | «Сравни сегменты по среднему PNL, средним остаткам и сумме FX за 2024» | смешанная агрегация (AVG/two-step AVG/SUM) |
| T10 | medium | «Доход за <текущий незакрытый месяц>» | `MAX(MONTH_DT)`, не синтез EOM |
| G1 | guardrail | «Кредитная нагрузка и просрочка Лукойла на сегодня?» | отказ (данных нет), без галлюцинации |
| G2 | guardrail | «Погода завтра в Москве?» | relevance-отказ, без обращения к БД |

## Фикстура с ground-truth

База — `dev/setup-oracle.sql` (таблица `client_product`, структуру не менять). Расширить до
~12–15 клиентов × 6–12 последовательных месяцев, **намеренно** провоцируя каждый trap:
- один месяц — текущий незакрытый (`MONTH_DT` ≠ EOM) для T10/temporal;
- 2-3 клиента с `GROUP_NM=NULL` + группа из 2-3 (T6/T9 NULL-trap);
- клиент с `PNL_SUM` > Σкомпонентов («прочий доход» > 0) для T6;
- `CREATE_DT`/`CLOSE_DT` внутри окна (T4/T8);
- `ACT_1M` flip 1→0 между месяцами (активность);
- монотонные балансы, чтобы two-step AVG ≠ прямой AVG/SUM (T3 — иначе trap не различим);
- FX в EUR+CNY так, что `FX_VOLUME_RUB > EUR+CNY` («прочие валюты»).

Golden: к каждой задаче — эталонный результат, вычисленный детерминированным скриптом из
фикстуры (числа/множества INN), + якорь снапшота (`MAX(MONTH_DT)` сверяется перед прогоном, чтобы
не «протух»). Метаданные (`metadata.py`) и промпты подаются агенту как спецификация домена.

## Метрики v2 (заменяют pass/fail)

**Группа A — авто-измеримые (детерминированный oracle, блокирующий gate):**
1. **Numeric correctness vs golden** — результат vs эталон ±tolerance (0 для счётчиков, 1% для денег).
2. **SQL structural anchors** — per-task `must_contain_any` / `must_not_contain` (период, год,
   агрегат, scope) regex по сгенерированному SQL.
3. **Empty-result-honesty** — флаг `silent_empty`: `status=success` ∧ (df.empty ∨ «не найдено») при
   том, что эталон вернул бы >0 строк.
4. **Aggregation-semantics** — для balance-полей проверка предписанного агрегата (AVG/two-step), не SUM.

**Группа A — пороговые (reliability/stability):**
5. **E2E reliability / artifact integrity** — pipeline без exception; PDF/Excel созданы и size>0;
   число SQL-fix retry ≤ порога; не сработал INSUFFICIENT-DATA fallback там, где данные есть;
   латентность p50/p95.
6. **Regression-guard + flakiness** — на positive-наборе доля исчезнувших якорей (RED ALARM);
   N≥3 прогона при temp=0.1, доля идентичного SQL (стабильность).

**Группа B — LLM-judge (качественный профиль):**
7. **Source-faithfulness NL-ответа** — числа прослеживаются к данным; тип агрегации назван верно;
   нет выдуманных трендов (рубрика в research `2026-03-27-faithful-grounded...md`).
8. **SQL↔NL consistency** — период/сущности в `final_answer` совпадают с фильтрами SQL.
9. **Analytical depth / completeness** — ответил на все части (декомпозиция); контекст/сравнение vs
   голое число; отмечена неполнота при усечении данных.

Composite: оси 1-4 — gate (блокирующие); 5-6 — пороги; 7-9 — профиль качества.

## Ключевые файлы-источники (для реализации)
- `infrastructure/metadata.py` — правила агрегации полей (ось 4).
- `core/sql/prompts/v1/sql_generation.txt` (989 строк) — анти-паттерны/правила (traps).
- `core/sql/validator.py` (2541) — каталог реальных ошибок NL→SQL.
- `application/subquestion.py:226` + `application/reports.py:378` — логика silent-empty (F1).
- `dev/validation/compare_runs.py` — текущий self-disqualifying раннер.
- `docs/thinking/2026-04-24-sql-prompt-validation-dataset.md` — спека oracle + regex-якоря + golden.
- `dev/verify_date_handling.json` — numeric snapshot (golden reference).
- `dev/setup-oracle.sql`, `dev/generate_seed.py` — фикстура.
- `tests/conftest.py:63` — что нужно для честного e2e (живой Oracle+PLAN_TABLE+ollama+данные).

## Открытые вопросы для build-scope (см. обсуждение с оператором)
1. Что строит/судит бенчмарк: агент **реализует** NL→SQL-аналитик (полный pipeline) vs агент решает
   **узкую text2sql**-задачу с golden-числами?
2. Прогон против **живого** ollama+Oracle-стека (есть у оператора) — да; кто поднимает фикстуру?
3. Какой subset осей/задач для MVP (T1/T3/T6/T8/T10 + оси 1-4 как первый срез?).
