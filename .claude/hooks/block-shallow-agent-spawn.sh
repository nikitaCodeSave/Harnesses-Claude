#!/usr/bin/env bash
# PreToolUse hook (matcher: Agent) for harness v0.1.
# Blocks subagent invocations whose `prompt` is shallow (<MIN_LEN chars).
# Rationale: enforce harness CLAUDE.md guidance — spawn agents thoughtfully
# with substantive briefings, not terse one-liners.
set -euo pipefail

LOG_DIR="${CLAUDE_PROJECT_DIR:-.}/.claude/memory"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/agent-spawn.jsonl"

payload="$(cat || true)"
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

MIN_LEN=100

prompt=""
subagent_type=""
if command -v jq >/dev/null 2>&1; then
    prompt="$(printf '%s' "$payload" | jq -r '.tool_input.prompt // empty' 2>/dev/null || true)"
    subagent_type="$(printf '%s' "$payload" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null || true)"
fi

prompt_len=${#prompt}

json_log() {
    local decision="$1"
    local reason="${2:-}"
    if command -v jq >/dev/null 2>&1; then
        jq -cn \
            --arg ts "$ts" \
            --arg decision "$decision" \
            --argjson prompt_len "$prompt_len" \
            --arg subagent_type "$subagent_type" \
            --arg reason "$reason" \
            '{ts:$ts, decision:$decision, prompt_len:$prompt_len, subagent_type:$subagent_type} + (if $reason == "" then {} else {reason:$reason} end)' \
            >> "$LOG_FILE"
    else
        printf '{"ts":"%s","decision":"%s","prompt_len":%d,"subagent_type":"%s"}\n' \
            "$ts" "$decision" "$prompt_len" "$subagent_type" >> "$LOG_FILE"
    fi
}

if [ "$prompt_len" -lt "$MIN_LEN" ]; then
    json_log "blocked" "prompt shorter than ${MIN_LEN} chars"
    echo "Agent spawn blocked: prompt must be >=${MIN_LEN} chars (got ${prompt_len}). Brief the subagent like a colleague who just walked in — explain goal, context, and constraints." >&2
    exit 2
fi

json_log "allowed"
exit 0
