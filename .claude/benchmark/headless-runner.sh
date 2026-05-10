#!/usr/bin/env bash
# Headless benchmark runner — runs one task on fixture clone, captures metrics.
# OAuth-compatible (no --bare). Costs subscription tokens per invocation.
#
# Usage:
#   headless-runner.sh --task <yaml> --fixture <dir>
#                      [--report <path>] [--no-inject-harness]
#                      [--no-judge-pytest] [--timeout-sec 900]
#                      [--permission-mode acceptEdits|bypassPermissions|auto|...]
#
# Note: invocation из interactive Claude session под auto mode классификатор блокирует
# nested claude --print spawn без durable allow rule в .claude/settings.local.json:
#   {"permissions": {"allow": ["Bash(bash *headless-runner.sh:*)"]}}
# Manual invocation в standalone terminal — без classifier interference.
#
# Pipeline: clone fixture → optional harness inject → claude --print on clone
#           → parse JSON metrics → optional pytest judge → write report → cleanup.
#
# Safety: cwd=clone, no --add-dir outside clone. Permission mode configurable
#         (default acceptEdits); isolation rests on directory boundary.

set -uo pipefail

TASK_FILE=""; FIXTURE_PATH=""; REPORT_PATH=""
INJECT_HARNESS=1; JUDGE_PYTEST=1; TIMEOUT_SEC=900
PERMISSION_MODE="acceptEdits"  # safer default; pass --permission-mode to override
INJECT_FROM=""  # default empty = inject our own harness; set to alt dir for cross-harness bench

while [[ $# -gt 0 ]]; do
    case "$1" in
        --task)              TASK_FILE="$2"; shift 2 ;;
        --fixture)           FIXTURE_PATH="$2"; shift 2 ;;
        --report)            REPORT_PATH="$2"; shift 2 ;;
        --no-inject-harness) INJECT_HARNESS=0; shift ;;
        --inject-from)       INJECT_FROM="$2"; shift 2 ;;
        --no-judge-pytest)   JUDGE_PYTEST=0; shift ;;
        --timeout-sec)       TIMEOUT_SEC="$2"; shift 2 ;;
        --permission-mode)   PERMISSION_MODE="$2"; shift 2 ;;
        -h|--help)           sed -n '2,/^$/p' "$0"; exit 0 ;;
        *)                   echo "Unknown arg: $1" >&2; exit 2 ;;
    esac
done

[[ -z "$TASK_FILE"    || ! -f "$TASK_FILE"    ]] && { echo "FAIL: --task <yaml> required (found: '$TASK_FILE')" >&2; exit 2; }
[[ -z "$FIXTURE_PATH" || ! -d "$FIXTURE_PATH" ]] && { echo "FAIL: --fixture <dir> required (found: '$FIXTURE_PATH')" >&2; exit 2; }
command -v claude >/dev/null 2>&1 || { echo "FAIL: 'claude' CLI not found in PATH" >&2; exit 2; }
command -v jq     >/dev/null 2>&1 || { echo "FAIL: 'jq' required for metrics parsing" >&2; exit 2; }

TASK_ID=$(grep -E '^id:' "$TASK_FILE" | head -1 | sed -E 's/^id:[[:space:]]*//;s/^"//;s/"$//' || true)
PROMPT=$(grep -E '^prompt:' "$TASK_FILE" | head -1 | sed -E 's/^prompt:[[:space:]]*//;s/^"//;s/"$//' || true)
[[ -z "$TASK_ID" ]] && { echo "FAIL: task missing 'id' field" >&2; exit 2; }
[[ -z "$PROMPT"  ]] && { echo "FAIL: task missing single-line 'prompt' field" >&2; exit 2; }

HARNESS_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TS=$(date -u +%Y%m%dT%H%M%SZ)
FIXTURE_NAME=$(basename "$FIXTURE_PATH")
CLONE_DIR="/tmp/bench-${TASK_ID}-${FIXTURE_NAME}-${TS}"
REPORT_PATH="${REPORT_PATH:-$HARNESS_ROOT/.claude/benchmark/reports/${TASK_ID}-${FIXTURE_NAME}-${TS}.json}"
mkdir -p "$(dirname "$REPORT_PATH")"

cleanup() {
    if [[ -d "$CLONE_DIR" ]]; then
        rm -rf "$CLONE_DIR" 2>/dev/null || echo "WARN: failed to cleanup $CLONE_DIR" >&2
    fi
}
trap cleanup EXIT INT TERM

echo "[1/5] Clone fixture: $FIXTURE_PATH → $CLONE_DIR"
cp -r "$FIXTURE_PATH" "$CLONE_DIR" || { echo "FAIL: clone copy failed" >&2; exit 1; }

if [[ $INJECT_HARNESS -eq 1 ]]; then
    if [[ -n "$INJECT_FROM" ]]; then
        [[ ! -d "$INJECT_FROM" ]] && { echo "FAIL: --inject-from dir not found: $INJECT_FROM" >&2; exit 2; }
        echo "[2/5] Inject harness from $INJECT_FROM/ (alt harness)"
        SRC="$INJECT_FROM"
    else
        echo "[2/5] Inject harness from $HARNESS_ROOT/.claude/ (this repo)"
        SRC="$HARNESS_ROOT"
    fi
    [[ -d "$CLONE_DIR/.claude" ]] && rm -rf "$CLONE_DIR/.claude"
    [[ -d "$SRC/.claude" ]] && cp -r "$SRC/.claude" "$CLONE_DIR/.claude"
    [[ -f "$CLONE_DIR/.claude/settings.local.json" ]] && rm -f "$CLONE_DIR/.claude/settings.local.json"
    # If alt harness ships top-level CLAUDE.md / agents / skills / commands / hooks / rules — bring them in
    if [[ -n "$INJECT_FROM" ]]; then
        [[ -f "$SRC/CLAUDE.md" ]] && cp "$SRC/CLAUDE.md" "$CLONE_DIR/CLAUDE.md"
        for d in agents skills commands hooks rules contexts; do
            [[ -d "$SRC/$d" ]] && cp -r "$SRC/$d" "$CLONE_DIR/$d"
        done
    fi
else
    echo "[2/5] Harness inject skipped (using fixture's own .claude/ if present)"
fi

echo "[3/5] Run claude --print on clone (timeout ${TIMEOUT_SEC}s, --permission-mode ${PERMISSION_MODE}, no-session-persistence)..."
CLAUDE_OUTPUT_FILE="$CLONE_DIR/.bench-claude-output.json"
START_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ); START_EPOCH=$(date +%s)

CLAUDE_EXIT=0
if ! BENCH_PROMPT="$PROMPT" BENCH_PERM_MODE="$PERMISSION_MODE" \
     BENCH_CLONE_DIR="$CLONE_DIR" BENCH_OUT_FILE="$CLAUDE_OUTPUT_FILE" \
     timeout "$TIMEOUT_SEC" bash -c '
    cd "$BENCH_CLONE_DIR" || exit 99
    printf "%s" "$BENCH_PROMPT" | claude --print \
        --output-format json \
        --permission-mode "$BENCH_PERM_MODE" \
        --no-session-persistence \
        > "$BENCH_OUT_FILE" 2> "$BENCH_CLONE_DIR/.bench-claude-stderr.log"
'; then
    CLAUDE_EXIT=$?
fi

END_EPOCH=$(date +%s); END_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
WALL=$((END_EPOCH - START_EPOCH))

NUM_TURNS=0; COST=0; INPUT_TOKENS=0; OUTPUT_TOKENS=0; CACHE_CREATE=0; CACHE_READ=0
RESULT="<exit ${CLAUDE_EXIT}>"; STOP_REASON="<unknown>"
if [[ -s "$CLAUDE_OUTPUT_FILE" ]] && jq -e . "$CLAUDE_OUTPUT_FILE" >/dev/null 2>&1; then
    NUM_TURNS=$(jq -r '.num_turns // 0'                         "$CLAUDE_OUTPUT_FILE")
    COST=$(jq      -r '.total_cost_usd // 0'                    "$CLAUDE_OUTPUT_FILE")
    INPUT_TOKENS=$(jq -r '.usage.input_tokens // 0'              "$CLAUDE_OUTPUT_FILE")
    OUTPUT_TOKENS=$(jq -r '.usage.output_tokens // 0'            "$CLAUDE_OUTPUT_FILE")
    CACHE_CREATE=$(jq -r '.usage.cache_creation_input_tokens // 0' "$CLAUDE_OUTPUT_FILE")
    CACHE_READ=$(jq   -r '.usage.cache_read_input_tokens // 0'   "$CLAUDE_OUTPUT_FILE")
    RESULT=$(jq -r '.result // "<no result>"' "$CLAUDE_OUTPUT_FILE" | head -c 1000)
    STOP_REASON=$(jq -r '.stop_reason // "<unknown>"' "$CLAUDE_OUTPUT_FILE")
fi
STDERR_TAIL=""
[[ -s "$CLONE_DIR/.bench-claude-stderr.log" ]] && STDERR_TAIL=$(tail -c 500 "$CLONE_DIR/.bench-claude-stderr.log")

echo "[4/5] Verify side-effects..."
FILES_CHANGED=0; PYTEST_STATUS="skipped"; PYTEST_REASON="default"
if [[ -d "$CLONE_DIR/.git" ]]; then
    FILES_CHANGED=$(cd "$CLONE_DIR" && git status --porcelain 2>/dev/null | grep -v '^?? \.bench-' | wc -l || echo 0)
else
    # Fallback: count files modified/created after Claude actually started
    # (post-inject-and-cd timestamp), excluding bench artefacts, harness inject, pycache, CLAUDE.md
    FILES_CHANGED=$(find "$CLONE_DIR" -type f -newermt "@$START_EPOCH" \
        -not -name '.bench-claude-*' \
        -not -path '*/__pycache__/*' \
        -not -path '*/.claude/*' \
        -not -name 'CLAUDE.md' \
        -not -name 'AGENTS.md' \
        2>/dev/null | wc -l || echo 0)
fi
if [[ $JUDGE_PYTEST -eq 1 ]] && command -v pytest >/dev/null 2>&1; then
    # Scope pytest to fixture's own test files only; skip parasitic tests
    # injected by alt harnesses (e.g. ECC skills/*/test_*.py).
    PYTEST_TARGETS=()
    if [[ -d "$CLONE_DIR/tests" ]]; then
        PYTEST_TARGETS=("tests/")
    fi
    while IFS= read -r f; do
        [[ -n "$f" ]] && PYTEST_TARGETS+=("$(basename "$f")")
    done < <(find "$CLONE_DIR" -maxdepth 1 -type f \( -name 'test_*.py' -o -name '*_test.py' \) 2>/dev/null)
    if [[ ${#PYTEST_TARGETS[@]} -gt 0 ]]; then
        if (cd "$CLONE_DIR" && pytest --quiet --tb=no --no-header -p no:cacheprovider "${PYTEST_TARGETS[@]}" >/dev/null 2>&1); then
            PYTEST_STATUS="pass"; PYTEST_REASON="pytest_clean"
        else
            PYTEST_STATUS="fail"; PYTEST_REASON="pytest_failed"
        fi
    fi
fi

echo "[5/5] Write report → $REPORT_PATH"
jq -n \
    --arg task_id "$TASK_ID" \
    --arg fixture "$FIXTURE_NAME" \
    --argjson inject "$INJECT_HARNESS" \
    --arg ts_start "$START_TS" --arg ts_end "$END_TS" --argjson wall "$WALL" \
    --argjson exit_code "$CLAUDE_EXIT" \
    --arg stop_reason "$STOP_REASON" \
    --argjson num_turns "$NUM_TURNS" \
    --argjson cost "$COST" \
    --argjson input "$INPUT_TOKENS" --argjson output "$OUTPUT_TOKENS" \
    --argjson cache_create "$CACHE_CREATE" --argjson cache_read "$CACHE_READ" \
    --argjson files_changed "$FILES_CHANGED" \
    --arg pytest_status "$PYTEST_STATUS" --arg pytest_reason "$PYTEST_REASON" \
    --arg result "$RESULT" --arg stderr_tail "$STDERR_TAIL" \
    '{
        task: $task_id, fixture: $fixture, harness_injected: ($inject==1),
        timing: { start: $ts_start, end: $ts_end, wall_seconds: $wall },
        claude: {
            exit_code: $exit_code, stop_reason: $stop_reason, num_turns: $num_turns,
            cost_usd: $cost,
            tokens: { input: $input, output: $output, cache_creation: $cache_create, cache_read: $cache_read }
        },
        verification: { files_changed: $files_changed, pytest: { status: $pytest_status, reason: $pytest_reason } },
        result_excerpt: $result,
        stderr_tail: $stderr_tail
    }' > "$REPORT_PATH"

echo ""
echo "=== Bench summary ==="
echo "Task: $TASK_ID | Fixture: $FIXTURE_NAME | Harness injected: $INJECT_HARNESS"
echo "Claude: exit=$CLAUDE_EXIT, turns=$NUM_TURNS, stop=$STOP_REASON"
echo "Cost: \$$COST | Tokens: in=$INPUT_TOKENS, out=$OUTPUT_TOKENS, cache_create=$CACHE_CREATE, cache_read=$CACHE_READ"
echo "Wall: ${WALL}s | Files changed: $FILES_CHANGED | Pytest: $PYTEST_STATUS ($PYTEST_REASON)"
echo "Report: $REPORT_PATH"

if [[ $CLAUDE_EXIT -ne 0 ]]; then
    echo "WARN: claude exited non-zero — see stderr_tail in report"
    exit 0
fi
exit 0
