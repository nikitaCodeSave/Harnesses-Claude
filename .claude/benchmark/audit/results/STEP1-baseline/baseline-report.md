# Step 1 baseline: adversarial post-test audit of existing battle-test artifacts

**Date**: 2026-05-11
**Method**: domain-aware critic in fresh Claude session, read-only access to artifact + spec, 10-min budget per artifact. Emits structured JSON-line findings + summary.
**Spec**: same MVP-prescriptive `prompt.txt` as battle-test (literally specifies 4 tools).
**Artifacts**: 3 ours + 3 noharness from `/tmp/battle-text2sql-*` (n=3 comparison run 2026-05-11).
**Audit model**: claude-opus-4-7.
**Total audit cost**: ~$6 OAuth (6 × ~$1).

## Discovery metric

Number of distinct failure modes the audit found *post-build*. Lower = harness pushed agent to discover/address more during build. Higher = audit found gaps the build phase missed.

## Bracket [min, median, max]

| Metric | ours | noharness | Δ median |
|---|---|---|---:|
| **Total findings** | [24, 24, 24] | [22, 24, 28] | **0** (tied) |
| Critical | [0, 0, 4] | [0, 2, 2] | -2 (ours 1 fewer) |
| Major | [10, 12, 14] | [8, 14, 14] | -2 (ours 2 fewer) |
| **Critical + Major (severe)** | [10, 14, 16] | [10, 14, 16] | **0** (tied) |
| Minor | [8, 10, 14] | [8, 12, 14] | -2 |
| Verified (demonstrated) | [6, 10, 10] | [6, 8, 10] | +2 |
| Reasoned (code-cited) | [14, 14, 14] | [12, 18, 20] | -4 |

## Headline

**Both harness и no-harness produce artifacts с ~24 audit findings, ~14 серьёзных (critical+major).** Existing harness не drives discovery — оно lift'ит floor на narrow F-Question correctness, но **structural depth of deliverable идентичен**.

Это **confirms** прошлую floor-lift гипотезу для F-Quality, но также добавляет новый insight: **на discovery-метрике harness и noharness статистически tied на n=3**. Это и есть тот gap, который Step 2 (pre-mortem gate) должен закрывать.

## Sample of findings (ours-r3, T121938Z, 24 finds)

Independent of which artifact (ours/nh), critic surfaced the same classes of failure modes that production text2sql project (`AI_analyst_migration`) had to discover and address iteratively:

1. **Semantic bug: MONTH_DT EOM vs snapshot date** (`prompts.py:13-16`). Match с production ADR — current-month uses last snapshot date, не EOM. Severity: major. Demonstrability: reasoned.
2. **SQL validator rejects legitimate queries with `'%delete%'` etc** — regex matches inside string literals. Severity: major. Verified by running `assert_readonly_sql`.
3. **Multi-statement detector breaks on `';'` inside string literal**. Severity: major. Verified.
4. **`max_rows` silently capped to 1000** — agent has no way to opt out, `truncated=true` is passive flag. Severity: major. Reasoned.
5. **`validate_result` only inspects `rows[0]`** — downstream nulls/negatives go unreported. Severity: major. Reasoned.
6. **Decimal → float precision loss for large monetary aggregates**. Severity: minor. Reasoned.

Every one of these maps to a real production discovery in `AI_analyst_migration` (LIKE-constraint validator, EOM-beyond-max-data fix, semantic monetary handling, nested-aggregate detection).

## Interpretation

The existing harness produces deliverables that satisfy **spec literally** (4 tools, working end-to-end) but **miss the same domain-specific failure modes** as no-harness deliverables. Both score ~91/87 on the 100-pt rubric but leave ~14 serious issues undiscovered.

**Mechanism**: spec is MVP-prescriptive. Agent reaches final_answer once spec criteria met. No internal trigger drives discovery beyond spec.

## What Step 2 (pre-mortem + evidence gate) should change

If discovery-gate hook works as designed, Step 2 ours artifacts should have:
- **Fewer audit findings overall** (agent discovered + addressed during build)
- **Especially fewer major + critical** (gate forces ≥4 distinct categories of failure mode discovery)
- **EVIDENCE.md** with ≥3 real Oracle executions (vs current mock tests)
- **Same or slightly higher build cost/wall** (gate adds 1-3 additional turns)

Failure mode for Step 2 hypothesis:
- Agent writes shallow PREMORTEM.md (4 generic headings, no real depth) — gate passes, no discovery actually happened.
- Agent writes EVIDENCE.md with mock-only "real" executions.

If observed: tighten gate criteria for Step 3.

## Data files

- `findings.jsonl` per artifact in `/home/nikita/PROJECTS/Harnesses-Claude/.claude/benchmark/audit/results/battle-text2sql-*-{TS}/`
- `summary.json` per artifact with parsed counts.

## Audit cost summary

| Run | Wall (s) | Cost ($) | Turns | Total | Critical | Major | Minor | Verified |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| ours-r1 (T111238Z) | ~200 | ~1.0 | ~22 | 24 | 4 | 12 | 8 | 10 |
| ours-r2 (T121032Z) | ~200 | ~1.0 | ~22 | 24 | 0 | 10 | 14 | 10 |
| ours-r3 (T121938Z) | 195 | 1.14 | 24 | 24 | 0 | 14 | 10 | 6 |
| nh-r1 (T114318Z) | ~200 | ~1.0 | ~22 | 24 | 2 | 14 | 8 | 6 |
| nh-r2 (T122801Z) | ~200 | ~1.0 | ~22 | 28 | 0 | 14 | 14 | 8 |
| nh-r3 (T123526Z) | ~200 | ~1.0 | ~22 | 22 | 2 | 8 | 12 | 10 |

Total: ~$6 OAuth, ~20 min wall (parallel run).
