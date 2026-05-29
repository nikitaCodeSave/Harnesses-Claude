#!/usr/bin/env bash
# SessionStart hook (LAB-ONLY) — surfaces the R&D loop STATE summary.
# Devlog + active-progress surfacing moved to the GLOBAL continuity hook
# (~/.claude/hooks/session-context.sh, devlog #54); kept here is only the
# lab-unique part: the self-improvement loop STATE, which has no meaning
# outside this repo. Both hooks fire here — no overlap by design.
# Per ADR-010: stays minimal. Advisory, exit 0 always.
set -euo pipefail

cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0

context=""
append() { context="${context:+$context$'\n'}$1"; }

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
