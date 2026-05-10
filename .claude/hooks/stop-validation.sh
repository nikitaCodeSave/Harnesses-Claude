#!/usr/bin/env bash
# Stop hook — independent test re-run при session end (two-gate validation).
# Community evidence: false-completion rate 35% → 4% after independent verification.
# Goal: detect phantom verification (Claude claims tests pass без session execution).
# Behavior: advisory-only (log + stderr warning), does NOT block session end.
set -uo pipefail

LOG_DIR="${CLAUDE_PROJECT_DIR:-.}/.claude/memory"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/stop-validation.jsonl"
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0

# Detect change scope из git status
CHANGED_UNSTAGED=$(git diff --name-only 2>/dev/null || true)
CHANGED_STAGED=$(git diff --staged --name-only 2>/dev/null || true)
CHANGED_FILES="$CHANGED_UNSTAGED
$CHANGED_STAGED"
CHANGED_FILES=$(echo "$CHANGED_FILES" | sort -u | grep -v '^$' || true)

if [[ -z "$CHANGED_FILES" ]]; then
    printf '{"ts":"%s","decision":"skipped","reason":"no_changes"}\n' "$ts" >> "$LOG_FILE"
    exit 0
fi

FILE_COUNT=$(echo "$CHANGED_FILES" | wc -l)
HAS_PYTHON=$(echo "$CHANGED_FILES" | grep -E '\.py$' | head -1 || true)
HAS_JS=$(echo "$CHANGED_FILES" | grep -E '\.(js|ts|jsx|tsx)$' | head -1 || true)

VALIDATION_STATUS="skipped"
VALIDATION_REASON="no_recognized_test_framework"

# Python: pytest if available
if [[ -n "$HAS_PYTHON" ]] && command -v pytest >/dev/null 2>&1; then
    TEST_DIR=""
    if [[ -d "tests" ]]; then
        TEST_DIR="tests"
    elif ls test_*.py >/dev/null 2>&1; then
        TEST_DIR="."
    fi
    if [[ -n "$TEST_DIR" ]]; then
        if pytest --quiet --tb=no "$TEST_DIR" >/dev/null 2>&1; then
            VALIDATION_STATUS="pass"
            VALIDATION_REASON="pytest_passed"
        else
            VALIDATION_STATUS="fail"
            VALIDATION_REASON="pytest_failed"
        fi
    fi
fi

# JS: npm test if package.json + test script
if [[ "$VALIDATION_STATUS" == "skipped" && -n "$HAS_JS" && -f "package.json" ]] && command -v npm >/dev/null 2>&1; then
    if grep -q '"test"' package.json 2>/dev/null; then
        if npm test --silent >/dev/null 2>&1; then
            VALIDATION_STATUS="pass"
            VALIDATION_REASON="npm_test_passed"
        else
            VALIDATION_STATUS="fail"
            VALIDATION_REASON="npm_test_failed"
        fi
    fi
fi

# Log structured result
if command -v jq >/dev/null 2>&1; then
    jq -cn --arg ts "$ts" --arg status "$VALIDATION_STATUS" --arg reason "$VALIDATION_REASON" --argjson files "$FILE_COUNT" \
        '{ts:$ts, decision:$status, reason:$reason, files_changed:$files}' >> "$LOG_FILE"
else
    printf '{"ts":"%s","decision":"%s","reason":"%s","files_changed":%d}\n' \
        "$ts" "$VALIDATION_STATUS" "$VALIDATION_REASON" "$FILE_COUNT" >> "$LOG_FILE"
fi

# Surface failure to user (advisory, не block)
if [[ "$VALIDATION_STATUS" == "fail" ]]; then
    echo "stop-validation: tests FAILED after session changes ($VALIDATION_REASON). Files changed: $FILE_COUNT. Re-run tests manually." >&2
fi

# Stop hook exit codes: 0 allow session end, 2 force continuation. We advise, не force.
exit 0
