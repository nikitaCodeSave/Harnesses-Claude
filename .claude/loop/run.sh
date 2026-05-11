#!/usr/bin/env bash
# FROZEN — self-improvement loop driver. NOT modified by loop's own iterations
# (protected by loop-protected-guard.sh + listed in corpus.yml.protected_files).
# Manual updates only (human-reviewed via .claude/loop/proposals/).
#
# Usage:
#   LOOP_MAX_ITER=10 ./.claude/loop/run.sh           # smoke (10 iter cap)
#   ./.claude/loop/run.sh                             # autonomous (env defaults)
#
# Env:
#   LOOP_MAX_ITER          (default: 9999)         hard iteration cap
#   LOOP_WALL_CLOCK_SEC    (default: 172800 = 48h) pause when exceeded
#   LOOP_BUDGET_USD        (default: 20.00)        cumulative cost pause threshold
#                                                  set this to 70% of your weekly limit USD
#   LOOP_STALL_CAP         (default: 10)           consecutive no-improvement pause
#   LOOP_PERMISSION_MODE   (default: acceptEdits)  claude --permission-mode flag
#   LOOP_ITER_TIMEOUT_SEC  (default: 1800 = 30min) per-iteration claude --print timeout
#
# Stop signals (any one pauses loop):
#   - PAUSED.md exists at iter start (manual gate)
#   - Wall-clock cap exceeded
#   - Cumulative cost exceeds LOOP_BUDGET_USD
#   - Stall count >= LOOP_STALL_CAP
#   - LOOP_MAX_ITER reached
#
# Each iteration:
#   1. Pre-check gates
#   2. Spawn `claude --print < PROMPT.md` (one Opus session per iter)
#   3. Parse RESULT:* marker from stdout
#   4. Update counters
#   5. notify-send on terminal events

set -uo pipefail

LOOP_DIR="$(cd "$(dirname "$0")" && pwd)"
HARNESS_ROOT="$(cd "$LOOP_DIR/../.." && pwd)"
cd "$HARNESS_ROOT" || { echo "FAIL: harness root not found"; exit 2; }

# ---------- Config ----------
MAX_ITER=${LOOP_MAX_ITER:-9999}
WALL_CLOCK_SEC=${LOOP_WALL_CLOCK_SEC:-172800}
BUDGET_USD=${LOOP_BUDGET_USD:-20.00}
STALL_CAP=${LOOP_STALL_CAP:-10}
PERMISSION_MODE=${LOOP_PERMISSION_MODE:-acceptEdits}
ITER_TIMEOUT=${LOOP_ITER_TIMEOUT_SEC:-1800}

# ---------- Setup ----------
mkdir -p "$LOOP_DIR/logs" "$LOOP_DIR/worktrees" "$LOOP_DIR/reports" "$LOOP_DIR/proposals"

START_EPOCH=$(date +%s)
START_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
CUMULATIVE_USD="0.00"
STALL_COUNT=0
ITER_COUNT=0

# ---------- Helpers ----------

notify() {
    local title="$1" msg="$2"
    local stamp; stamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    echo "[$stamp] $title — $msg" | tee -a "$LOOP_DIR/logs/run.log"
    command -v notify-send >/dev/null 2>&1 && \
        notify-send -u normal "Claude Loop: $title" "$msg" 2>/dev/null || true
}

write_paused() {
    local reason="$1"
    {
        echo "# Loop paused — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo ""
        echo "**Reason**: $reason"
        echo "**Iteration**: $ITER_COUNT"
        echo "**Elapsed**: $(( $(date +%s) - START_EPOCH ))s"
        echo "**Cumulative cost**: \$${CUMULATIVE_USD}"
        echo ""
        echo "To resume: rm \`.claude/loop/PAUSED.md\` then re-run \`./.claude/loop/run.sh\`."
    } > "$LOOP_DIR/PAUSED.md"
    notify "Pause" "$reason (iter $ITER_COUNT, \$${CUMULATIVE_USD})"
}

# Cost accumulator: parses claude --output-format json's total_cost_usd field
# (one per claude --print invocation). Adds to CUMULATIVE_USD.
accumulate_cost() {
    local json_file="$1"
    [[ ! -f "$json_file" ]] && return 0
    if command -v jq >/dev/null 2>&1; then
        local delta
        delta=$(jq -r '.total_cost_usd // 0' "$json_file" 2>/dev/null || echo "0")
        CUMULATIVE_USD=$(awk -v a="$CUMULATIVE_USD" -v b="$delta" 'BEGIN { printf "%.4f", a+b }')
    fi
}

cost_over_budget() {
    awk -v c="$CUMULATIVE_USD" -v b="$BUDGET_USD" 'BEGIN { exit !(c+0 >= b+0) }'
}

# ---------- Pre-flight ----------

if [[ -f "$LOOP_DIR/PAUSED.md" ]]; then
    echo "PAUSED.md exists. Delete it to resume. Refusing to start."
    exit 1
fi

if [[ ! -f "$LOOP_DIR/PROMPT.md" ]]; then
    echo "FAIL: $LOOP_DIR/PROMPT.md missing — cannot proceed without idempotent prompt"
    exit 2
fi

if [[ ! -f "$LOOP_DIR/STATE.md" ]]; then
    echo "FAIL: $LOOP_DIR/STATE.md missing"
    exit 2
fi

if [[ ! -f "$LOOP_DIR/corpus.yml" ]]; then
    echo "FAIL: $LOOP_DIR/corpus.yml missing"
    exit 2
fi

command -v claude >/dev/null 2>&1 || { echo "FAIL: claude CLI not in PATH"; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "FAIL: jq required"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "FAIL: git required"; exit 2; }

# Sanity: STATE.md has baseline_snapshot (loop refuses to run without)
if grep -q '^baseline_snapshot: null' "$LOOP_DIR/STATE.md"; then
    echo "FAIL: STATE.md.baseline_snapshot is null — run variance baseline first (task #38)"
    exit 2
fi

echo "===== Loop starting $START_TS ====="
echo "  max_iter=$MAX_ITER wall_clock=${WALL_CLOCK_SEC}s budget=\$${BUDGET_USD} stall_cap=$STALL_CAP"
echo "  permission_mode=$PERMISSION_MODE iter_timeout=${ITER_TIMEOUT}s"
echo ""

# ---------- Main loop ----------

export LOOP_MODE=1

while (( ITER_COUNT < MAX_ITER )); do
    NOW=$(date +%s)
    ELAPSED=$(( NOW - START_EPOCH ))

    # Gate 1: manual pause
    if [[ -f "$LOOP_DIR/PAUSED.md" ]]; then
        echo "PAUSED.md detected mid-loop. Stopping."
        exit 0
    fi

    # Gate 2: wall-clock
    if (( ELAPSED >= WALL_CLOCK_SEC )); then
        write_paused "wall-clock cap reached (${ELAPSED}s >= ${WALL_CLOCK_SEC}s)"
        exit 0
    fi

    # Gate 3: cumulative cost
    if cost_over_budget; then
        write_paused "cumulative cost \$${CUMULATIVE_USD} >= budget \$${BUDGET_USD}"
        exit 0
    fi

    # Gate 4: stall
    if (( STALL_COUNT >= STALL_CAP )); then
        write_paused "stall count $STALL_COUNT >= cap $STALL_CAP (no improvement)"
        exit 0
    fi

    ITER_COUNT=$(( ITER_COUNT + 1 ))
    ITER_TAG=$(printf 'iter-%04d' "$ITER_COUNT")
    ITER_LOG="$LOOP_DIR/logs/${ITER_TAG}.log"
    ITER_JSON="$LOOP_DIR/logs/${ITER_TAG}.json"

    echo ""
    echo "----- $ITER_TAG (elapsed ${ELAPSED}s, \$${CUMULATIVE_USD}, stall $STALL_COUNT) -----"

    # Invoke claude --print with PROMPT.md as input
    # Output: text → ITER_LOG (for human inspection); JSON metadata → ITER_JSON (cost)
    # Using --output-format json gives total_cost_usd field
    set +e
    timeout "$ITER_TIMEOUT" claude --print \
        --add-dir "$HARNESS_ROOT" \
        --permission-mode "$PERMISSION_MODE" \
        --output-format json \
        < "$LOOP_DIR/PROMPT.md" > "$ITER_JSON" 2>"$ITER_LOG.stderr"
    CLAUDE_EXIT=$?
    set -e

    if [[ $CLAUDE_EXIT -ne 0 ]]; then
        echo "  claude --print exit=$CLAUDE_EXIT (timeout or error)" | tee -a "$ITER_LOG"
        STALL_COUNT=$(( STALL_COUNT + 1 ))
        notify "Iter error" "$ITER_TAG claude exit=$CLAUDE_EXIT, see logs/${ITER_TAG}.log.stderr"
        continue
    fi

    # Extract text from JSON output, save to log
    if jq -er '.result // .content // empty' "$ITER_JSON" > "$ITER_LOG" 2>/dev/null; then
        : # ok
    else
        cp "$ITER_JSON" "$ITER_LOG"  # fallback
    fi

    # Accumulate cost
    accumulate_cost "$ITER_JSON"

    # Parse RESULT marker (last RESULT:* line)
    RESULT_LINE=$(grep -E '^RESULT:[A-Z]+' "$ITER_LOG" | tail -1 || true)
    if [[ -z "$RESULT_LINE" ]]; then
        echo "  no RESULT:* marker — treating as ERROR"
        STALL_COUNT=$(( STALL_COUNT + 1 ))
        continue
    fi

    echo "  $RESULT_LINE"

    case "$RESULT_LINE" in
        RESULT:ACCEPT*)    STALL_COUNT=0 ;;
        RESULT:REJECT*)    STALL_COUNT=$(( STALL_COUNT + 1 )) ;;
        RESULT:PROPOSAL*)  STALL_COUNT=$(( STALL_COUNT + 1 )) ;;  # proposal не считается улучшением
        RESULT:HOLDOUT*)   ;; # holdout не меняет stall
        RESULT:NOOP*)      write_paused "backlog exhausted (NOOP)"; exit 0 ;;
        RESULT:ERROR*)     STALL_COUNT=$(( STALL_COUNT + 1 )) ;;
    esac
done

write_paused "max_iter $MAX_ITER reached"
notify "Loop complete" "Ran $ITER_COUNT iterations, \$${CUMULATIVE_USD} spent"
