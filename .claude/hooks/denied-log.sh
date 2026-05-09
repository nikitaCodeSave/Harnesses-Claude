#!/usr/bin/env bash
# PermissionDenied hook for harness v0.1 — see docs/RESEARCH-PATCHES.md P0-4
# Records every permission denial. Observability only — never blocks.
set -euo pipefail

LOG_DIR="${CLAUDE_PROJECT_DIR:-.}/.claude/memory"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/denied.jsonl"

payload="$(cat || true)"
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

MAX_ARGS_LEN=120

tool=""
reason=""
args_summary=""
if command -v jq >/dev/null 2>&1; then
    tool="$(printf '%s' "$payload" | jq -r '.tool // .tool_name // empty' 2>/dev/null || true)"
    reason="$(printf '%s' "$payload" | jq -r '.reason // .message // .error // empty' 2>/dev/null || true)"
    # Compact representation of tool input/args for the summary field.
    args_raw="$(printf '%s' "$payload" | jq -c '.args // .tool_input // .input // empty' 2>/dev/null || true)"
    if [ -n "$args_raw" ] && [ "$args_raw" != "null" ]; then
        args_summary="$args_raw"
    fi
fi
if [ -z "$tool" ]; then
    tool="$(printf '%s' "$payload" | grep -oE '"(tool|tool_name)"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n1 | sed -E 's/.*:[[:space:]]*"(.*)"$/\1/' || true)"
fi
if [ -z "$reason" ]; then
    reason="$(printf '%s' "$payload" | grep -oE '"(reason|message|error)"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n1 | sed -E 's/.*:[[:space:]]*"(.*)"$/\1/' || true)"
fi

# Truncate args summary to MAX_ARGS_LEN characters.
if [ ${#args_summary} -gt $MAX_ARGS_LEN ]; then
    args_summary="${args_summary:0:$MAX_ARGS_LEN}"
fi

if command -v jq >/dev/null 2>&1; then
    jq -cn \
        --arg ts "$ts" \
        --arg tool "$tool" \
        --arg args_summary "$args_summary" \
        --arg reason "$reason" \
        '{ts:$ts, tool:$tool, args_summary:$args_summary} + (if $reason == "" then {} else {reason:$reason} end)' \
        >> "$LOG_FILE"
else
    esc_args="$(printf '%s' "$args_summary" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
    esc_reason="$(printf '%s' "$reason" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
    if [ -n "$reason" ]; then
        printf '{"ts":"%s","tool":"%s","args_summary":"%s","reason":"%s"}\n' \
            "$ts" "$tool" "$esc_args" "$esc_reason" >> "$LOG_FILE"
    else
        printf '{"ts":"%s","tool":"%s","args_summary":"%s"}\n' \
            "$ts" "$tool" "$esc_args" >> "$LOG_FILE"
    fi
fi

exit 0
