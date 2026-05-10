#!/usr/bin/env bash
# SessionStart hook — injects last devlog entry filename as additionalContext.
# Git context (branch, status, log) is already injected by Claude Code's built-in
# system prompt; this hook only adds harness-unique signal.
# Per ADR-010: trimmed from 58 → 22 lines (removed redundant git injection +
# observability log).
set -euo pipefail

cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0

devlog_entries_dir=".claude/devlog/entries"
[ -d "$devlog_entries_dir" ] || exit 0

last_entry="$(ls "$devlog_entries_dir"/[0-9]*.md 2>/dev/null | sort | tail -1)"
[ -n "$last_entry" ] || exit 0

last_devlog="$(basename "$last_entry")"
context="Last devlog entry: $last_devlog"

if command -v jq >/dev/null 2>&1; then
    jq -n --arg ctx "$context" '{additionalContext: $ctx}'
else
    printf '%s\n' "$context"
fi

exit 0
