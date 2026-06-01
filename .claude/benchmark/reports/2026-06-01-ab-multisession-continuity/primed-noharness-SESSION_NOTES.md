# Multi-session build — handoff notes

## What was built (sessions 1 & 2)

```
solve.py          — entry point: python3 solve.py "<question>" → stdout SQL / NO_SQL
agent.py          — LLM wrapper + SYSTEM_PROMPT + extract_sql logic
test_solve.py     — 71 tests (all passing), no external dependencies beyond httpx
```

`solve.py` is a thin shim; all logic lives in `agent.py`.

## Interface contract (do not break)

```bash
python3 solve.py "<question>"   # prints SQL or NO_SQL to stdout, diagnostics to stderr
```

## Environment variables expected (set externally, not hardcoded)

| Variable | Example value |
|---|---|
| `AI_ANALYST_API_URL` | `http://localhost:11434/v1` |
| `AI_ANALYST_API_KEY` | `ollama` |
| `AI_ANALYST_SQL_MODEL` | `qwen2.5-coder:7b` |

HTTP done via `httpx` (falls back to `urllib`). No `openai` SDK. No `anthropic` SDK.

## Key domain decisions / rules encoded in the prompt

### MONTH_DT filtering
- Specific month (e.g. March 2024): `WHERE TRUNC(MONTH_DT, 'MM') = DATE '2024-03-01'`
- Quarter (Q1 2024): `WHERE MONTH_DT >= DATE '2024-01-01' AND MONTH_DT < DATE '2024-04-01'`
- All quarters follow the same half-open interval pattern.
- Q3 2024: `>= DATE '2024-07-01' AND < DATE '2024-10-01'`
- Q4 2024: `>= DATE '2024-10-01' AND < DATE '2025-01-01'`

### Aggregation — THE critical rule
| Metric type | Columns | Aggregation |
|---|---|---|
| **Balance** (snapshot) | `CA_LCY_SUM`, `CA_LCY_RUB_SUM`, `DEP_SUM` | **AVG** over months |
| **Flow** | `PNL_SUM`, `PL_CA`, `PL_DEP`, `PL_VK`, `PL_VK_OUT`, `VED_SUM`, `FX_VOLUME_RUB`, `FX_CNT`, `FX_MARGIN_RUB`, `VED_VOL` | **SUM** |

### Client count
Use `COUNT(DISTINCT INN)`, never `COUNT(*)`.

### Oracle syntax
- Top-N: `ORDER BY ... FETCH FIRST N ROWS ONLY` — never `LIMIT`
- No trailing `;` in returned SQL

### NO_SQL
Return exactly `NO_SQL` (extract_sql normalises case) when the question cannot be answered from `client_product`.

### New clients (opened during period) — session 2
Filter and group by `CREATE_DT`, NOT `MONTH_DT`. Use `COUNT(DISTINCT INN)`.
```sql
SELECT TRUNC(CREATE_DT, 'MM') AS open_month, COUNT(DISTINCT INN) AS new_clients
FROM client_product
WHERE CREATE_DT >= DATE '2024-01-01' AND CREATE_DT < DATE '2025-01-01'
GROUP BY TRUNC(CREATE_DT, 'MM')
ORDER BY open_month
```

### Period comparison (Q vs Q) — session 2
Use CTE + CASE WHEN to get both periods in one query.
Difference = period2 - period1; Percentage = `ROUND((p2 - p1) / NULLIF(p1, 0) * 100, 2)`.
```sql
WITH q AS (
    SELECT
        SUM(CASE WHEN MONTH_DT >= DATE '2024-07-01' AND MONTH_DT < DATE '2024-10-01' THEN PNL_SUM ELSE 0 END) AS q3,
        SUM(CASE WHEN MONTH_DT >= DATE '2024-10-01' AND MONTH_DT < DATE '2025-01-01' THEN PNL_SUM ELSE 0 END) AS q4
    FROM client_product
    WHERE MONTH_DT >= DATE '2024-07-01' AND MONTH_DT < DATE '2025-01-01'
)
SELECT q3, q4, q4 - q3 AS diff, ROUND((q4 - q3) / NULLIF(q3, 0) * 100, 2) AS pct_change
FROM q
```

### Revenue component breakdown — session 2
- ВК свой банк = `PL_VK`, ВК чужой банк = `PL_VK_OUT`
- Маржа FX = `FX_MARGIN_RUB`
- ВЭД = `VED_SUM`
- Прочее = `PNL_SUM - PL_CA - PL_DEP - PL_VK - PL_VK_OUT - FX_MARGIN_RUB - VED_SUM`
All columns are flow metrics → SUM.

### Latest available month — session 2
Dynamic subquery, no hardcoded date:
```sql
WHERE TRUNC(MONTH_DT, 'MM') = (SELECT MAX(TRUNC(MONTH_DT, 'MM')) FROM client_product)
```

## Reference correct SQL (all verified by tests)

**PNL_SUM за март 2024:**
```sql
SELECT SUM(PNL_SUM) AS total_pnl
FROM client_product
WHERE TRUNC(MONTH_DT, 'MM') = DATE '2024-03-01'
```

**Сколько клиентов:**
```sql
SELECT COUNT(DISTINCT INN) AS total_clients
FROM client_product
```

**Средние CA_LCY_SUM по сегментам за Q1 2024:**
```sql
SELECT SEG, AVG(CA_LCY_SUM) AS avg_ca_balance
FROM client_product
WHERE MONTH_DT >= DATE '2024-01-01' AND MONTH_DT < DATE '2024-04-01'
GROUP BY SEG
ORDER BY SEG
```

**Новые клиенты по месяцам 2024:**
```sql
SELECT TRUNC(CREATE_DT, 'MM') AS open_month,
       COUNT(DISTINCT INN) AS new_clients
FROM client_product
WHERE CREATE_DT >= DATE '2024-01-01' AND CREATE_DT < DATE '2025-01-01'
GROUP BY TRUNC(CREATE_DT, 'MM')
ORDER BY open_month
```

**Q3 vs Q4 сравнение:**
```sql
WITH q AS (
    SELECT
        SUM(CASE WHEN MONTH_DT >= DATE '2024-07-01' AND MONTH_DT < DATE '2024-10-01' THEN PNL_SUM ELSE 0 END) AS q3,
        SUM(CASE WHEN MONTH_DT >= DATE '2024-10-01' AND MONTH_DT < DATE '2025-01-01' THEN PNL_SUM ELSE 0 END) AS q4
    FROM client_product
    WHERE MONTH_DT >= DATE '2024-07-01' AND MONTH_DT < DATE '2025-01-01'
)
SELECT q3, q4, q4 - q3 AS diff, ROUND((q4 - q3) / NULLIF(q3, 0) * 100, 2) AS pct_change
FROM q
```

**Структура дохода Q1 2024:**
```sql
SELECT
    SUM(PL_CA) AS pl_ca,
    SUM(PL_DEP) AS pl_dep,
    SUM(PL_VK) AS pl_vk,
    SUM(PL_VK_OUT) AS pl_vk_out,
    SUM(FX_MARGIN_RUB) AS fx_margin,
    SUM(VED_SUM) AS ved,
    SUM(PNL_SUM) - SUM(PL_CA) - SUM(PL_DEP) - SUM(PL_VK) - SUM(PL_VK_OUT) - SUM(FX_MARGIN_RUB) - SUM(VED_SUM) AS other,
    SUM(PNL_SUM) AS total_pnl
FROM client_product
WHERE MONTH_DT >= DATE '2024-01-01' AND MONTH_DT < DATE '2024-04-01'
```

**Последний доступный месяц:**
```sql
SELECT SUM(PNL_SUM) AS total_pnl
FROM client_product
WHERE TRUNC(MONTH_DT, 'MM') = (
    SELECT MAX(TRUNC(MONTH_DT, 'MM')) FROM client_product
)
```

## What was added in session 3 (119 tests total, all passing)

### New query patterns (rules 9–12 in SYSTEM_PROMPT)

**Rule 9 — Client churn via MINUS:**
```sql
SELECT DISTINCT INN FROM client_product
WHERE MONTH_DT >= DATE '2025-07-01' AND MONTH_DT < DATE '2025-10-01' AND VED_VOL > 0
MINUS
SELECT DISTINCT INN FROM client_product
WHERE MONTH_DT >= DATE '2025-10-01' AND MONTH_DT < DATE '2026-01-01' AND VED_VOL > 0
```

**Rule 10 — Top-N with breakdown (CTE + JOIN):**
```sql
WITH top3 AS (
    SELECT INN FROM client_product
    WHERE MONTH_DT >= DATE '2024-01-01' AND MONTH_DT < DATE '2024-04-01'
    GROUP BY INN ORDER BY SUM(PNL_SUM) DESC FETCH FIRST 3 ROWS ONLY
)
SELECT cp.INN, TRUNC(cp.MONTH_DT, 'MM') AS month, SUM(cp.FX_VOLUME_RUB) AS fx_volume
FROM client_product cp JOIN top3 ON cp.INN = top3.INN
WHERE cp.MONTH_DT >= DATE '2024-01-01' AND cp.MONTH_DT < DATE '2024-04-01'
GROUP BY cp.INN, TRUNC(cp.MONTH_DT, 'MM') ORDER BY cp.INN, month
```

**Rule 11 — "средний" overrides default for flow metrics → AVG:**
```sql
SELECT SEG, AVG(PNL_SUM) AS avg_pnl, AVG(CA_LCY_SUM) AS avg_ca,
       SUM(FX_VOLUME_RUB) AS total_fx_volume
FROM client_product
WHERE MONTH_DT >= DATE '2024-01-01' AND MONTH_DT < DATE '2024-04-01'
GROUP BY SEG ORDER BY SEG
```

**Rule 12 — NO_SQL for out-of-scope:**
Explicitly lists: кредитная нагрузка, просрочка, скоринг, риски, погода, цены акций,
конкуренты, география. Two NO_SQL examples added for credit/delinquency questions.

### New test classes (48 tests added)
- `TestTop3PnlWithFxByMonth` (10 tests)
- `TestVedStoppedClientsStructure` (8 tests)
- `TestSegmentComparisonStructure` (8 tests)
- `TestNoSqlRefusalSession3` (6 tests)
- `TestSystemPromptSession3Rules` (8 tests)
- `TestGenerateSqlSession3Mocked` (8 tests)
