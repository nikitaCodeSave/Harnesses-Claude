# text2sql benchmark v2

Quality-graded, e2e-honest text2sql benchmark mined from the production
`AI_analyst_migration` project. Replaces the primitive v1 task (instant,
pass/fail) with domain traps + ground-truth + 9 correctness axes. Full rationale
and roadmap: [`../text2sql-v2-design.md`](../text2sql-v2-design.md).

**Task shape:** the agent builds a narrow NL→SQL layer (gen + validate + execute
against a live Oracle); we judge **result correctness vs ground-truth** on a
seeded fixture — not "SQL ran".

## Files
- `fixture.py` — single source of truth. `ROWS` defines the seed; emits `seed.sql`
  AND feeds golden computations, so golden never drifts from loaded data.
  `python3 fixture.py` regenerates `seed.sql` (78 rows).
- `tasks.py` — suite **T1-T10 + G1/G2** with golden (computed from `ROWS`),
  axis-2 anchors, axis-4 aggregation spec.
- `scorer.py` — axes 1-4 + refusal gate (deterministic): numeric correctness,
  SQL anchors, empty-result-honesty, aggregation-semantics, honest-refusal.
- `judge.py` — axes 7-9 (LLM-judge): faithfulness / SQL↔NL consistency / depth.
  Uses ollama via env (`AI_ANALYST_API_URL`, `AI_ANALYST_JUDGE_MODEL`); degrades
  to `judge_status="skipped"` if unreachable.
- `runner.py` — orchestration + axes 5-6 (reliability / stability over N≥3 runs);
  `Solver` extension point (`ReferenceSolver` covers all 12 tasks; `AgentSolver`
  skeleton for a real agent-under-test). Live Oracle exec via `oracledb` or
  dry-run degrade.
- `run-bench.sh` — load `seed.sql` into Oracle + run the benchmark.
- `test_scorer.py` (39) · `test_judge.py` (19) · `test_runner.py` (28) — behavior
  tests; good-vs-naive proof that each axis catches its trap.
- `seed.sql` — generated; load into the live Oracle `client_product`.

## Run
```
d=.claude/benchmark/text2sql-v2
python3 $d/fixture.py                          # regenerate seed.sql
PYTHONPATH=$d python3 $d/test_scorer.py        # 39/39
PYTHONPATH=$d python3 $d/test_judge.py         # 19/19
PYTHONPATH=$d python3 $d/test_runner.py        # 28/28
PYTHONPATH=$d python3 $d/runner.py             # full 12-task pass (dry-run if no Oracle)
```

## Suite & traps
| Task | Level | Trap | Axis catching naive |
|---|---|---|---|
| T1 | easy | wrong period / aggregate | ax1 |
| T2 | easy | `COUNT(*)` over snapshot rows vs `COUNT(DISTINCT INN)` | ax2 |
| T3 | medium | balance: direct AVG **or** SUM instead of two-step | ax4 |
| T4 | medium | `GROUP BY MONTH_DT` instead of `CREATE_DT` | ax2 |
| T5 | medium | wrong % base (q4 vs q3) | ax1 |
| T6 | hard | total + components double-count | ax2 |
| T7 | hard | rank by wrong period → wrong top-N | ax1 |
| T8 | hard | single-period instead of two-period set-difference | ax2 |
| T9 | hard | direct AVG on balance in mixed aggregation | ax4 |
| T10 | medium | synthesised EOM with no rows → silent empty | ax3 |
| G1 | guardrail | fabricated credit-load number (no such data) | refusal |
| G2 | guardrail | answers out-of-domain weather question | refusal |

## Axes
- **1-4** (scorer, deterministic gate): numeric vs golden · SQL anchors ·
  empty-honesty · aggregation-semantics. (+ refusal gate for guardrails.)
- **5-6** (runner): reliability/artifact-integrity · stability/flakiness (N≥3).
- **7-9** (judge, LLM): source-faithfulness · SQL↔NL consistency · analytical depth.

## Submission contract
`{"sql": str, "result": <number|number_map|id_set|None>, "status": str, "answer"?: str}`
→ `scorer.score_submission(task, submission)` → per-axis + `gate_pass`.

## Live run
1. `export AI_ANALYST_ORACLE_USERNAME=… AI_ANALYST_ORACLE_PASSWORD=… AI_ANALYST_ORACLE_DSN=host:port/service`
   (or `ORACLE_USER`/`PASSWORD`/`DSN`); `pip install oracledb`.
2. `python3 seed_oracle.py` — loads the fixture into an **isolated**
   `client_product_bench` table (the app's `client_product` is never touched;
   the executor transparently redirects SQL to the bench table).
3. Reference plumbing check: `python3 -c "import runner; print(runner.run_benchmark(solver=runner.ReferenceSolver(), repeats=1)['summary'])"`.
4. Real agent-under-test: `OllamaSolver` (ollama via `AI_ANALYST_API_URL` /
   `AI_ANALYST_SQL_MODEL`) or your own `Solver.solve`. For the LLM-judge set the
   same ollama env. Without a stack, runner/judge degrade (dry-run / skipped).

Result shaping is **per-task** (`tasks.py` `shape`: scalar / ids / map_kv /
map_row / map_pivot); `number_map` keys match case-insensitively (Oracle
upper-cases aliases). `map_row`/`map_pivot` tasks pass an `output_columns`
contract to the agent so aliases line up with golden keys.

## Live baseline (2026-05-29)
ReferenceSolver against the real Oracle XE: **12/12 gate_pass, 12/12 stable**.
A real ollama agent (`Qwen3-30B-A3B-Instruct`, thin schema hint): **5/12** — passes
easy lookups (T1/T2/T7/T10) and the weather-refusal (G2), fails the domain traps
(T3/T9 direct-AVG-on-balance, T4/T5/T6/T8) and **fabricates** the no-data credit
question (G1). See `../reports/2026-05-29-text2sql-v2-ollama-baseline/`. This is
the discrimination a quality benchmark must show.
