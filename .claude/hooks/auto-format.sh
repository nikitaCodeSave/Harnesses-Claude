#!/usr/bin/env bash
# PostToolUse hook (matcher: Edit|Write|MultiEdit) for harness v0.1.
# Observability: logs file changes; runs project formatter if configured.
# Adapts to stack via .claude/format.sh in the project root (if present).
# This hook never blocks (PostToolUse cannot block by design).
set -euo pipefail

LOG_DIR="${CLAUDE_PROJECT_DIR:-.}/.claude/memory"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/format-events.jsonl"

payload="$(cat || true)"
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

file_path=""
if command -v jq >/dev/null 2>&1; then
    file_path="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"
fi

[ -z "$file_path" ] && exit 0

formatter_script="${CLAUDE_PROJECT_DIR:-.}/.claude/format.sh"
formatter_status="not-configured"

if [ -x "$formatter_script" ]; then
    if "$formatter_script" "$file_path" >/dev/null 2>&1; then
        formatter_status="ok"
    else
        formatter_status="failed"
    fi
fi

if command -v jq >/dev/null 2>&1; then
    jq -cn --arg ts "$ts" --arg file "$file_path" --arg fmt "$formatter_status" \
        '{ts:$ts, file:$file, formatter:$fmt}' >> "$LOG_FILE"
else
    printf '{"ts":"%s","file":"%s","formatter":"%s"}\n' "$ts" "$file_path" "$formatter_status" >> "$LOG_FILE"
fi
exit 0
