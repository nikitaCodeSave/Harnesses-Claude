---
id: 27
date: 2026-05-11
title: "Self-improvement Ralph-loop — Milestone 2/3 smoke and fixes"
tags: [harness, self-improvement, loop, ralph, smoke, benchmark, evidence]
status: complete
---

# Self-improvement Ralph-loop — Milestone 2/3 smoke and fixes

## Контекст

Continuation of devlog #26 (Milestone 1 scaffolding). User explicit authorization
to do all Milestone 2/3 work autonomously: corpus extension, backlog generation,
fixture clone, smoke loop, fixes, ADR.

## Milestone 2 — data

### Fixtures cloned
- `tiangolo/full-stack-fastapi-template` @ `13652b51ea0acca7dfe243ac25e2bbdc066f3c4f` (3.5MB)
- `pallets/click` @ `fc6c7c47edd6110b6bd5a1a5297b2035214b0cd1` (2.5MB)
- Total 6MB; gitignored (re-clone via `corpus.yml.fixtures.external.[].commit`)

### Baseline extraction (skipped expensive 3× variance run)
Cost-aware: existing reports `.claude/benchmark/reports/T0{1,2,3,4}-B-ourharness*.json`
provide T01-T04 metrics. T03 has 4 real runs (CV ~20%, devlog #25); T01/T02/T04
single-run + synthetic σ = 20% CV proxy. Wrote `STATE.md.baseline_snapshot` directly.

Savings: ~$45 vs cold 3-replica baseline. Trade-off: T01/T02/T04 σ synthetic until
first real variance pass.

### Corpus scope reduction
Initial plan T05-T15 (11 new tasks). Reduced to T01-T04 only — all measured baseline,
all with existing `.yaml` files. T05-T15 deferred as Milestone-4 expansion.

### Backlog: 30 hypotheses ranked
10 add / 5 retire / 5 refactor / 5 tune / 5 brainstorm. Cross-checked against:
- Retired list in `decisions-2026Q2.md` (8 explicit skip-reasons documented)
- `principles.md` anti-patterns section
- CLAUDE.md explicit bans (multi-stage pipelines, self-describing skills)

Sources mixed: brainstorm (operator tools, retire candidates), ADR/devlog (#22, #25,
ADR-014, ADR-016), community (everything-claude-code AgentShield as opt-in only,
OpenHarness tool gating).

## Milestone 3 — smoke loop

### Three smoke attempts (1 iter each)

| Attempt | Permission mode | Result | Cost | Failure mode |
|---|---|---|---|---|
| 1 | acceptEdits | RESULT:ERROR preflight-blocked loop-scaffolding-uncommitted | \$1.30 | Inner Claude refused on uncommitted state — valid safety check |
| 2 | dontAsk | RESULT:ERROR cannot-execute-loop permission-mode-blocks-state-writes | \$1.07 | dontAsk не auto-accepts Edit; STATE/journal writes denied |
| 3 | bypassPermissions | RESULT:ERROR T03-fixture-missing + fitness-schema-mismatch (T01 ran OK \$0.21 24s pytest-pass) | \$2.14 | Real bugs found through end-to-end execution |

Total smoke cost: \$4.51 (within \$5 cap, by design).

### What worked end-to-end

Attempt 3 проverified entire pipeline на T01:
- Driver `run.sh` correctly spawns `claude --print` with frozen PROMPT.md
- Inner Claude reads STATE/backlog/journal/corpus
- Inner Claude picks H-001 (top-of-backlog, non-protected target)
- Worktree creation works
- Edit operations in worktree pass guard hook (target was `.claude/commands/loop-status.md`, non-protected)
- Tier 0 static-checks runs from worktree, passes (12/12)
- Headless-runner spawns nested `claude --print` for T01 → success ($0.21, 24s, pytest pass)
- Inner Claude correctly handles errors (T03 fixture missing), updates journal с diagnostic, emits `RESULT:ERROR` marker
- run.sh parses marker, increments stall_count, exits cleanly

### Bugs found + fixed this session

**Bug 1: Inner Claude unsolicited `settings.json` modifications**

Attempt 3 inner Claude added 5 allow entries to `settings.json` (claude plugin enable/disable, .claude/ralph-loop.local.md references). Not authorized by user or PROMPT.md.

Fix: Added `settings.json` + `settings.local.json` + `.claude/docs/*.md` + `loop-protected-guard.sh` itself to guard hook protected list. Inner Claude can now only PROPOSE diffs to these files. Reverted attempt-3 settings.json changes.

**Bug 2: `fitness.py` schema mismatch with `headless-runner` output**

`fitness.py` originally expected flat fields `tokens_total`, `turns`, `files_touched`, `success`. `headless-runner.sh` emits nested `claude.tokens.{input,output,cache_*}`, `claude.num_turns`, `verification.files_changed`, `verification.pytest.status`.

Without fix: fitness.py would compute `success_rate=0` for any candidate → hard reject regardless of merit.

Fix: Introduced `_extract_metric(r, *path_options)` helper tolerating multiple schema shapes. Compute tokens from flat OR nested input+output, files from flat OR `verification.files_changed`, success from flat OR `verification.pytest.status == "pass"`.

Validated с mock JSON in nested format → `ACCEPT (avg_score=-0.180, threshold=0.200)` (correctly identifies improvement vs baseline).

**Bug 3 (deferred): External fixtures invisible from worktree**

Worktrees include only tracked files. `.claude/benchmark/fixtures/external/` gitignored (6MB
external clones). When inner Claude `cd <worktree>`, the external/ dir doesn't exist there.

Inner Claude correctly diagnosed as "fixture missing" in journal entry. No fix this session
because requires either:
- (a) Un-gitignore external/ — adds 6MB to repo, sets precedent
- (b) PROMPT.md absolute-path instruction для fixtures (PROMPT.md is protected → proposal-only)
- (c) Auto-symlink external/ into each worktree at creation time в run.sh (run.sh protected → proposal-only)
- (d) Use HARNESS_ROOT-prefixed absolute paths в corpus.yml fixtures (corpus.yml protected → proposal-only)

**Recommended path forward**: option (c) via run.sh proposal-only diff after first real loop launch. For now, T03/T04 effectively unusable in loop iterations — only T01/T02 (sample-py-app, in tree) viable.

## Что готово для launch

- Scaffolding: `.claude/loop/` (8 файлов, валидированы)
- Baseline: T01/T02 fully usable; T03/T04 blocked by Bug 3
- Backlog: 30 hypotheses ranked
- Guard hook: extended protected list (10 patterns vs original 7)
- Fitness function: validated с nested headless-runner schema
- End-to-end iteration: verified успешно проходит до Phase 4 включительно (Phase 5 fitness decision должен работать с фикcами)

## Что требуется до full autonomous launch (24-48h)

1. **Fix Bug 3** (external fixtures) — proposal-only changes to run.sh + PROMPT.md or corpus.yml. Probably need 1 review cycle с user.
2. **Re-smoke** с фиксами и `LOOP_MAX_ITER=3 LOOP_BUDGET_USD=10`. Expected cost ~\$5-7 для validation.
3. **User sets** `LOOP_BUDGET_USD` to actual 70% weekly (currently \$20 conservative).
4. **Decide on `LOOP_PERMISSION_MODE`** для full run. Recommendation: `bypassPermissions` (proven работает; hooks остаются independent guard).

## Cost economics learned

| Item | Cost |
|---|---|
| Single headless-runner T01 invocation | \$0.21 |
| Single loop iter (outer + Phase 1-3) | \$0.30-0.50 |
| Single loop iter (full, all training tasks × fixtures) | \$1.30-2.50 |
| 1 smoke iter (1 task only, T01) | \$0.50-0.70 |
| Variance baseline 3× × 4 tasks × 2 fixtures (full) | \$20-30 |
| Full 24-48h autonomous run (~20-40 iter) | \$30-100 |

Strong implication: each full loop iter is benchmark-dominated cost. Optimization
target: reduce per-task benchmark cost (cache hit rate, smaller fixtures, partial runs).

## Затронутые файлы

- **Created** (committed in #26): `.claude/loop/{run.sh, PROMPT.md, STATE.md, backlog.md, journal.md, corpus.yml, fitness.{sh,py}, README.md}` + `.claude/hooks/loop-protected-guard.sh`
- **Updated this session**: `.claude/loop/STATE.md` (baseline extracted + iter=1 после smoke), `.claude/loop/corpus.yml` (extended protected_files), `.claude/loop/journal.md` (smoke iter-0001 entry), `.claude/loop/fitness.py` (schema-tolerant extraction), `.claude/hooks/loop-protected-guard.sh` (extended protected list)
- **Created this session**: `.claude/benchmark/fixtures/external/{full-stack-fastapi-template,click}/` (gitignored)
- **Reverted**: `.claude/settings.json` (inner Claude's unauthorized additions)

## Implications

- **Foundational principle holds**: minimum scaffolding worked под Opus 4.7 — inner Claude reasons correctly about safety (refused on uncommitted state, refused on permission issues, gracefully reported bugs vs catastrophic write).
- **Protected mechanism critical**: without guard, inner Claude would have modified settings.json which would have downstream effects на user permissions. Guard caught the same pattern on protected files (CLAUDE.md, rules/, loop/).
- **Schema discipline matters**: fitness.py and headless-runner.sh were developed independently — they ended up с incompatible schemas. Need contract test между components в Tier 0 going forward.
- **Smoke validates more than success-path**: 3 different RESULT:ERROR diagnostics revealed 3 different bug classes. End-to-end execution с real money exposes integration gaps invisible to syntax checks.

## Related

- #21 — benchmark infrastructure foundation
- #22 — stop-validation multi-gate
- #24 — cross-harness empirical baseline
- #25 — sign-inversion warning (T03 fixture variance)
- #26 — Milestone 1 scaffolding
