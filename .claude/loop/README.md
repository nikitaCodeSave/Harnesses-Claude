# Self-improvement Ralph-loop

Cycle that evolves the Claude Code harness via empirical hypothesis testing. Pattern adapted from Mishra-Sharma «Long-running Claude» (Mar 2026) + Huntley ralph-wiggum. Single-thread `claude --print` driven by frozen shell loop with file-based state.

## Files

| Path | Role | Mutated by |
|---|---|---|
| `run.sh` | frozen driver — while-loop, budget gate, cost poll, worktree mgmt | **only human** |
| `PROMPT.md` | frozen idempotent prompt — read by each `claude --print` invocation | **only human** |
| `corpus.yml` | task definitions, train/holdout split, fitness weights | **only human** |
| `fitness.sh` | deterministic accept/reject scorer | **only human** |
| `STATE.md` | current iteration N, baseline snapshot, in-flight hypothesis | loop iteration |
| `backlog.md` | ranked hypotheses (status: pending / in_flight / accepted / rejected / dead) | loop iteration |
| `journal.md` | accepted/rejected/error log (append-only) | loop iteration |
| `proposals/` | diffs for protected-file changes — human reviews | loop iteration |
| `logs/` | per-iteration transcripts (gitignored) | loop iteration |
| `worktrees/` | per-iteration git worktrees (gitignored, ephemeral) | loop iteration |
| `reports/` | benchmark JSON per iteration (gitignored) | loop iteration |
| `PAUSED.md` | written on pause-event with reason; cleared on resume | run.sh |

## Protected files

Loop may PROPOSE but not auto-modify (recursive failure risk):
- `.claude/CLAUDE.md`
- `.claude/rules/*`
- `.claude/loop/{run.sh, PROMPT.md, corpus.yml, fitness.sh}`

Enforced via `.claude/hooks/loop-protected-guard.sh` (active only when `LOOP_MODE=1`).

## Lifecycle

```
run.sh:
  export LOOP_MODE=1
  loop until (budget cap | wall-clock cap | stall cap | PAUSED.md):
    invoke `claude --print` with PROMPT.md
    parse stdout for RESULT:{ACCEPT|REJECT|PROPOSAL|ERROR}
    update counters
    next
```

Inside each `claude --print` invocation (PROMPT.md spec):
1. Read STATE/backlog/journal/corpus
2. Pick hypothesis (retire-bias every 5th iter; holdout validation every K=5)
3. Apply in worktree (or write proposal if protected)
4. Run Tier 0 → reject on fail
5. Run Tier 1 on training subset (variance-checked vs baseline)
6. Call `fitness.sh` → accept or reject
7. Merge ff or drop worktree
8. Update STATE, backlog status, journal
9. Print `RESULT:*` marker

## Invocation

```bash
# Smoke (10 iterations)
LOOP_MAX_ITER=10 ./.claude/loop/run.sh

# Full autonomous (48h max default)
./.claude/loop/run.sh

# Override caps
LOOP_WALL_CLOCK_SEC=86400 LOOP_COST_CAP=50 ./.claude/loop/run.sh
```

## Stop conditions

| Env var | Default | Effect |
|---|---|---|
| `LOOP_MAX_ITER` | unlimited | hard iteration cap |
| `LOOP_WALL_CLOCK_SEC` | 172800 (48h) | pause when exceeded |
| `LOOP_COST_CAP` | 70 | pause when subscription usage ≥ N% weekly |
| `LOOP_STALL_CAP` | 10 | pause after N consecutive no-improvement iter |

Plus: presence of `PAUSED.md` at iter start → exit.

## Notify

On pause-event:
- Write `PAUSED.md` with reason + iteration N + timestamp
- `notify-send "Loop pause" "<reason>"` if available

## Acceptance contract (fitness.sh formula)

```
ACCEPT iff:
  tier0_status == "pass" AND
  success_rate_delta >= 0 (hard) AND
  weighted_cost_score within ±threshold (per corpus.yml.fitness) AND
  no protected-file direct modifications AND
  hypothesis target not in retired-components list

weighted_cost_score =
  0.5 * (tokens_delta_pct / 100) +
  0.3 * (turns_delta_abs / max_turns_baseline) +
  0.2 * (files_delta_abs / max_files_baseline)
```

Variance guard: only count delta as signal if `|delta| > 2σ` of task-specific baseline.

## Smoke-loop pre-flight

Before full launch:
1. Tier 0 green (`.claude/benchmark/static-checks.sh`)
2. Variance baseline ran (`STATE.baseline_snapshot` populated for all training tasks)
3. Backlog ≥ 30 ranked hypotheses
4. Fixtures cloned (`fixtures.external.*.path` exist)
5. `loop-protected-guard.sh` wired in `settings.json`
6. `notify-send` available (or fallback documented)

См. `.claude/devlog/entries/0026-*-loop-bootstrap.md` for bootstrap progress.
