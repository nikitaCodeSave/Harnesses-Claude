# text2sql benchmark v2 — MVP

Quality-graded, e2e-honest text2sql benchmark mined from the production
`AI_analyst_migration` project. Replaces the primitive v1 task (instant,
pass/fail) with domain traps + ground-truth + correctness axes. Full rationale
and the 12-task / 9-axis roadmap: [`../text2sql-v2-design.md`](../text2sql-v2-design.md).

**Task shape (decided):** the agent builds a narrow NL→SQL layer
(gen + validate + execute against a live Oracle); we judge **result correctness
vs ground-truth** on a seeded fixture — not "SQL ran".

## Files
- `fixture.py` — single source of truth. `ROWS` defines the seed; emits `seed.sql`
  AND feeds golden computations, so golden never drifts from loaded data.
  Run `python3 fixture.py` to regenerate `seed.sql` (42 rows).
- `tasks.py` — MVP suite **T1/T3/T6/T8/T10** with golden (computed from `ROWS`)
  + axis-2 regex anchors + axis-4 aggregation spec.
- `scorer.py` — axes 1-4 (deterministic gate): numeric correctness, SQL
  anchors, empty-result-honesty, aggregation-semantics.
- `test_scorer.py` — proves the scorer gives a GOOD solution gate-pass and a
  NAIVE (trap) solution gate-fail on the intended axis. **18/18.**
- `seed.sql` — generated; load into the live Oracle `client_product` table.

## Run the validation
```
d=.claude/benchmark/text2sql-v2
python3 $d/fixture.py                       # regenerate seed.sql
PYTHONPATH=$d python3 $d/test_scorer.py     # exit 0 == metrics catch all traps
```

## Traps covered (MVP)
| Task | Trap | Axis that catches naive |
|---|---|---|
| T1 | wrong period / aggregate | ax1 numeric |
| T3 | balance field: direct AVG **or** SUM instead of two-step | ax4 aggregation |
| T6 | total + components double-count | ax2 anchors |
| T8 | single-period instead of two-period set-difference | ax2 anchors |
| T10 | synthesised EOM with no rows → silent empty | ax3 empty-honesty |

## Submission contract (per task)
`{"sql": str, "result": <number|number_map|id_set>, "status": str}` →
`score_submission(task, submission)` → per-axis booleans + `gate_pass`.

## Not yet wired (next steps)
- **Live-Oracle runner**: load `seed.sql` into the docker Oracle, drive the
  agent-under-test's NL→SQL against it, capture `(sql, result, status)` per task,
  feed the scorer. (Golden is verified-by-construction against `ROWS`; a live run
  also confirms Oracle-side date/aggregation behaviour.)
- Remaining tasks (T2/T4/T5/T7/T9 + guardrails G1/G2) and axes 5-9
  (reliability/stability + LLM-judge faithfulness/consistency/depth).
