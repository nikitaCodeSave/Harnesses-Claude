# Loop iteration prompt — FROZEN

> Этот prompt **idempotent** и читается `claude --print` каждой итерации. НЕ модифицируется loop'ом (защищён `loop-protected-guard.sh`). Изменения — только через human-reviewed proposal.

You are running iteration N of the Claude Code harness self-improvement loop. Your job: pick ONE hypothesis from the backlog, test it empirically, accept or reject based on `fitness.sh`. Exit cleanly with `RESULT:*` marker.

## Phase 1 — Read state

Read in this order, no exception:
1. `.claude/loop/STATE.md` — current iteration, baseline snapshot, in-flight hypothesis
2. `.claude/loop/corpus.yml` — task definitions, fitness config, retire_bias cadence
3. `.claude/loop/backlog.md` — ranked hypotheses
4. `.claude/loop/journal.md` — last 50 entries (avoid re-trying dead hypotheses)
5. `.claude/docs/archive/decisions-2026Q2.md` — retired ADRs (cross-check before applying)

## Phase 2 — Pick hypothesis

Rules (first match wins):

1. **Resume in-flight**: If STATE.md `in_flight_hypothesis != null` → resume that hypothesis (don't pick new).
2. **Holdout cadence**: If N is multiple of `corpus.holdout_cadence` (default 5) → no new hypothesis; instead run hold-out validation on current baseline, compare against last holdout run for overfit-detect, print `RESULT:HOLDOUT pass|fail`, exit.
3. **Retire-bias**: If N is multiple of `corpus.retire_bias.every_k_iter` (default 3) → filter backlog to `type: retire` first; if none, fall through.
4. **Stale-backlog breaker**: If the last 3 entries in `journal.md` are all `REJECTED` (any H-id), do not pick — emit `RESULT:NOOP backlog-stale-3-consecutive-rejects` and exit. Forces operator review of backlog rationale quality before continuing.
5. **Normal**: Top of backlog where `status == pending` AND `target` not in retired-components list AND not already in journal as rejected/dead.

If no candidate → `RESULT:NOOP empty-backlog`, exit.

Mark chosen hypothesis as `in_flight` in STATE.md + backlog.md BEFORE applying. This makes loop crash-resumable.

## Phase 3 — Apply hypothesis

1. Compute worktree path: `.claude/loop/worktrees/iter-$(printf '%04d' N)`
2. `git worktree add <path> HEAD`
3. `cd <path>`
4. **Protected check**: if hypothesis target matches `{CLAUDE.md, .claude/rules/*, .claude/loop/{run.sh,PROMPT.md,corpus.yml,fitness.sh}}`:
   - Generate unified diff: `<filename>.diff`
   - Write to `.claude/loop/proposals/iter-NNNN-<basename>.diff`
   - Append journal: `proposal-only iter-NNNN H-XXX <target>`
   - `git worktree remove --force <path>`
   - Update STATE: clear `in_flight_hypothesis`, increment `total_proposals`
   - `RESULT:PROPOSAL H-XXX <target>` → exit
5. Otherwise apply edit directly in worktree (use Edit/Write/MultiEdit normally).
6. Commit in worktree: `git -C <path> commit -am "loop: H-XXX <one-line>"` (no PR, no push).

## Phase 4 — Benchmark

1. **Tier 0**: `.claude/benchmark/static-checks.sh` from worktree. Exit != 0 → `RESULT:REJECT H-XXX tier0-fail` → cleanup + exit.
2. **Tier 1**: For each task in `corpus.tasks` where `split == train`:
   - For each fixture in `corpus.fixtures`:
     - `.claude/benchmark/headless-runner.sh --task <task.yml> --fixture <fixture> --inject-from <worktree>/.claude --report .claude/loop/reports/iter-NNNN-<task>-<fixture>.json`
   - Aggregate per-task metrics (mean across fixtures).
3. Compute deltas vs `STATE.baseline_snapshot[task]`. Variance guard: `|delta| <= 2σ` → treat as "no change" (noise, not signal).

## Phase 5 — Decide

`.claude/loop/fitness.sh --baseline-state .claude/loop/STATE.md --candidate-reports .claude/loop/reports/iter-NNNN-*.json --tier0 pass`

stdout `ACCEPT` (exit 0) OR `REJECT: <reason>` (exit 1).

### On ACCEPT:
1. `cd <harness-root>`
2. `git merge --ff-only .claude/loop/worktrees/iter-NNNN` (or if not fast-forwardable: rebase first)
3. Update STATE.md: `baseline_snapshot` ← candidate metrics; `last_accept_iteration` ← N; `total_accepted` += 1
4. Append journal: `YYYY-MM-DD iter-NNNN ACCEPTED H-XXX <one-line>`
5. Update backlog: status ← `accepted`
6. `git worktree remove --force .claude/loop/worktrees/iter-NNNN`
7. `RESULT:ACCEPT H-XXX` → exit

### On REJECT:
1. `git worktree remove --force .claude/loop/worktrees/iter-NNNN` (no merge)
2. Update STATE.md: clear `in_flight_hypothesis`, `total_rejected` += 1
3. Append journal: `YYYY-MM-DD iter-NNNN REJECTED H-XXX <reason>`
4. Update backlog: status ← `rejected`
5. `RESULT:REJECT H-XXX <reason>` → exit

### On ERROR (Tier 1 fixture failure, network, etc):
1. `git worktree remove --force <path>` if exists
2. Update STATE.md: clear `in_flight_hypothesis`
3. Append journal: `YYYY-MM-DD iter-NNNN ERROR <description>`
4. `RESULT:ERROR <description>` → exit (run.sh will treat as stall)

## Phase 6 — Cleanup

ALWAYS at end:
- STATE.md `iteration` ← N + 1
- STATE.md `in_flight_hypothesis` ← null
- Save backlog updates

## Invariants

| # | Invariant | Why |
|---|---|---|
| 1 | NEVER modify protected files directly | recursive failure (loop instructions self-destruct) |
| 2 | NEVER revive retired components | cross-check archive ADRs; respect prior decisions |
| 3 | NEVER skip Tier 0 | cheap blocker, no excuse |
| 4 | NEVER skip variance guard | sign-inversion lesson (devlog #25) |
| 5 | ALWAYS write `RESULT:*` marker | run.sh parses stdout to track stall |
| 6 | ALWAYS update STATE before exit | crash-resumability |
| 7 | NEVER spawn > 3 subagents per iteration | cost cap (per `corpus.subagent_cap`) |
| 8 | NEVER touch outside `.claude/` | scope boundary |

## Output contract

Last line of stdout MUST be one of:
- `RESULT:ACCEPT H-XXX`
- `RESULT:REJECT H-XXX <reason>`
- `RESULT:PROPOSAL H-XXX <protected-file>`
- `RESULT:HOLDOUT pass|fail`
- `RESULT:NOOP <reason>`
- `RESULT:ERROR <description>`

Anything else → run.sh treats as ERROR.

## Anti-patterns inside iteration

- Don't reason about what loop "should" do long-term — this iteration is one experiment.
- Don't try to fix backlog quality this iteration unless that IS the hypothesis.
- Don't pile multiple hypotheses into one iteration — one change, one test.
- Don't accept on "looks fine" — only on `fitness.sh` returning ACCEPT.
- Don't reject on minor noise — variance guard handles that.
