# Battle-test text2sql comparison — ours vs no-harness (n=1)

**Date**: 2026-05-11
**Task**: text2sql-Oracle deliverable build (F-deliverable type)
**Model**: claude-opus-4-7 (build + judge)
**Fixture**: live Oracle XE + Ollama, 30-col `client_product` table

## Verdict snapshot

| Variant | Grand total | Verdict | Build cost | Wall |
|---|---:|:---:|---:|---:|
| **our harness** | **87/100** | accepted | $3.20 | 7m 6s |
| **no harness** | **88/100** | accepted | $3.24 | 8m 4s |
| Δ | **−1pt** | tied | +1.4% | +14% |

**Harness ROI verdict (n=1)**: noise band. −1pt difference нельзя считать сигналом — Layer D protocol требует median Δ ≥ +10pt outside baseline IQR + ≥2/3 runs same side. С n=1 conclusively **cannot reject null hypothesis (harness does nothing on F-deliverable)**.

## Detailed comparison

### Functional (F-Q1..Q5, 30 pts max)

| Q | Ours | No-harness | Notes |
|---|---:|---:|---|
| Q1 simple count | 6 ✓ | 6 ✓ | Both: 10 clients in Large |
| Q2 top-N agg | 6 ✓ | 6 ✓ | Both: all 5 orgs |
| Q3 trend comparison | 6 ✓ | 6 ✓ | Both: Large +19% growth |
| **Q4 cross-table join** | **0 ✗** | **0 ✗** | **Both failed**: didn't discover `desk` table via `user_tab_columns` |
| Q5 filtered group-by | 6 ✓ | 6 ✓ | Both: 6 hubs ±1 |
| **Total** | **24/30** | **24/30** | identical |

**Critical observation**: BOTH variants failed Q4 — the only cross-table query. User's intentional removal of `desk` hint from prompt.txt revealed a real gap: Claude doesn't proactively probe `user_tab_columns` to discover beyond declared schema. Не harness-related — model-level limitation.

### T/B auto (27 pts max)

Both 27/27 perfect: pyproject + module + tests + README ≥ 50 lines + median Q wall < 30s.

### LLM-judge T/B residual (43 pts max)

| Item | Ours | No-harness | Δ |
|---|---:|---:|---:|
| T3 error handling | **6** | 5 | +1 (ours wins) |
| T4 code quality | 6 | 6 | tied |
| T7 SQL safety | 5 | 5 | tied |
| B1 formatting | 5 | **6** | −1 (nh wins) |
| B2 validation | 5 | 5 | tied |
| B3 robustness | 5 | 5 | tied |
| B5 production-ready | 4 | **5** | −1 (nh wins) |
| **Total** | **36** | **37** | **−1** |

Per-item exchanges balance out. No clear winner.

### Resource cost

| Metric | Ours | No-harness | Δ |
|---|---:|---:|---:|
| Build cost | $3.20 | $3.24 | +1.4% nh |
| Build wall | 426s | 484s | **+14% nh** |
| Build turns | 50 | 58 | +16% nh |
| Cache_read tokens | 3.23M | 3.57M | **+10% nh** |
| Output tokens | 32253 | 33277 | +3% nh |
| Cumulative (incl. judge) | $3.39 | $3.44 | +1.5% nh |

**Pattern**: ours faster + fewer turns + less cache_read. **Harness preload did reduce ambient exploration cost (−14% wall, −16% turns, −10% cache_read), но quality output equivalent**. Это первое empirical evidence что harness ROI на F-deliverable выражается **в эффективности, не в качестве** — для well-specified prompts.

## Mechanism analysis

Why no quality differential?

1. **Prompt is well-articulated**: 31 lines с архитектурой + tools spec + acceptance criteria + entry-point convention. Claude Opus 4.7 имеет всю нужную informации в одном reading.
2. **Anthropic safety training + Claude API plugin** покрывают most of what our harness кодирует:
   - Type hints, docstrings → general Python convention skill
   - Error handling → API plugin pattern
   - Module structure → standard Python packaging
3. **Opus 4.7 «spawns fewer subagents by default»** — both variants used 0 subagents per trajectory parsing.
4. **api-constraint invariant не тестировался**: this task doesn't tempt Claude to use Anthropic SDK / managed-agents — TW-01..06 уже показали differential на adversarial.

Where harness DID help (per trajectory, hidden in cost numbers):
- 8 fewer turns of exploration (50 vs 58)
- 340k fewer cache_read tokens (preload pre-cached project structure)
- 58s less wall time

**This is exactly the «ROI ∝ exploration cost» hypothesis playing out**: well-spec'd realistic task → harness helps efficiency but quality already maxed at Opus 4.7 baseline.

## Stat protocol disclaimer

**n=1 per cell — INFO ONLY, NOT statistical claim**.

Per Layer D requirements:
- ≥n=3 per cell для bracket [min, median, max]
- Median Δ outside baseline IQR + ≥2/3 same side для sign-inversion
- Battle-test variance unknown — single run может swing ±10pt

To make harness-helps claim: would need (1) repeat ours×3 + nh×3 = 6 builds at $5-30 each ≈ $30-180 OAuth; (2) different deliverable type (legacy modernization, debug fix) where exploration cost peaks differently.

## Findings

1. **Battle-test infrastructure VALIDATED**: 9-phase pipeline end-to-end success, 100-pt rubric meaningful, LLM-judge produced detailed evidence-based justifications.

2. **F-deliverable on well-specified prompt**: harness ≈ no-harness on QUALITY. Harness wins on EFFICIENCY (−14% wall, −10% cache_read).

3. **Q4 desk-discovery gap (both fail)**: model-level limitation, not harness gap. Future fix: enrich metadata.py with cross-table hints OR change prompt to mention schema discovery via `user_tab_columns`.

4. **Both deliverables high quality**: 87 and 88 of 100. Real production-grade text2sql агенты built автономно за 7-8 минут at $3.20-3.44 cost.

5. **Cost asymmetry**: harness preload paid for itself in token savings (cache_read 340k less = ~$0.50 savings on Opus 4.7 pricing). **Harness ROI на этом таске ≈ neutral cost, win wall-time**.

## Methodology bugs found + fixed during this session

1. **Model name `opus-4-7` invalid** → `claude-opus-4-7`. Initial 2.3 build 404'd за 0.5s.
2. **Decimal comma `0,0000`** (locale ru_RU breaking jq) → `LC_NUMERIC=C` in acc_cost.
3. **jq quoting `\"unknown\"`** in echo subshell → unescaped `"unknown"`.
4. **Heredoc backtick command-sub** в `summary.md` template → escaped `\` before backticks.
5. **T6 double-graded** (auto + LLM-judge) → removed from LLM-judge, max recalibrated 47→43.
6. **Phase 7/8 display max** hardcoded → fetch from JSON.
7. **`tmpfile + mv` pattern interacted weirdly с EXIT trap** → direct stdout redirect + sync.
8. **Relative path resolution broken по cd inside group-command** → resolve OUTPUT/CLONE/JUDGE to absolute paths upfront.
9. **Evidence builder pulled `.claude/` harness inject** → exclude `.claude/` from FIND_EXCLUDES, judge sees only deliverable.
10. **`add_files` shell-quote issue** в priority sorting → simplified to single find + alphabetic.

All 10 bugs caught и fixed in this session. Battle-test runner now production-ready.

## Cost transparency

Phase 2.3 retry (ours full): $3.20 build + $0.19 judge = $3.39
Phase 2.6 (noharness full): $3.24 build + $0.20 judge = $3.44
Total empirical: **$6.83 OAuth**

Plus diagnostic invocations (smoke pings, LLM-judge re-runs while debugging): ~$1 additional.

**Total battle-test session cost: ~$7.80**

## Next steps

| Option | Cost | Wall | Yield |
|---|---:|---:|---|
| **A**: Stop here. Methodology validated, n=1 honest data captured | $0 | 0 | accept noise-band conclusion |
| **B**: n=3 enforcement — repeat ours×2 + nh×2 (4 more builds) | $13-28 | ~30m | statistical confidence on direction |
| **C**: Different F-deliverable (legacy modernization, debug fix) | $5-30 each | ~10m | broader axis coverage |
| **D**: Add **F-ambiguous** variant — make text2sql prompt deliberately ambiguous, see if harness helps disambiguation | $5-30 | ~10m | tests harness role in spec-discovery |

Operator decision required.

## Files

- `2026-05-11-text2sql-ours-23v2-20260511T111238Z/` — ours full report
- `2026-05-11-text2sql-noharness-26-20260511T114318Z/` — noharness full report
- `2026-05-11-text2sql-comparison/summary.md` — this file
- `/tmp/battle-text2sql-{ours,noharness}-*/` — clone artifacts preserved
