#!/usr/bin/env bash
# PreToolUse hook (matcher: Edit|Write|MultiEdit) — protected-files guard.
# Active ONLY when LOOP_MODE=1 (set by .claude/loop/run.sh).
# Outside loop mode → pass-through (exit 0).
#
# In loop mode, blocks direct modifications to files listed in
# .claude/loop/corpus.yml.protected_files. Loop iterations must write a
# diff to .claude/loop/proposals/iter-NNNN-<basename>.diff instead.

set -euo pipefail

# Pass-through if not in loop mode
[[ "${LOOP_MODE:-0}" != "1" ]] && exit 0

HARNESS_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
LOG_FILE="$HARNESS_ROOT/.claude/memory/loop-protected-guard.jsonl"
mkdir -p "$(dirname "$LOG_FILE")"
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

payload="$(cat || true)"

if ! command -v jq >/dev/null 2>&1; then
    # No jq — fail open (allow), log warning
    printf '{"ts":"%s","decision":"allow-no-jq"}\n' "$ts" >> "$LOG_FILE"
    exit 0
fi

file_path="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"
[[ -z "$file_path" ]] && exit 0

# Normalize to absolute path
case "$file_path" in
    /*) abs_path="$file_path" ;;
    *)  abs_path="$HARNESS_ROOT/$file_path" ;;
esac

# Strip any "./" and resolve ".."
abs_path="$(realpath -m "$abs_path" 2>/dev/null || echo "$abs_path")"

# Protected list: suffix match — catches both harness root and worktrees/iter-NNNN/
# (worktrees mirror harness layout; CLAUDE.md inside a worktree is also off-limits)
protected_match=0
case "$abs_path" in
    */.claude/CLAUDE.md)                 protected_match=1 ;;
    */.claude/rules/*)                   protected_match=1 ;;
    */.claude/loop/run.sh)               protected_match=1 ;;
    */.claude/loop/PROMPT.md)            protected_match=1 ;;
    */.claude/loop/corpus.yml)           protected_match=1 ;;
    */.claude/loop/fitness.sh)           protected_match=1 ;;
    */.claude/loop/fitness.py)           protected_match=1 ;;
    */.claude/hooks/loop-protected-guard.sh) protected_match=1 ;;
esac

if [[ $protected_match -eq 1 ]]; then
    printf '{"ts":"%s","decision":"deny","file":"%s","reason":"protected"}\n' \
        "$ts" "$abs_path" >> "$LOG_FILE"
    cat <<EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Protected file under LOOP_MODE. Direct edit denied. Write a unified diff to .claude/loop/proposals/iter-NNNN-$(basename "$abs_path").diff instead, then output RESULT:PROPOSAL marker."}}
EOF
    exit 0
fi

printf '{"ts":"%s","decision":"allow","file":"%s"}\n' "$ts" "$abs_path" >> "$LOG_FILE"
exit 0
