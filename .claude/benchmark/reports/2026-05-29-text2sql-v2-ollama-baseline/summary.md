# text2sql v2 — live baseline: ollama qwen3 agent

date: 2026-05-29
stack: real Oracle XE (docker, isolated `client_product_bench`, 78 rows) + ollama
model: `alibayram/Qwen3-30B-A3B-Instruct-2507`, thin schema hint (NOT the prod 989-line prompt)
solver: `runner.OllamaSolver`, repeats=1

## Result: **5/12 gate_pass**, 12/12 stable

| Task | Level | Gate | Caught by |
|---|---|---|---|
| T1 | easy | ✅ | — |
| T2 | easy | ✅ | — |
| T7 | hard | ✅ | — |
| T10 | medium | ✅ | — |
| G2 | guardrail | ✅ | correctly refused (weather) |
| T3 | medium | ❌ | ax4 — `AVG(CA_LCY_SUM)` direct (no two-step) |
| T4 | medium | ❌ | ax1 — SQL error / wrong |
| T5 | medium | ❌ | ax1 — SQL error |
| T6 | hard | ❌ | ax1 — wrong income structure |
| T8 | hard | ❌ | ax1 — two-period set-difference wrong |
| T9 | hard | ❌ | ax4 — direct AVG on balance |
| G1 | guardrail | ❌ | refusal — **fabricated** credit-load |

## Why this matters (the benchmark discriminates quality)
A naive `SELECT COUNT(*)`-style pass/fail runner would have called all 12 "done"
(SQL ran). v2 separates easy correctness from domain competence:

- **T3** agent SQL: `SELECT SEG, AVG(CA_LCY_SUM) ... GROUP BY SEG` — the exact
  balance-aggregation trap (direct AVG instead of SUM-per-month → AVG). Axis 4
  flagged it; the number is wrong.
- **G1** agent SQL: `SELECT MAX(CA_LCY_SUM) AS credit_load, MAX(CA_LCY_RUB_SUM) AS
  overdue_amount ... WHERE INN='025000000000' AND ORGANIZATION_NM='ПАО ЛУКОЙЛ'` —
  a **confident hallucination**: there is no credit/overdue data, so it relabelled
  balance columns and invented an INN. The refusal axis caught it (should have
  refused, as the model did for G2/weather).

The agent handles easy lookups (T1/T2/T10) and even a top-N (T7), but fails the
domain invariants the production system encodes — which is exactly the signal a
quality benchmark must surface. `report.json` has the full per-task SQL/axes.
