#!/usr/bin/env bash
# StopFailure hook for harness v0.1 — see docs/RESEARCH-PATCHES.md P0-4
# Captures stop-failure reason and writes a recovery hint. Never blocks.
set -euo pipefail

LOG_DIR="${CLAUDE_PROJECT_DIR:-.}/.claude/memory"
mkdir -p "$LOG_DIR"
FALLBACK_LOG="$LOG_DIR/recovery-hints.jsonl"

REPO_ROOT="${CLAUDE_PROJECT_DIR:-.}"
MEMORY_MD="$REPO_ROOT/MEMORY.md"

payload="$(cat || true)"
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

reason=""
if command -v jq >/dev/null 2>&1; then
    reason="$(printf '%s' "$payload" | jq -r '.reason // .error // .message // empty' 2>/dev/null || true)"
fi
if [ -z "$reason" ]; then
    reason="$(printf '%s' "$payload" | grep -oE '"(reason|error|message)"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n1 | sed -E 's/.*:[[:space:]]*"(.*)"$/\1/' || true)"
fi
if [ -z "$reason" ]; then
    reason="(no reason field in payload)"
fi

if [ -f "$MEMORY_MD" ]; then
    {
        printf '\n\n## Recovery hint %s\n%s\n' "$ts" "$reason"
    } >> "$MEMORY_MD"
else
    if command -v jq >/dev/null 2>&1; then
        jq -cn --arg ts "$ts" --arg reason "$reason" '{ts:$ts, reason:$reason}' >> "$FALLBACK_LOG"
    else
        esc_reason="$(printf '%s' "$reason" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
        printf '{"ts":"%s","reason":"%s"}\n' "$ts" "$esc_reason" >> "$FALLBACK_LOG"
    fi
fi

exit 0
