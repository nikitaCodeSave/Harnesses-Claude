---
# Hypothesis backlog (ranked)
# Generated 2026-05-11 in Milestone 2.
#
# Format per entry:
# ## H-NNN <title>
# - type: add | retire | refactor | tune
# - target: file/component
# - rationale: 1-2 sentences why expected to help
# - expected_delta: tokens=±X%, turns=±N, success=±0
# - source: ADR-NNN | devlog-NNN | community:<repo> | brainstorm
# - retired_check: pass | skip-revives-retired
# - status: pending | in_flight | accepted | rejected | dead
---

# Backlog

30 hypotheses ranked by expected ROI × ease-of-test. Filtered against retired-components
list from CLAUDE.md, principles.md anti-patterns, decisions-2026Q2.md archive.

## ADD candidates (10)

### H-001 Loop-status slash command
- type: add
- target: .claude/commands/loop-status.md
- rationale: Quick inspection без чтения 5 файлов state. Reduces context-load on operator.
- expected_delta: neutral on benchmark (operator-facing tool)
- source: brainstorm
- retired_check: pass
- status: accepted  # iter-0001 ACCEPTED (avg_score=-0.089, T01/T02 measured, T03 skipped — external fixture issue)

### H-002 Metrics aggregator across iterations
- type: add
- target: .claude/loop/aggregate-metrics.py
- rationale: Parse all reports/iter-*.json → trend chart. Helps detect drift early.
- expected_delta: neutral on benchmark (telemetry)
- source: brainstorm
- retired_check: pass
- status: accepted  # iter-0002 ACCEPTED (avg_score=+0.000, T01/T02 measured, T03 skipped)

### H-003 Stop-hook regression-check
- type: add
- target: .claude/hooks/stop-validation.sh (extend)
- rationale: Delta vs last accepted baseline. Catches silent regressions earlier.
- expected_delta: success_rate guard tighter; cost +5% (extra check)
- source: devlog #22 stop-validation
- retired_check: pass
- status: accepted  # iter-0003 ACCEPTED (avg_score=+0.000, T01/T02 measured, T03 pytest=skipped infra-bug; RED/GREEN smoke-tested locally: prior 5p → current 2p → regression:fail)

### H-004 SessionStart preload current STATE.md
- type: add
- target: .claude/hooks/session-context.sh (extend)
- rationale: When человек opens shell, auto-inject STATE summary. Saves "what was happening".
- expected_delta: neutral on bench; UX win
- source: ADR-016 pilot pattern
- retired_check: pass
- status: accepted  # iter-0004 ACCEPTED (avg_score=+0.137 < threshold 0.200; T01 noise + T02 tokens 2501→3869 signal absorbed; T03 pytest=skipped infra-bug, excluded from fitness глобом)

### H-005 UserPromptSubmit cost-warn hook
- type: add
- target: .claude/hooks/cost-warn.sh
- rationale: If cumulative iter cost > expected → warn before next iter. Prevents silent budget blow.
- expected_delta: cost cap firing earlier; user-confidence
- source: brainstorm
- retired_check: pass
- status: accepted  # iter-0006 ACCEPTED (avg_score=+0.000, T01/T02 measured, T03 skipped; settings.json wiring pending — file-only ACCEPT)

### H-006 Fixture bootstrap helper
- type: add
- target: .claude/benchmark/fixtures/external/bootstrap.sh
- rationale: One-command re-clone via commits in corpus.yml. Reproducibility.
- expected_delta: neutral
- source: brainstorm
- retired_check: pass
- status: accepted  # iter-0007 ACCEPTED (avg_score=+0.000, T01/T02 measured, T03 excluded — PYTEST_TARGETS infra blocker; file relocated to .claude/benchmark/bootstrap-fixtures.sh because target path .claude/benchmark/fixtures/external/ is gitignored)

### H-007 Per-task variance report
- type: add
- target: .claude/loop/variance-report.py
- rationale: Flag tasks с CV > 30%. Sign-inversion early-warn (devlog #25).
- expected_delta: reliability of accept/reject signal
- source: devlog #25 sign-inversion
- retired_check: pass
- status: accepted  # iter-0008 ACCEPTED (avg_score=+0.000; 12 tests pass; CLI smoke OK; real-data run shows T01 CVs <8%, T02 CVs <19% — within synthetic 20% CV proxy; T03/T04 n=1 → below_min_n=true; T01/T02 benchmark pytest=pass, all deltas within 2σ)

### H-008 Cross-fixture variance comparator
- type: add
- target: .claude/loop/cross-fixture-check.py
- rationale: Same task different fixture → opposite sign? Alert. Direct lesson of #25.
- expected_delta: reduces false-positive accepts
- source: devlog #25
- retired_check: pass
- status: accepted  # iter-0009 ACCEPTED (avg_score=+0.000; 17 tests pass; CLI smoke OK — spread 200% + SIGN_INVERSION detected on synthetic; real data has no task on ≥2 fixtures yet, tool acts as tripwire until corpus expands; T01/T02 benchmark pytest=pass, all deltas within 2σ)

### H-009 Proposals review index
- type: add
- target: .claude/loop/proposals/REVIEW.md (auto-generated)
- rationale: Index of pending proposals so человек knows what awaits.
- expected_delta: governance, neutral on bench
- source: brainstorm
- retired_check: pass
- status: accepted  # iter-0011 ACCEPTED (avg_score=+0.000; 19 tests pass; CLI smoke OK — synth diff + journal PROPOSAL → REVIEW.md correctly indexes; --check exit 1 when pending; tripwire-only until first H-018/H-020/H-021..H-025/H-028/H-029 fires; T01/T02 benchmark pytest=pass, all deltas within 2σ)

### H-010 ECC AgentShield-style security review (opt-in)
- type: add
- target: .claude/agents/security-reviewer.md
- rationale: Opt-in only for security-sensitive PRs (PROPOSAL — touches protected file pattern).
- expected_delta: cost +20% когда invoked; success rate ↑ для security tasks
- source: community:everything-claude-code (Anthropic Hackathon winner)
- retired_check: pass (opt-in, not mandatory; spawn policy (a) — context isolation)
- status: accepted  # iter-0012 ACCEPTED (avg_score=+0.000; 66-line agent file: tools=Read/Glob/Grep/Bash, model=opus, 7-item checklist; T01/T02 benchmark pytest=pass, all deltas within 2σ; tripwire-only until first PROPOSAL diff fires)

## RETIRE candidates (5)

### H-011 Retire dangerous-cmd-block.sh
- type: retire
- target: .claude/hooks/dangerous-cmd-block.sh + settings.json wiring
- rationale: Overlaps с permissions.deny list (rm/sudo/curl already denied). Empirically redundant.
- expected_delta: cost -3% (hook overhead removed); success unchanged
- source: brainstorm + permission-deny inspection
- retired_check: pass (not in retired list)
- status: accepted  # iter-0013 PROPOSAL applied 2026-05-11 by operator (solo-dev «свободный конфиг» preference: less Claude-control surface). Hook + settings.json wiring removed.

### H-012 Retire secret-scan.sh
- type: retire
- target: .claude/hooks/secret-scan.sh + settings.json
- rationale: Already gitignore'd secrets. Permission-deny на Read paths. Hook = third layer of redundancy.
- expected_delta: cost -3%
- source: brainstorm
- retired_check: pass
- status: accepted  # iter-0014 PROPOSAL applied 2026-05-11 by operator (solo-dev preference, gitignore sufficient guard). Hook + settings.json wiring removed.

### H-013 Retire deliverable-planner agent
- type: retire
- target: .claude/agents/deliverable-planner.md
- rationale: ADR-014 already noted criteria emerge organically под Opus 4.7. Agent rarely invoked.
- expected_delta: cost neutral (agent rarely invoked); CLAUDE.md cleanup
- source: ADR-014 + CLAUDE.md soft-guidance note
- retired_check: pass
- status: accepted  # iter-0016 ACCEPTED (avg_score=+0.000, T01/T02 measured, T03 excluded — PYTEST_TARGETS infra blocker; all deltas within 2σ; first non-PROPOSAL retire; CLAUDE.md reference to deliverable-planner now stale — followup PROPOSAL candidate)

### H-014 Retire auto-format.sh PostToolUse hook
- type: retire
- target: .claude/hooks/auto-format.sh + settings.json wiring
- rationale: Per-language ad-hoc invocation cleaner than blanket hook. Hooks-discipline rule «only когда action must happen every time».
- expected_delta: cost -2%; possible style drift
- source: principles.md hooks section
- retired_check: pass
- status: accepted  # iter-0017 PROPOSAL applied 2026-05-11 by operator. Hook + entire PostToolUse section + settings.json wiring removed.

### H-015 Retire .claude/output-styles/ + .claude/commands/ legacy dirs
- type: retire
- target: .claude/output-styles/, .claude/commands/
- rationale: Empty/legacy. .claude/skills/ supersedes per ADR-016.
- expected_delta: neutral
- source: ADR-016
- retired_check: pass
- status: rejected  # iter-0018 REJECTED — stale-rationale dead-on-arrival: `.claude/commands/` hosts H-001's `loop-status.md` (ACCEPT iter-0001 same day backlog was generated 2026-05-11 in Milestone 2, before H-001 was applied) — retiring whole commands/ would regress H-001; `.claude/output-styles/` empty but 0 git-tracked files, `rmdir` would be filesystem-only non-committable no-op. Verified: `git ls-files .claude/output-styles/ .claude/commands/` → only `commands/loop-status.md` tracked. No worktree, no benchmark (Phase 3-5 skipped — apply impossible). First non-PROPOSAL/non-ERROR REJECT in loop history.

## REFACTOR candidates (5)

### H-016 Consolidate workflow.md + multi-agent.md overlap
- type: refactor
- target: .claude/docs/workflow.md + multi-agent.md
- rationale: Both cover spawn policy. Single source of truth. Saves ~80 lines of context cost.
- expected_delta: tokens -5% (less context when read on-demand); turns neutral
- source: brainstorm reading existing docs
- retired_check: pass
- status: accepted  # iter-0019 PROPOSAL applied 2026-05-11 by operator. workflow.md + multi-agent.md consolidated; net -49 lines.

### H-017 Headless-runner parse json directly (not grep)
- type: refactor
- target: .claude/benchmark/headless-runner.sh
- rationale: Currently extracts via grep/sed on raw output. JSON parsing more robust.
- expected_delta: reliability ↑; cost neutral
- source: code-read headless-runner.sh:35-42
- retired_check: pass
- status: rejected  # iter-0021 REJECTED — stale-rationale dead-on-arrival (second case after H-015). Verified against current code state (.claude/benchmark/headless-runner.sh HEAD 0766f1a): Claude output JSON metric extraction ALREADY uses jq (lines 146-154: num_turns, total_cost_usd, usage.{input_tokens,output_tokens,cache_creation_input_tokens,cache_read_input_tokens}, result, stop_reason) since first commit b5fcfd1 (verified via `git show b5fcfd1:.claude/benchmark/headless-runner.sh`); `command -v jq` is hard requirement at line 45 (exits early without jq); remaining grep/sed is ONLY on task YAML keys (lines 80-81: `id:` + `prompt:`), works correctly on all 5 current task YAMLs (T01/T02/T03/T03e/T04 all flat single-line scalar). No `grep` on JSON exists anywhere in script. Hypothesis as written ("parse json directly (not grep)") cannot apply — change is no-op. Backlog source-pointer `code-read headless-runner.sh:35-42` references arg parser block (lines 35-42 then AND now), not parsing logic — misformulated at backlog generation 2026-05-11. No worktree created (no apply possible), no benchmark run (Phase 3-5 skipped). Second stale-rationale REJECT in 4 iters (H-015 iter-0018, H-017 iter-0021) meets STATE.md iter-0018 «watch for second stale-rationale REJECT in next ~5 iters» trigger — backlog hygiene tool justified as future hypothesis candidate (pre-pick rationale-validation pass that re-checks each pending hypothesis's stated assumptions against current state, e.g., `grep -l "raw output" headless-runner.sh` or AST-level greps for target patterns).

### H-018 git stash save before each iteration
- type: refactor
- target: .claude/loop/run.sh (PROTECTED — proposal-only)
- rationale: Even with worktree isolation, accidental main-tree edit → stash auto-saves.
- expected_delta: reliability ↑
- source: brainstorm
- retired_check: pass (proposal-only against protected)
- status: rejected  # iter-0022 PROPOSAL rejected 2026-05-11 by operator. Solo-dev preference for less ceremony; uncommitted-state pattern between iters is intentional, opt-in stash adds surface area without observed need.

### H-019 Move T05-T07 stubs into yaml files
- type: refactor
- target: .claude/benchmark/tier1/tasks/T05*.yaml, T06*.yaml, T07*.yaml
- rationale: benchmark.md table → real yaml. Unlocks T05/T06/T07 в loop training.
- expected_delta: corpus size +3; benchmark coverage ↑
- source: benchmark.md
- retired_check: pass
- status: rejected  # iter-0023 REJECTED — fitness avg_score=+0.305 > 0.200 (T01 +0.320, T02 +0.291). Root cause: harness-inject artifact in verification.files_changed metric. Adding 3 YAMLs to .claude/benchmark/tier1/tasks/ ships them into every fixture clone via cp -r .claude/ inject, bumping T01 files_changed 10→26 (+16, exceeds 2σ=4) and T02 11→27 (+16, exceeds 2σ=4.4). With files weight 0.2 × (16/10)=0.32 and 0.2 × (16/11)=0.291, weighted_score above 0.20 threshold despite zero functional regression (tokens within 2σ, turns unchanged, pytest=pass both tasks, claude exit=0 both). Baseline caveat «T01 files=90 includes harness inject artifacts» (STATE.md) anticipated this class of false-positive but was not actionable here — variance σ on files metric (2.0 / 2.2) too tight to absorb 16-file inject delta. Lesson: pure-additive .claude/ changes WILL trigger files_changed signal on any task with INJECT_HARNESS=1; H-019-style backlog additions need either (a) rebaselining files_mean after corpus expansion, (b) files weight reduction, (c) headless-runner.sh stop counting injected harness files in verification (subtract harness inject footprint), or (d) accept hypothesis design that adds task YAMLs simultaneously wires them into corpus.yml (PROPOSAL path — protected file) so files inject becomes part of new baseline.

### H-020 Move CLAUDE.md API constraint section → .claude/rules/api-constraint.md
- type: refactor
- target: .claude/CLAUDE.md (PROTECTED — proposal-only) + .claude/rules/api-constraint.md
- rationale: CLAUDE.md как indexer не store (docs-discipline rule 2). API constraint = invariant → rules/.
- expected_delta: CLAUDE.md size -15 lines; clarity ↑
- source: docs-discipline.md rule 2
- retired_check: pass (target proposal-only)
- status: accepted  # iter-0026 PROPOSAL applied 2026-05-11 by operator. CLAUDE.md body trimmed; .claude/rules/api-constraint.md created (docs-discipline rule 2).

## TUNE candidates (5)

### H-021 retire_bias every_k_iter 5 → 3
- type: tune
- target: .claude/loop/corpus.yml (PROTECTED — proposal-only)
- rationale: More aggressive retirement pressure. Counters add-bias inherent в exploration.
- expected_delta: trim rate ↑; total component count ↓
- source: foundational principle «retire as readily as add»
- retired_check: pass (proposal-only)
- status: accepted  # iter-0027 PROPOSAL applied 2026-05-11 by operator. retire_bias.every_k_iter: 5→3 (fixes holdout-collision scheduling bug).

### H-022 sigma_multiplier 2 → 1.5
- type: tune
- target: .claude/loop/corpus.yml (PROTECTED — proposal-only)
- rationale: Current 2σ very conservative. 1.5σ ≈ 87% confidence — still robust.
- expected_delta: accept rate +; risk of false accepts
- source: stat best-practice
- retired_check: pass (proposal-only)
- status: rejected  # iter-0028 PROPOSAL rejected 2026-05-11 by operator. Solo-dev preference against deeper corpus.yml tuning; iter-0035 bipolar variance outlier makes σ-tightening hazardous without re-baseline.

### H-023 subagent_cap 3 → 1
- type: tune
- target: .claude/loop/corpus.yml (PROTECTED — proposal-only)
- rationale: Pure single-thread per Opus 4.7 spawn-fewer-default. Cost predictability ↑.
- expected_delta: cost -10% per iter; isolation lost
- source: principles.md spawn policy
- retired_check: pass (proposal-only)
- status: rejected  # iter-0029 PROPOSAL rejected 2026-05-11 by operator. Forecloses CLAUDE.md spawn policy (b) parallelism; cap=3 never hit empirically so change is performative.

### H-024 holdout_cadence 5 → 7
- type: tune
- target: .claude/loop/corpus.yml (PROTECTED — proposal-only)
- rationale: Holdout expensive (extra iter без accept). 7 saves ~6% время without much overfit risk.
- expected_delta: total time -6%; overfit-detect лаг slightly ↑
- source: brainstorm
- retired_check: pass (proposal-only)
- status: rejected  # iter-0031 PROPOSAL rejected 2026-05-11 by operator. iter-0035 bipolar variance — holdout is the ONLY signal channel for invocation noise; reducing frequency now is wrong direction.

### H-025 weighted_score_delta_max 0.20 → 0.15
- type: tune
- target: .claude/loop/corpus.yml (PROTECTED — proposal-only)
- rationale: Stricter accept gate. Better long-term harness quality at cost of slower exploration.
- expected_delta: accept rate ↓; reject rate ↑
- source: brainstorm
- retired_check: pass (proposal-only)
- status: rejected  # iter-0032 PROPOSAL rejected 2026-05-11 by operator. Same reasoning as H-022 — tighter accept gate hazardous on bipolar variance baseline; needs re-baseline first.

## EXTRA brainstorm (5)

### H-026 Add `claude --output-format` field validator
- type: add
- target: .claude/loop/validate-claude-output.sh
- rationale: Verify `.total_cost_usd` exists in current CLI version. Future-proof.
- expected_delta: reliability across CLI updates
- source: risk-from-Milestone-1
- retired_check: pass
- status: accepted  # iter-0033 ACCEPTED (avg_score=+0.000, threshold=0.200; T01/T02 pytest=pass, all deltas within 2σ noise — T01 tokens -344, T02 tokens -474, both improvement direction; files=10/11 UNCHANGED confirming iter-0024 path-semantic-bug root cause for iter-0023 H-019 REJECT; T03 skipped PYTEST_TARGETS infra blocker). 168 LOC across 2 new files (.claude/loop/validate-claude-output.sh 71 lines + test 97 lines); script mirrors headless-runner.sh:147-154 jq paths (8 required fields .num_turns/.total_cost_usd/.usage.{input,output,cache_creation_input,cache_read_input}_tokens/.result/.stop_reason); two modes (--live default invokes claude --print, --from-file for static validation + unit tests); test suite 6/6 pass (valid→0, missing-top→1, missing-nested→1, malformed→1, no-file→2, bad-arg→2). Operator-invocation tool — not auto-run by loop iter. Tripwire against CLI field drift after `claude` upgrades.

### H-027 Add OpenHarness tool-gating check
- type: add
- target: .claude/benchmark/static-checks.sh (extend Tier 0)
- rationale: Count active tools, flag >20. Pattern from leaked Claude Code analysis.
- expected_delta: tool selection quality ↑ (long-term)
- source: community:OpenHarness
- retired_check: pass (selectivity, not wholesale)
- status: accepted  # iter-0024 ACCEPTED (avg_score=+0.000, threshold 0.200; T01/T02 pytest=pass, all deltas within 2σ noise; T03 skipped PYTEST_TARGETS infra blocker); +15 lines static-checks.sh, new Check 10 «Tool-gating ≤ 20» counts agents/hooks/skills/commands = 12 currently. Tripwire-only until harness growth approaches threshold. Modify-existing-file path validated as antidote to iter-0023 H-019 files-inflation (no new files added → no T01/T02 files_changed delta beyond baseline). Also surfaced (and worked around in invocation) ongoing inject-from path semantic debt: PROMPT.md says <worktree>/.claude, headless-runner.sh expects <worktree>.

### H-028 Add backlog auto-prune on N consecutive rejects
- type: add
- target: .claude/loop/PROMPT.md (PROTECTED — proposal-only)
- rationale: Prevent revisiting same dead hypothesis class. Adaptive backlog.
- expected_delta: stall risk ↓; iteration efficiency ↑
- source: brainstorm
- retired_check: pass (proposal-only)
- status: accepted  # iter-0034 PROPOSAL applied 2026-05-11 by operator. Picker rule 4 stale-breaker added; Normal renumbered 4→5.

### H-029 Add devlog auto-entry on accept
- type: add
- target: .claude/loop/PROMPT.md (PROTECTED — proposal-only) — instruct create devlog entry on accept
- rationale: Audit trail. Each accept = devlog → human can scan что менялось без полного read journal'а.
- expected_delta: cost +5% (devlog write); audit trail ↑
- source: docs-discipline.md
- retired_check: pass (proposal-only)
- status: rejected  # iter-0037 PROPOSAL rejected 2026-05-11 by operator. Devlog parallel to journal.md adds runtime cost + failure surface without proportional audit value; if needed later, prefer offline journal-to-devlog rollup.

### H-030 Add ADR-trigger detection
- type: add
- target: .claude/hooks/adr-trigger-detect.sh (PreToolUse Write)
- rationale: When Claude writes file touching architecture decision (renaming dir, removing component), suggest ADR. Per docs-discipline rule 6.
- expected_delta: ADR coverage ↑; cost +2%
- source: docs-discipline.md rule 6
- retired_check: pass
- status: rejected  # iter-0036 REJECT — third stale-rationale dead-on-arrival case (after H-015/H-017). Pre-apply rationale check found 4 disqualifying conditions: (1) hooks-discipline N≥3 incidence threshold per .claude/hooks/README.md NOT MET (no journal.md occurrence of Claude missing ADR-trigger); (2) hook = self-description anti-pattern (docs-discipline.md rule 6 already in CLAUDE.md reference list, model reads natively — stderr-advisory hook is rule retransmission); (3) target/rationale scope mismatch (rationale enumerates `mv`/`rm`/`git rm` Bash triggers but matcher is PreToolUse Write — cannot observe rename/remove); (4) block-at-write timing flavor (CLAUDE.md/README anti-pattern «block-at-submit, not block-at-write» applies even to non-blocking stderr advisories). H-030 differs from prior stale-rationale REJECTs in being apply-possible but design-conflict-with-canonical (vs H-015/H-017 which were apply-no-op). Counter-design candidate not pursued this iter: observation-only logger to .claude/memory/adr-trigger.jsonl (no stderr, no Claude visibility) — environment-configurator not self-description, would gather N≥3 evidence for principled future hook adoption (recommended as H-037 operator action — not added to backlog this iter).

---

## Retired/skipped candidates (cross-check log)

- Superpowers 7-phase pipeline → **SKIPPED**: multi-stage PM→Arch→Dev→QA anti-pattern (CLAUDE.md explicit ban + ADR-007/010 retirement).
- Chachamaru127 verb-skills (plan/execute/review/release/setup) → **SKIPPED**: self-describing skills retired per ADR-016 + CLAUDE.md «self-описывающие skills — anti-pattern».
- atomic 5-phase deterministic workflow as skill → **SKIPPED**: same as verb-skills.
- Karpathy 4-rule template wholesale paste → **SKIPPED**: would push CLAUDE.md > 200 lines (yunbow experiment violation).
- Generator/Evaluator контракт for every iteration → **SKIPPED**: explicit anti-pattern CLAUDE.md + retired ADR.
- Free-form debate rounds between agents → **SKIPPED**: retired (decisions-2026Q2.md).
- Fixed thinking budgets → **SKIPPED**: deprecated (Opus 4.7 adaptive).
- Block-at-write hooks mid-thought → **SKIPPED**: retired pattern; PreToolUse instead.

## Notes

- Status legend: `pending` → не пробовал; `in_flight` → текущая итерация; `proposed` → diff в proposals/ awaiting human review (PROTECTED target — picker skips); `accepted` → merged; `rejected` → пробовал, fitness reject; `dead` → multiple rejects of same idea, не возвращаемся.
- Proposal-only entries (against protected) — loop writes diff в `proposals/`, человек ревьюит batch'ем.
- Backlog reorder возможен между итерациями (loop может deprioritize при низком ROI).
