#!/usr/bin/env bash
# SessionStart hook — injects harness-unique signal as additionalContext.
# Sends: last devlog entry filename + (if present) compact loop STATE summary.
# Git context (branch, status, log) is injected by Claude Code built-in system
# prompt; this hook adds only what built-ins don't cover.
# Per ADR-010: stays minimal (≤ 40 lines). H-004: loop STATE summary added.
set -euo pipefail

cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0

context=""
append() { context="${context:+$context$'\n'}$1"; }

devlog_entries_dir=".claude/devlog/entries"
if [ -d "$devlog_entries_dir" ]; then
    last_entry="$(ls "$devlog_entries_dir"/[0-9]*.md 2>/dev/null | sort | tail -1)" || true
    if [ -n "${last_entry:-}" ]; then
        append "Last devlog entry: $(basename "$last_entry")"
    fi
fi

state_file=".claude/loop/STATE.md"
if [ -f "$state_file" ]; then
    iter=$(grep -m1 -E '^iteration:'              "$state_file" | awk '{print $2}' || true)
    last_acc=$(grep -m1 -E '^last_accept_iteration:' "$state_file" | awk '{print $2}' || true)
    n_acc=$(grep -m1 -E '^total_accepted:'        "$state_file" | awk '{print $2}' || true)
    n_rej=$(grep -m1 -E '^total_rejected:'        "$state_file" | awk '{print $2}' || true)
    n_prop=$(grep -m1 -E '^total_proposals:'      "$state_file" | awk '{print $2}' || true)
    in_flight=$(grep -m1 -E '^in_flight_hypothesis:' "$state_file" | awk '{print $2}' || true)
    if [ -n "${iter:-}" ]; then
        append "Loop: iter-${iter} (${n_acc:-?} acc / ${n_rej:-?} rej / ${n_prop:-?} prop), last accept iter-${last_acc:-?}, in_flight=${in_flight:-none}"
    fi
fi

[ -z "$context" ] && exit 0

if command -v jq >/dev/null 2>&1; then
    jq -n --arg ctx "$context" '{additionalContext: $ctx}'
else
    printf '%s\n' "$context"
fi

exit 0
