#!/usr/bin/env bash
# PreToolUse hook (matcher: Bash) for harness v0.1.
# Blocks destructive shell commands that have no safe rollback.
# Conservative: matches commands by canonical patterns; soft on edge cases.
set -euo pipefail

LOG_DIR="${CLAUDE_PROJECT_DIR:-.}/.claude/memory"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/dangerous-cmd.jsonl"

payload="$(cat || true)"
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

cmd=""
if command -v jq >/dev/null 2>&1; then
    cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
fi

[ -z "$cmd" ] && exit 0

block_reason=""

# rm -rf on root, home, or anchored paths.
if printf '%s' "$cmd" | grep -qE '(^|[[:space:]&|;])rm[[:space:]]+(-[a-zA-Z]*r[a-zA-Z]*[a-zA-Z]*f|-rf|-fr)([[:space:]]+--?[a-zA-Z]+)*[[:space:]]+(/|~|\$HOME|\*)([[:space:]]|$)'; then
    block_reason="rm -rf on root/home/wildcard"
fi
# Filesystem destruction
if printf '%s' "$cmd" | grep -qE '(^|[[:space:]&|;])(mkfs|dd[[:space:]]+if=.*of=/dev/|shred[[:space:]]+/)'; then
    block_reason="${block_reason:+$block_reason; }filesystem destruction"
fi
# Force-push to protected branches
if printf '%s' "$cmd" | grep -qE 'git[[:space:]]+push[[:space:]]+(--force|-f)([^a-zA-Z]|$).*\b(main|master|prod|production|release)\b'; then
    block_reason="${block_reason:+$block_reason; }force-push to protected branch"
fi
# Force-push to all remotes
if printf '%s' "$cmd" | grep -qE 'git[[:space:]]+push[[:space:]]+(--force|-f).*--all'; then
    block_reason="${block_reason:+$block_reason; }force-push --all"
fi
# Fork bomb
if printf '%s' "$cmd" | grep -qE ':\(\)[[:space:]]*\{[[:space:]]*:\|:&[[:space:]]*\};:'; then
    block_reason="${block_reason:+$block_reason; }fork bomb"
fi
# chmod 777 on broad paths
if printf '%s' "$cmd" | grep -qE 'chmod[[:space:]]+(-R[[:space:]]+)?777[[:space:]]+(/|~|\$HOME)'; then
    block_reason="${block_reason:+$block_reason; }chmod 777 on root/home"
fi
# Shutdown / reboot
if printf '%s' "$cmd" | grep -qE '(^|[[:space:]&|;])(shutdown|halt|poweroff|reboot)([[:space:]]|$)'; then
    block_reason="${block_reason:+$block_reason; }system power command"
fi
# git reset --hard on bare HEAD without explicit commit (rare but catastrophic if uncommitted work)
# Skip — too many false positives; let user judgment handle.

if [ -n "$block_reason" ]; then
    if command -v jq >/dev/null 2>&1; then
        jq -cn --arg ts "$ts" --arg cmd "$cmd" --arg reason "$block_reason" \
            '{ts:$ts, decision:"blocked", cmd:$cmd, reason:$reason}' >> "$LOG_FILE"
    fi
    echo "dangerous-cmd blocked: ${block_reason}. If this is intentional, run from your shell directly." >&2
    exit 2
fi

if command -v jq >/dev/null 2>&1; then
    jq -cn --arg ts "$ts" --arg cmd "$cmd" \
        '{ts:$ts, decision:"allowed", cmd:$cmd}' >> "$LOG_FILE"
fi
exit 0
