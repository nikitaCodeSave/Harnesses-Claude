# Loop monitoring guide

**Started**: 2026-05-11T00:51:31Z
**PID**: 2121797 (see `RUN.pid`)
**Log**: `.claude/loop/logs/autonomous-20260511T005131Z.log` (see `RUN.log`)
**Config**: budget=$120, wall_clock=48h, stall_cap=10, permission_mode=bypassPermissions

## Quick health check

```bash
cd ~/PROJECTS/Harnesses-Claude

# Process alive?
kill -0 $(cat .claude/loop/RUN.pid) 2>/dev/null && echo "✓ running" || echo "✗ exited"

# Driver progress (most useful)
tail -50 .claude/loop/logs/autonomous-*.log

# Or live tail
tail -f .claude/loop/logs/autonomous-*.log
```

## Compact status (recommended)

В Claude Code сессии используй `/loop-status` slash command (создан iter-0001 H-001 ACCEPT). Outputs compact dashboard: iter count, counters, top backlog, last journal entries, paused status.

## State files (live update each iter)

```bash
# Current iter + baseline snapshot + counters
cat .claude/loop/STATE.md

# All accept/reject events (append-only)
cat .claude/loop/journal.md

# Hypothesis status (pending/accepted/rejected counts)
grep -c "status: " .claude/loop/backlog.md

# Pause? (file exists iff loop paused)
cat .claude/loop/PAUSED.md 2>/dev/null || echo "not paused"

# Reports per iter
ls .claude/loop/reports/
```

## Per-iteration artifacts

```bash
ls -lt .claude/loop/logs/iter-*.log | head -5     # text output
ls -lt .claude/loop/logs/iter-*.json | head -5    # claude --print metadata
```

## Stopping the loop

### Graceful (preferred — completes current iter, no half-state):
```bash
touch .claude/loop/PAUSED.md
# Loop will detect PAUSED.md at next iter boundary and exit cleanly.
```

### Immediate (kill mid-iter — may leave worktree dirty):
```bash
kill -TERM $(cat .claude/loop/RUN.pid)
sleep 2
kill -KILL $(cat .claude/loop/RUN.pid) 2>/dev/null   # if still alive

# Cleanup leftover worktree
git worktree list
git worktree remove --force .claude/loop/worktrees/iter-NNNN
git worktree prune
```

## Resume after pause

```bash
rm -f .claude/loop/PAUSED.md
# Re-launch с теми же env vars:
nohup bash -c '
  export CLAUDE_PROJECT_DIR=/home/nikita/PROJECTS/Harnesses-Claude
  export LOOP_BUDGET_USD=120
  export LOOP_PERMISSION_MODE=bypassPermissions
  export LOOP_WALL_CLOCK_SEC=172800
  export LOOP_STALL_CAP=10
  exec /home/nikita/PROJECTS/Harnesses-Claude/.claude/loop/run.sh
' < /dev/null > .claude/loop/logs/autonomous-$(date -u +%Y%m%dT%H%M%SZ).log 2>&1 &
echo $! > .claude/loop/RUN.pid
```

## Pause triggers (loop will self-pause при любом):

| Trigger | Effect |
|---|---|
| `PAUSED.md` exists at iter start | manual gate; exits cleanly |
| Wall-clock ≥ 48h (172800s) | wall-clock cap; PAUSED.md написан, notify-send |
| Cumulative cost ≥ $120 | budget cap; PAUSED.md, notify |
| 10 consecutive no-improvement iter | stall cap; PAUSED.md, notify |
| `RESULT:NOOP empty-backlog` | backlog exhausted; PAUSED.md, exit |
| Claude --print exit non-zero (timeout/error) | counts as stall, continues |

## Expected behavior

| Phase | Time | Sign of progress |
|---|---|---|
| First 1-2 iter | ~10 min each | `STATE.iteration` increments, journal entries appear |
| Iter 5 | ~50 min in | First retire-bias iter (prefers `type: retire` hypotheses) |
| Iter 10 | ~100 min in | Stall-cap-relevant if no accepts |
| Iter 30 | ~5h in | Backlog should be ~50% consumed |
| Iter 50+ | longer-run | Auto-extend phase — loop may noop if backlog exhausted |

## Cost per iter

Empirical from iter-0001 (smoke): **$4.16** average.
- Outer Claude (PROMPT.md reasoning): ~$3.50 (85%)
- Inner headless-runner per task: $0.20-0.40 each
- 2 train tasks measured per iter → outer dominates

If iter costs significantly higher (>$8), check log for:
- Wandering reasoning (long thinking chains)
- Excessive subagent spawns (cap=3/iter)
- Multi-task expansion (iter ran more than corpus.tasks.split:train count)

## Protected files audit

After ANY accept iter, verify protected scope unchanged:
```bash
git diff HEAD~1 -- .claude/CLAUDE.md .claude/rules/ .claude/docs/ \
  .claude/settings.json .claude/loop/{run.sh,PROMPT.md,corpus.yml,fitness.{sh,py}}
# Expected: empty diff
```

If non-empty: загляни в `.claude/loop/proposals/iter-NNNN-*.diff` — loop should have written proposal there, not direct edit. Если direct edit прошёл — bug в protected-guard hook, остановить loop.

## Debug commands

```bash
# Inner Claude's last reasoning (iter-NNNN.log = stdout text)
cat .claude/loop/logs/iter-NNNN.log

# Inner Claude's metadata (cost, turns, tokens)
jq '.total_cost_usd, .num_turns, .usage' .claude/loop/logs/iter-NNNN.json

# Headless-runner reports (per task per fixture)
ls .claude/loop/reports/iter-NNNN-*.json
jq '.cost_usd, .num_turns, .verification.pytest.status' .claude/loop/reports/iter-NNNN-*.json
```
