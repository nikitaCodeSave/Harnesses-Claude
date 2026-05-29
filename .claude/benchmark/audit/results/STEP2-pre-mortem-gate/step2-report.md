# Step 2: Pre-mortem + real-data evidence gate — battle-test n=3 + audit

**Date**: 2026-05-11
**Modification**: added `discovery-gate.sh` Stop hook, активный когда `HARNESS_BENCH_MODE=1` или присутствует `.claude/.benchmark-active` marker. Hook блокирует Stop пока не созданы:
- `PREMORTEM.md` с ≥4 distinct failure-mode headings (## или ###)
- `EVIDENCE.md` с ≥3 real execution headings (## Run/Test/Execution N)

Hook domain-agnostic: не указывает что искать, только требует discovery-evidence.

**Modified files**:
- `.claude/hooks/discovery-gate.sh` (new)
- `.claude/settings.json` (added hook to Stop array)
- `.claude/benchmark/battle-test-runner.sh` (touch marker + set `HARNESS_BENCH_MODE=1` env)

## Battle-test results (3 ours runs)

| Run | Score | F-Q | LLM-judge | Cost | Wall | Gate blocks |
|---|---:|---:|---:|---:|---:|---:|
| r1 (T180753Z) | 83/100 | 24/30 | 32/43 | $4.67 | 643s (10:43) | 1 |
| r2 (T181921Z) | 88/100 | 27/30 | 34/43 | $3.89 | 561s (9:21) | 1 |
| r3 (T182918Z) | 90/100 | 24/30 | 39/43 | $4.90 | 717s (11:57) | 1 |

**Aggregates**:
- Score: median **88**, range [83, 90] → vs Step 1 baseline median 91 [87, 93] → **−3pt**
- Cost: median **$4.67**, +30% vs baseline $3.46
- Wall: median **643s**, +38% vs baseline 463s
- Gate blocks: 1 per run (agent always blocks once, then creates artifacts)

## Audit results (n=3)

| Run | Total | Critical | Major | Minor | Verified | Reasoned |
|---|---:|---:|---:|---:|---:|---:|
| r1 audit | 24 | 0 | 16 | 8 | 8 | 16 |
| r2 audit | 22 | 0 | 16 | 6 | 12 | 10 |
| r3 audit | 20 | 4 | 10 | 6 | 12 | 8 |

**Sorted [min, median, max]**:

| Metric | Step 1 noharness | Step 1 ours | Step 2 ours+gate | Δ Step2 vs Step1 ours |
|---|---|---|---|---:|
| **Total findings** | [22, 24, 28] m=24 | [24, 24, 24] m=24 | [20, 22, 24] m=**22** | **−2** |
| Critical | [0, 2, 2] m=2 | [0, 0, 4] m=0 | [0, 0, 4] m=**0** | 0 |
| Major | [8, 14, 14] m=14 | [10, 12, 14] m=12 | [10, 16, 16] m=**16** | **+4** |
| **Critical+Major (severe)** | [10, 14, 16] m=14 | [10, 14, 16] m=14 | [14, 16, 16] m=**16** | **+2** |
| Minor | [8, 12, 14] m=12 | [8, 10, 14] m=10 | [6, 6, 8] m=**6** | **−4** |
| Verified | [6, 8, 10] m=8 | [6, 10, 10] m=10 | [8, 12, 12] m=**12** | **+2** |

## Qualitative findings — agent's discovery artifacts

Agent independently discovered failure modes that mirror **production ADRs** in `AI_analyst_migration` (which we never showed it):

**Run 1 PREMORTEM categories** (7):
1. Empty assistant.content after execute_sql (FOUND in own EVIDENCE Run 3 — real regression caught)
2. TOTAL field summed with components (production ADR equivalent — PNL_SUM rule)
3. Date range out of available data (production EOM-beyond-max-data fix equivalent)
4. No LLM timeout (production-grade concern)
5. _coerce Decimal precision loss
6. Module-level import side-effects
7. CLI signal handling

**Run 1 EVIDENCE runs** (5 real Oracle queries):
- Run 1-2: PASS verified
- **Run 3: REGRESSION found** (empty content after execute_sql) — agent's own discovery
- Run 4: PASS verified
- **Run 5: re-run of Run 3 after mitigation** — verified fix

**Run 3 PREMORTEM categories** (6, different focus):
- Trap-field selection (FX vs VED for "valuta payments")
- Non-Qwen Ollama models JSON parsing
- Final answer plain-content fallback
- Closed-month filter returns 0 rows
- Transient network errors
- Rough rounding in NL answer

**Run 3 EVIDENCE runs** (8 real runs incl. trap experiments + edge cases):
- Run 1-3: standard queries PASS
- Run 4: Trap по периоду
- Run 5: Trap field FX vs VED
- Run 7: Trap field без явного слова "ВЭД"
- Run 8: Edge — empty input
- Run 9: Edge — non-existent field

This is dramatically different from Step 1 baseline где tests были моки и agent не делал self-experiments.

## Headline interpretation

**Pre-mortem gate работает as designed**: agent проводит **real discovery work** (high-quality PREMORTEM, real-data EVIDENCE с self-found regressions, trap experiments). Discovery artifacts независимо обнаружили несколько production-ADR-equivalent failure modes.

**НО deliverable quality slightly regressed**: rubric score dropped 91→88 (−3pt), critical+major audit findings increased (+2). Это **paradox**: discovery up, code quality down.

**Root cause hypothesis (data-supported)**:

1. **Time/budget reallocation**: agent потратил ~30-40% extra wall + cost на PREMORTEM/EVIDENCE/experiments — меньше осталось на code refinement. F-Q dropped 27→24 на r1/r3, LLM-judge 37→32 на r1.

2. **Documentation ≠ fixes**: agent честно пишет в PREMORTEM «Mitigation backlog. Не реализовано» — gate forces visibility, не forces fix. LLM-judge видит deliverable + PREMORTEM с known-unfixed gaps → docks code-quality score.

3. **Complexity introduces new bugs**: r3 PREMORTEM добавляет state management для trap-field detection и edge cases. Critic нашёл **4 critical bugs в state machine** (last_result_dict retains stale data, final_answer no precondition) которых не было в Step 1 simpler implementations. Больше кода = больше багов. Surface bugs пофикшены (minor −4), но architectural depth introduces new criticals (+4).

4. **Agent's own discoveries are at "easy-articulate" level** (LIKE-rule, EOM-rule, timeout). Subtler architectural bugs (state machine invariants, precondition violations) agent **systematically misses** — это и есть слой который critic surface'ит.

## Verdict

**Pre-mortem gate: partial signal, NOT a clear win on its own.**

- ✓ Demonstrably drives real discovery work (qualitative win, hard to ignore)
- ✓ Reduces minor audit findings by 40%
- ✓ Agent self-finds real regressions during EVIDENCE testing
- ✗ Doesn't reduce severe (critical+major) findings — actually increases them
- ✗ Rubric score regression −3pt (still well above noise band of ±2-3)
- ✗ Cost +30%, wall +38%

**The gate produces VISIBILITY into known gaps, not FIXES.** It forces the agent to think about failure modes but doesn't enforce addressing them.

## Implication for Step 3 (Critic subagent)

Step 3 design must address what Step 2 cannot:

**Option A — Pure adversarial critic** (original design): Critic finds NEW issues post-PREMORTEM. Risk: just duplicates Step 2 findings since agent already does broad discovery via gate. Low incremental value if Step 2 already covers the easy-articulate layer.

**Option B — Address-or-justify critic**: Critic verifies each PREMORTEM item is FIXED in code OR has explicit accept-risk justification with user-value tradeoff. Block stop if unfixed items lack justification. **Addresses the documentation-not-fix problem directly**.

**Option C — Architectural-depth critic**: Critic specifically probes for state machine, precondition, invariant-violation classes (the layer Step 2 systematically misses). Pre-loaded with prompt template covering these categories. Domain-agnostic.

**Recommendation**: **Option B + C combined**. Critic agent does both:
1. Verify PREMORTEM items addressed (or justified) — solves documentation-not-fix
2. Probes for architectural-depth issues (state, preconditions, invariants) — catches what agent misses

This makes Step 3 **incrementally valuable** over Step 2 rather than redundant.

## Cost summary

- 3 builds × $4.49 avg = $13.46
- 3 audits × ~$1.20 avg = $3.60
- LLM-judge × 3 = ~$0.66
- **Total Step 2: ~$17.72**
- Cumulative Step 1+2: ~$24

## Data files

- Build reports: `.claude/benchmark/reports/2026-05-11-text2sql-step2-r{1,2,3}-*/`
- Audit results: `.claude/benchmark/audit/results/battle-text2sql-ours-2026-05-11T18*/`
- Discovery-gate logs in each clone's `.claude/memory/discovery-gate.jsonl`
- Agent's PREMORTEM.md/EVIDENCE.md preserved in clones at `/tmp/battle-text2sql-ours-2026-05-11T18*/`
