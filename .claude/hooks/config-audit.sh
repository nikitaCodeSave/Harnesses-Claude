#!/usr/bin/env bash
# ConfigChange hook for harness v0.1 — see docs/RESEARCH-PATCHES.md P0-4
# Append-only audit log for any config mutation. Observability only — never blocks.
set -euo pipefail

LOG_DIR="${CLAUDE_PROJECT_DIR:-.}/.claude/memory"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/config-audit.jsonl"

payload="$(cat || true)"
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

if command -v jq >/dev/null 2>&1; then
    # If payload is valid JSON keep it as a structured object; otherwise treat as raw string.
    if printf '%s' "$payload" | jq -e . >/dev/null 2>&1; then
        printf '%s' "$payload" \
            | jq -c --arg ts "$ts" '{ts:$ts, payload:.}' \
            >> "$LOG_FILE"
    else
        jq -cn --arg ts "$ts" --arg payload "$payload" '{ts:$ts, payload:$payload}' >> "$LOG_FILE"
    fi
else
    # Escape backslashes and double quotes for JSON literal.
    escaped="$(printf '%s' "$payload" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr -d '\n')"
    printf '{"ts":"%s","payload":"%s"}\n' "$ts" "$escaped" >> "$LOG_FILE"
fi

exit 0
