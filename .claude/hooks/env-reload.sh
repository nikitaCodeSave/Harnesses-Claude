#!/usr/bin/env bash
# CwdChanged hook for harness v0.1 — see docs/RESEARCH-PATCHES.md P0-4
# Detects .envrc presence after a cwd change (direnv hint only — does NOT auto-source).
set -euo pipefail

LOG_DIR="${CLAUDE_PROJECT_DIR:-.}/.claude/memory"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/cwd-changes.jsonl"

payload="$(cat || true)"
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

old_cwd=""
new_cwd=""
if command -v jq >/dev/null 2>&1; then
    new_cwd="$(printf '%s' "$payload" | jq -r '.new_cwd // .cwd // .path // empty' 2>/dev/null || true)"
    old_cwd="$(printf '%s' "$payload" | jq -r '.old_cwd // .previous_cwd // empty' 2>/dev/null || true)"
fi
if [ -z "$new_cwd" ]; then
    new_cwd="$(printf '%s' "$payload" | grep -oE '"(new_cwd|cwd|path)"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n1 | sed -E 's/.*:[[:space:]]*"(.*)"$/\1/' || true)"
fi
if [ -z "$old_cwd" ]; then
    old_cwd="$(printf '%s' "$payload" | grep -oE '"(old_cwd|previous_cwd)"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n1 | sed -E 's/.*:[[:space:]]*"(.*)"$/\1/' || true)"
fi

envrc_present="false"
if [ -n "$new_cwd" ] && [ -f "$new_cwd/.envrc" ]; then
    envrc_present="true"
fi

if command -v jq >/dev/null 2>&1; then
    jq -cn \
        --arg ts "$ts" \
        --arg old_cwd "$old_cwd" \
        --arg new_cwd "$new_cwd" \
        --argjson envrc_present "$envrc_present" \
        '{ts:$ts, old_cwd:$old_cwd, new_cwd:$new_cwd, envrc_present:$envrc_present}' \
        >> "$LOG_FILE"
else
    printf '{"ts":"%s","old_cwd":"%s","new_cwd":"%s","envrc_present":%s}\n' \
        "$ts" "$old_cwd" "$new_cwd" "$envrc_present" >> "$LOG_FILE"
fi

# Hint only — never source .envrc, never block.
exit 0
