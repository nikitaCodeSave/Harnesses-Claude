#!/usr/bin/env bash
# PreToolUse hook (matcher: Edit|Write|MultiEdit) for harness v0.1.
# Blocks file writes containing hardcoded secrets (API keys, tokens, passwords).
# Detects common patterns; not a substitute for proper secret management.
set -euo pipefail

LOG_DIR="${CLAUDE_PROJECT_DIR:-.}/.claude/memory"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/secret-scan.jsonl"

payload="$(cat || true)"
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

content=""
file_path=""
tool_name=""
if command -v jq >/dev/null 2>&1; then
    tool_name="$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null || true)"
    file_path="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"
    case "$tool_name" in
        Write)
            content="$(printf '%s' "$payload" | jq -r '.tool_input.content // empty' 2>/dev/null || true)"
            ;;
        Edit)
            content="$(printf '%s' "$payload" | jq -r '.tool_input.new_string // empty' 2>/dev/null || true)"
            ;;
        MultiEdit)
            content="$(printf '%s' "$payload" | jq -r '[.tool_input.edits[].new_string] | join("\n") // empty' 2>/dev/null || true)"
            ;;
    esac
fi

# Skip allowed paths: .env.example, tests with placeholder secrets, docs about secrets.
case "$file_path" in
    *.env.example|*test*|*spec*|*fixture*|*docs/*|*.md|*HARNESS-DECISIONS*|*RESEARCH-*|*PRACTICES-*)
        printf '{"ts":"%s","decision":"allowed","reason":"path allowlisted","file":"%s"}\n' \
            "$ts" "$file_path" >> "$LOG_FILE"
        exit 0
        ;;
esac

# Detection patterns. Conservative: prefer false-negatives over false-positives that block real work.
matches=""
add_match() { matches="${matches}${matches:+;}$1"; }

# AWS access key
if printf '%s' "$content" | grep -qE 'AKIA[0-9A-Z]{16}'; then
    add_match "aws-access-key"
fi
# GitHub token (classic + fine-grained)
if printf '%s' "$content" | grep -qE '(ghp|gho|ghs|ghu|ghr)_[A-Za-z0-9]{36,}'; then
    add_match "github-token"
fi
# Generic API key/secret with high-entropy assignment
if printf '%s' "$content" | grep -qiE '(api[_-]?key|secret[_-]?key|access[_-]?token|bearer)[[:space:]]*[:=][[:space:]]*['"'"'"][A-Za-z0-9_\-]{24,}['"'"'"]'; then
    add_match "generic-api-key"
fi
# Private key headers
if printf '%s' "$content" | grep -qE 'BEGIN (RSA |EC |OPENSSH |DSA )?PRIVATE KEY'; then
    add_match "private-key"
fi
# Slack token
if printf '%s' "$content" | grep -qE 'xox[abprs]-[A-Za-z0-9-]{10,}'; then
    add_match "slack-token"
fi

if [ -n "$matches" ]; then
    if command -v jq >/dev/null 2>&1; then
        jq -cn --arg ts "$ts" --arg file "$file_path" --arg matches "$matches" \
            '{ts:$ts, decision:"blocked", file:$file, matches:$matches}' >> "$LOG_FILE"
    fi
    echo "secret-scan blocked: detected secret pattern(s) in ${file_path}: ${matches}. Use environment variables or a secret manager; place placeholder in .env.example only." >&2
    exit 2
fi

printf '{"ts":"%s","decision":"allowed","file":"%s"}\n' "$ts" "$file_path" >> "$LOG_FILE"
exit 0
