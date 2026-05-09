#!/usr/bin/env bash
# SessionStart hook for harness v0.2.
# Injects compact git context (branch, status summary, last commits) into the
# session as additionalContext per Effective harnesses pattern.
# Reference: anthropic.com/engineering/effective-harnesses-for-long-running-agents
# Returns JSON {"additionalContext": "..."} on stdout per Claude Code hooks spec.
set -euo pipefail

LOG_DIR="${CLAUDE_PROJECT_DIR:-.}/.claude/memory"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/session-starts.jsonl"

cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0

# Skip silently if not a git repo.
if ! git rev-parse --git-dir >/dev/null 2>&1; then
    if command -v jq >/dev/null 2>&1; then
        jq -cn --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            '{ts:$ts, status:"skip", reason:"not-a-git-repo"}' >> "$LOG_FILE"
    fi
    exit 0
fi

branch="$(git branch --show-current 2>/dev/null || echo 'detached')"
modified_count="$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
last_commits="$(git log --oneline -5 2>/dev/null || echo 'no-commits')"

# Last devlog entry, if any.
devlog_entries_dir="${CLAUDE_PROJECT_DIR:-.}/.claude/devlog/entries"
last_devlog=""
if [ -d "$devlog_entries_dir" ]; then
    last_entry="$(ls "$devlog_entries_dir"/[0-9]*.md 2>/dev/null | sort | tail -1)"
    if [ -n "$last_entry" ]; then
        last_devlog="$(basename "$last_entry")"
    fi
fi

# Compose additionalContext (compact — context budget is a public good).
context="Session start (auto via SessionStart hook):
- Branch: $branch
- Working tree: $modified_count modified file(s)
- Recent commits:
$(printf '%s' "$last_commits" | sed 's/^/  /')"
if [ -n "$last_devlog" ]; then
    context="$context
- Last devlog entry: $last_devlog"
fi

if command -v jq >/dev/null 2>&1; then
    jq -n --arg ctx "$context" '{additionalContext: $ctx}'
    jq -cn --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg branch "$branch" --argjson modified "$modified_count" \
        '{ts:$ts, status:"injected", branch:$branch, modified:$modified}' >> "$LOG_FILE"
else
    # Fallback: plain stdout becomes context per hooks spec.
    printf '%s\n' "$context"
fi

exit 0
