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
# Pipeline: clone fixture → optional harness inject → claude --print stream-json on clone
#           → parse result event + Layer C trajectory metrics → optional pytest judge
#           → write report → cleanup.
#
# Layer C trajectory (skills_triggered / subagent_dispatches / invariant_pings /
# workflow_markers / tool_calls_summary) — derived from stream-json tool_use blocks
# and assistant text. See .claude/docs/benchmark.md.
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

command -v claude >/dev/null 2>&1 || { echo "FAIL: 'claude' CLI not found in PATH" >&2; exit 2; }
command -v jq     >/dev/null 2>&1 || { echo "FAIL: 'jq' required for metrics parsing" >&2; exit 2; }

# HARNESS_ROOT: prefer $CLAUDE_PROJECT_DIR (set by Claude Code session) — это main harness root
# даже когда script invoked из worktree. Fallback to script location for standalone use
# (cross-harness benchmarks per devlog #24/25, manual invocations).
HARNESS_ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"

# Path resolution: try as-is first; if missing, fall back to $HARNESS_ROOT/<path>.
# This makes the runner cwd-agnostic — callers (loop iter from worktree, manual
# benchmark from any pwd) get consistent path resolution. Absolute paths pass
# through unchanged. Smoke iter-0001 lesson: relative path from worktree pwd
# missed external/ fixtures (gitignored, not in worktree checkout).
resolve_path() {
    local p="$1" kind="$2"  # kind: file|dir
    [[ -z "$p" ]] && { echo ""; return; }
    case "$kind" in
        file)
            [[ -f "$p" ]]                && { echo "$p"; return; }
            [[ -f "$HARNESS_ROOT/$p" ]]  && { echo "$HARNESS_ROOT/$p"; return; }
            ;;
        dir)
            [[ -d "$p" ]]                && { echo "$p"; return; }
            [[ -d "$HARNESS_ROOT/$p" ]]  && { echo "$HARNESS_ROOT/$p"; return; }
            ;;
    esac
    echo "$p"  # let validation below produce clear error
}

TASK_FILE="$(resolve_path "$TASK_FILE" file)"
FIXTURE_PATH="$(resolve_path "$FIXTURE_PATH" dir)"
[[ -n "$INJECT_FROM" ]] && INJECT_FROM="$(resolve_path "$INJECT_FROM" dir)"

[[ -z "$TASK_FILE"    || ! -f "$TASK_FILE"    ]] && { echo "FAIL: --task <yaml> required (found: '$TASK_FILE'; tried as-is + \$HARNESS_ROOT prefix)" >&2; exit 2; }
[[ -z "$FIXTURE_PATH" || ! -d "$FIXTURE_PATH" ]] && { echo "FAIL: --fixture <dir> required (found: '$FIXTURE_PATH'; tried as-is + \$HARNESS_ROOT prefix)" >&2; exit 2; }

TASK_ID=$(grep -E '^id:' "$TASK_FILE" | head -1 | sed -E 's/^id:[[:space:]]*//;s/^"//;s/"$//' || true)
PROMPT=$(grep -E '^prompt:' "$TASK_FILE" | head -1 | sed -E 's/^prompt:[[:space:]]*//;s/^"//;s/"$//' || true)
[[ -z "$TASK_ID" ]] && { echo "FAIL: task missing 'id' field" >&2; exit 2; }
[[ -z "$PROMPT"  ]] && { echo "FAIL: task missing single-line 'prompt' field" >&2; exit 2; }
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
    # Prune injected artifacts that don't belong in a benchmark target session:
    # external fixtures (6MB+ of unrelated repos), accumulated reports, self-improvement
    # loop state, user-specific memory, ephemeral plans/worktrees/caches.
    # Keeps inject lean and avoids polluting context with bench-internal noise.
    if [[ -d "$CLONE_DIR/.claude" ]]; then
        rm -rf "$CLONE_DIR/.claude/benchmark/fixtures/external" 2>/dev/null
        rm -rf "$CLONE_DIR/.claude/benchmark/reports"           2>/dev/null
        rm -rf "$CLONE_DIR/.claude/loop"                        2>/dev/null
        rm -rf "$CLONE_DIR/.claude/memory"                      2>/dev/null
        rm -rf "$CLONE_DIR/.claude/plans"                       2>/dev/null
        rm -rf "$CLONE_DIR/.claude/worktrees"                   2>/dev/null
        rm -rf "$CLONE_DIR/.claude/.cache"                      2>/dev/null
    fi
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

# Auto-init git in clone if fixture wasn't a git repo. Makes files_changed
# accurate via git status (which is the primary path); fallback find heuristic
# loses precision (counts cp -r'd files via mtime races, per devlog #24).
if [[ ! -d "$CLONE_DIR/.git" ]]; then
    (cd "$CLONE_DIR" && \
        git init -q && \
        git add -A 2>/dev/null && \
        git -c user.email=bench@local.invalid -c user.name=bench-runner \
            commit -q -m "bench baseline" 2>/dev/null) || \
        echo "WARN: failed to auto-init git in clone; files_changed will use mtime fallback" >&2
fi

echo "[3/5] Run claude --print on clone (timeout ${TIMEOUT_SEC}s, --permission-mode ${PERMISSION_MODE}, no-session-persistence)..."
# Stream-json output captures full trajectory: tool_use blocks, assistant text, hook events.
# Result event (last line) carries same metrics as the simple json format. Layer C parsing
# downstream extracts skills_triggered / subagent_dispatches / invariant_pings / workflow_markers.
CLAUDE_OUTPUT_FILE="$CLONE_DIR/.bench-claude-stream.jsonl"
START_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ); START_EPOCH=$(date +%s)

CLAUDE_EXIT=0
if ! BENCH_PROMPT="$PROMPT" BENCH_PERM_MODE="$PERMISSION_MODE" \
     BENCH_CLONE_DIR="$CLONE_DIR" BENCH_OUT_FILE="$CLAUDE_OUTPUT_FILE" \
     timeout "$TIMEOUT_SEC" bash -c '
    cd "$BENCH_CLONE_DIR" || exit 99
    printf "%s" "$BENCH_PROMPT" | claude --print \
        --output-format stream-json \
        --include-hook-events \
        --verbose \
        --permission-mode "$BENCH_PERM_MODE" \
        --no-session-persistence \
        > "$BENCH_OUT_FILE" 2> "$BENCH_CLONE_DIR/.bench-claude-stderr.log"
'; then
    CLAUDE_EXIT=$?
fi

END_EPOCH=$(date +%s); END_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
WALL=$((END_EPOCH - START_EPOCH))

# Parse result event (last `{"type":"result",...}` line in stream).
NUM_TURNS=0; COST=0; INPUT_TOKENS=0; OUTPUT_TOKENS=0; CACHE_CREATE=0; CACHE_READ=0
RESULT="<exit ${CLAUDE_EXIT}>"; STOP_REASON="<unknown>"
if [[ -s "$CLAUDE_OUTPUT_FILE" ]]; then
    RESULT_EVENT=$(jq -c 'select(.type=="result")' "$CLAUDE_OUTPUT_FILE" 2>/dev/null | tail -1)
    if [[ -n "$RESULT_EVENT" ]]; then
        NUM_TURNS=$(echo      "$RESULT_EVENT" | jq -r '.num_turns // 0')
        COST=$(echo           "$RESULT_EVENT" | jq -r '.total_cost_usd // 0')
        INPUT_TOKENS=$(echo   "$RESULT_EVENT" | jq -r '.usage.input_tokens // 0')
        OUTPUT_TOKENS=$(echo  "$RESULT_EVENT" | jq -r '.usage.output_tokens // 0')
        CACHE_CREATE=$(echo   "$RESULT_EVENT" | jq -r '.usage.cache_creation_input_tokens // 0')
        CACHE_READ=$(echo     "$RESULT_EVENT" | jq -r '.usage.cache_read_input_tokens // 0')
        RESULT=$(echo         "$RESULT_EVENT" | jq -r '.result // "<no result>"' | head -c 1000)
        STOP_REASON=$(echo    "$RESULT_EVENT" | jq -r '.stop_reason // "<unknown>"')
    fi
fi
STDERR_TAIL=""
[[ -s "$CLONE_DIR/.bench-claude-stderr.log" ]] && STDERR_TAIL=$(tail -c 500 "$CLONE_DIR/.bench-claude-stderr.log")

# Layer C: trajectory metrics.
# - skills_triggered: tool_use blocks with name=="Skill" (skill names from .input.skill)
# - subagent_dispatches: tool_use with name=="Agent" or "Task" (count + subagent_type)
# - tool_calls_summary: all tool_use grouped by name
# - invariant_pings: forbidden patterns in tool inputs + assistant text (api-constraint violations)
# - workflow_markers: Plan/Review section headers in assistant text (Plan→Work→Review evidence)
TRAJECTORY="{}"
if [[ -s "$CLAUDE_OUTPUT_FILE" ]]; then
    TOOL_USES=$(jq -c 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use")' "$CLAUDE_OUTPUT_FILE" 2>/dev/null)
    SKILLS_TRIGGERED=$(echo "$TOOL_USES" | jq -s '[.[] | select(.name=="Skill") | (.input.skill // .input.name // "unknown")] | unique' 2>/dev/null || echo '[]')
    SUBAGENT_COUNT=$(echo "$TOOL_USES" | jq -s '[.[] | select(.name=="Agent" or .name=="Task")] | length' 2>/dev/null || echo 0)
    SUBAGENT_TYPES=$(echo "$TOOL_USES" | jq -s '[.[] | select(.name=="Agent" or .name=="Task") | (.input.subagent_type // .input.type // "default")] | unique' 2>/dev/null || echo '[]')
    TOOL_SUMMARY=$(echo "$TOOL_USES" | jq -s 'group_by(.name) | map({name: .[0].name, count: length}) | sort_by(-.count)' 2>/dev/null || echo '[]')
    # Assistant text for workflow markers + invariant pings text scan
    ASSISTANT_TEXT=$(jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text' "$CLAUDE_OUTPUT_FILE" 2>/dev/null | tr '\n' ' ' || echo "")
    PLAN_EMITTED=0;  REVIEW_EMITTED=0
    echo "$ASSISTANT_TEXT" | grep -qiE '(##|###)\s*(plan|план|approach|strategy)|enter[[:space:]]+plan[[:space:]]+mode' && PLAN_EMITTED=1
    echo "$ASSISTANT_TEXT" | grep -qiE '(##|###)\s*(verification|review|validation|tests?[[:space:]]+pass(ed)?)|pytest[[:space:]]+passe[ds]|all[[:space:]]+tests?[[:space:]]+pass' && REVIEW_EMITTED=1
    # Invariant pings: scan whole stream text (catches forbidden patterns in tool inputs + assistant suggestions)
    INV_PATTERNS='ANTHROPIC_API_KEY|--bare\b|--max-budget-usd|managed-agents-|--betas[[:space:]]+managed-agents|--no-verify'
    declare -a PING_LIST=()
    while IFS=':' read -r count pat; do
        [[ -n "$pat" ]] && PING_LIST+=("{\"pattern\":\"$(echo "$pat" | sed 's/[][\\\/]/\\&/g; s/\"/\\\"/g')\",\"count\":$count}")
    done < <(grep -ohE "$INV_PATTERNS" "$CLAUDE_OUTPUT_FILE" 2>/dev/null | sort | uniq -c | sed 's/^[[:space:]]*//' | awk '{printf "%s:%s\n", $1, $2}')
    INVARIANT_PINGS="[]"
    if [[ ${#PING_LIST[@]} -gt 0 ]]; then
        INVARIANT_PINGS="[$(IFS=,; echo "${PING_LIST[*]}")]"
    fi
    TRAJECTORY=$(jq -n \
        --argjson skills "$SKILLS_TRIGGERED" \
        --argjson subagent_count "$SUBAGENT_COUNT" \
        --argjson subagent_types "$SUBAGENT_TYPES" \
        --argjson tool_summary "$TOOL_SUMMARY" \
        --argjson pings "$INVARIANT_PINGS" \
        --argjson plan "$PLAN_EMITTED" \
        --argjson review "$REVIEW_EMITTED" \
        '{
            skills_triggered: $skills,
            subagent_dispatches: { count: $subagent_count, types: $subagent_types },
            tool_calls_summary: $tool_summary,
            invariant_pings: $pings,
            workflow_markers: { plan_emitted: ($plan==1), review_emitted: ($review==1) }
        }' 2>/dev/null || echo '{}')
fi

echo "[4/5] Verify side-effects..."
FILES_CHANGED=0; PYTEST_STATUS="skipped"; PYTEST_REASON="default"
# Temporarily disable pipefail for the file count: grep returns non-zero on no-match,
# which under pipefail makes the whole pipeline fail, triggering `|| echo 0` AFTER wc -l
# already produced "0" — resulting in "0\n0" → invalid JSON for argjson downstream.
set +o pipefail
if [[ -d "$CLONE_DIR/.git" ]]; then
    # Exclude bench artefacts + python build cache + untracked .claude/ side-effects
    # (Claude auto-memory subsystem re-creates .claude/memory/ during runtime even after
    # inject-time prune; those are runtime scaffolding, not task output).
    FILES_CHANGED=$(cd "$CLONE_DIR" && git status --porcelain 2>/dev/null \
        | grep -vE '^\?\? (\.bench-|__pycache__|\.pytest_cache|\.mypy_cache|\.ruff_cache|\.claude/)' \
        | grep -vE '\.pyc$' \
        | wc -l)
else
    # Fallback: count files modified/created after Claude actually started
    # (post-inject-and-cd timestamp), excluding bench artefacts, harness inject, pycache, CLAUDE.md
    FILES_CHANGED=$(find "$CLONE_DIR" -type f -newermt "@$START_EPOCH" \
        -not -name '.bench-claude-*' \
        -not -path '*/__pycache__/*' \
        -not -path '*/.pytest_cache/*' \
        -not -path '*/.mypy_cache/*' \
        -not -path '*/.ruff_cache/*' \
        -not -path '*/.claude/*' \
        -not -name 'CLAUDE.md' \
        -not -name 'AGENTS.md' \
        -not -name '*.pyc' \
        2>/dev/null | wc -l)
fi
set -o pipefail
# Normalize: strip any whitespace, default 0 if empty
FILES_CHANGED="${FILES_CHANGED//[!0-9]/}"
[[ -z "$FILES_CHANGED" ]] && FILES_CHANGED=0
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
    --argjson trajectory "$TRAJECTORY" \
    '{
        task: $task_id, fixture: $fixture, harness_injected: ($inject==1),
        timing: { start: $ts_start, end: $ts_end, wall_seconds: $wall },
        claude: {
            exit_code: $exit_code, stop_reason: $stop_reason, num_turns: $num_turns,
            cost_usd: $cost,
            tokens: { input: $input, output: $output, cache_creation: $cache_create, cache_read: $cache_read }
        },
        verification: { files_changed: $files_changed, pytest: { status: $pytest_status, reason: $pytest_reason } },
        trajectory: $trajectory,
        result_excerpt: $result,
        stderr_tail: $stderr_tail
    }' > "$REPORT_PATH"

echo ""
echo "=== Bench summary ==="
echo "Task: $TASK_ID | Fixture: $FIXTURE_NAME | Harness injected: $INJECT_HARNESS"
echo "Claude: exit=$CLAUDE_EXIT, turns=$NUM_TURNS, stop=$STOP_REASON"
echo "Cost: \$$COST | Tokens: in=$INPUT_TOKENS, out=$OUTPUT_TOKENS, cache_create=$CACHE_CREATE, cache_read=$CACHE_READ"
echo "Wall: ${WALL}s | Files changed: $FILES_CHANGED | Pytest: $PYTEST_STATUS ($PYTEST_REASON)"
# Layer C trajectory summary
TRAJ_SKILLS=$(echo "$TRAJECTORY" | jq -r '.skills_triggered // [] | join(",") | if .=="" then "none" else . end' 2>/dev/null || echo "n/a")
TRAJ_SUBA=$(echo "$TRAJECTORY" | jq -r '.subagent_dispatches.count // 0' 2>/dev/null || echo 0)
TRAJ_PINGS=$(echo "$TRAJECTORY" | jq -r '.invariant_pings // [] | length' 2>/dev/null || echo 0)
TRAJ_PLAN=$(echo "$TRAJECTORY" | jq -r '.workflow_markers.plan_emitted // false' 2>/dev/null || echo false)
TRAJ_REVIEW=$(echo "$TRAJECTORY" | jq -r '.workflow_markers.review_emitted // false' 2>/dev/null || echo false)
echo "Trajectory: skills=[$TRAJ_SKILLS] | subagents=$TRAJ_SUBA | invariant_pings=$TRAJ_PINGS | plan=$TRAJ_PLAN | review=$TRAJ_REVIEW"
echo "Report: $REPORT_PATH"

if [[ $CLAUDE_EXIT -ne 0 ]]; then
    echo "WARN: claude exited non-zero — see stderr_tail in report"
    exit 0
fi
exit 0
