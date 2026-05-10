#!/usr/bin/env bash
# Stop hook — independent verification на session end (multi-gate validation).
# Community evidence: false-completion rate 35% → 4% после independent verification.
# Goals:
#   - phantom-test detection (Claude утверждает «тесты pass» без session execution)
#   - phantom-completion detection (Claude декларирует «готово» при провале lint/type-check)
# Three independent gates: tests / lint / types. Каждый advisory: log + stderr warning.
# Hook НЕ блокирует session end (exit 0 always).
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

TEST_STATUS="skipped";  TEST_REASON="no_test_framework"
LINT_STATUS="skipped";  LINT_REASON="no_linter"
TYPES_STATUS="skipped"; TYPES_REASON="no_type_checker"

# === Python ветка ===
if [[ -n "$HAS_PYTHON" ]]; then
    # pytest gate
    if command -v pytest >/dev/null 2>&1; then
        TEST_DIR=""
        if [[ -d "tests" ]]; then
            TEST_DIR="tests"
        elif ls test_*.py >/dev/null 2>&1; then
            TEST_DIR="."
        fi
        if [[ -n "$TEST_DIR" ]]; then
            if pytest --quiet --tb=no "$TEST_DIR" >/dev/null 2>&1; then
                TEST_STATUS="pass"; TEST_REASON="pytest_passed"
            else
                TEST_STATUS="fail"; TEST_REASON="pytest_failed"
            fi
        fi
    fi
    # ruff gate (sensible defaults, конфиг не обязателен)
    if command -v ruff >/dev/null 2>&1; then
        if ruff check --quiet . >/dev/null 2>&1; then
            LINT_STATUS="pass"; LINT_REASON="ruff_clean"
        else
            LINT_STATUS="fail"; LINT_REASON="ruff_diagnostics"
        fi
    fi
    # mypy gate — требует explicit конфиг (без него floods diagnostics)
    HAS_MYPY_CFG=0
    [[ -f "mypy.ini" ]] && HAS_MYPY_CFG=1
    [[ -f "pyproject.toml" ]] && grep -q '^\[tool\.mypy\]' pyproject.toml 2>/dev/null && HAS_MYPY_CFG=1
    if command -v mypy >/dev/null 2>&1 && [[ $HAS_MYPY_CFG -eq 1 ]]; then
        if mypy . >/dev/null 2>&1; then
            TYPES_STATUS="pass"; TYPES_REASON="mypy_clean"
        else
            TYPES_STATUS="fail"; TYPES_REASON="mypy_diagnostics"
        fi
    fi
fi

# === JS/TS ветка ===
if [[ -n "$HAS_JS" && -f "package.json" ]] && command -v npm >/dev/null 2>&1; then
    # npm test gate (только если не отработала Python ветка — иначе mixed-repo confusion)
    if [[ "$TEST_STATUS" == "skipped" ]] && grep -q '"test"' package.json 2>/dev/null; then
        if npm test --silent >/dev/null 2>&1; then
            TEST_STATUS="pass"; TEST_REASON="npm_test_passed"
        else
            TEST_STATUS="fail"; TEST_REASON="npm_test_failed"
        fi
    fi
    # eslint gate — global или local через node_modules/.bin
    if [[ "$LINT_STATUS" == "skipped" ]]; then
        ESLINT_BIN=""
        if command -v eslint >/dev/null 2>&1; then
            ESLINT_BIN="eslint"
        elif [[ -x "node_modules/.bin/eslint" ]]; then
            ESLINT_BIN="node_modules/.bin/eslint"
        fi
        if [[ -n "$ESLINT_BIN" ]]; then
            if "$ESLINT_BIN" . --quiet >/dev/null 2>&1; then
                LINT_STATUS="pass"; LINT_REASON="eslint_clean"
            else
                LINT_STATUS="fail"; LINT_REASON="eslint_diagnostics"
            fi
        fi
    fi
    # tsc --noEmit gate — требует tsconfig.json
    if [[ "$TYPES_STATUS" == "skipped" ]] && [[ -f "tsconfig.json" ]]; then
        TSC_BIN=""
        if command -v tsc >/dev/null 2>&1; then
            TSC_BIN="tsc"
        elif [[ -x "node_modules/.bin/tsc" ]]; then
            TSC_BIN="node_modules/.bin/tsc"
        fi
        if [[ -n "$TSC_BIN" ]]; then
            if "$TSC_BIN" --noEmit >/dev/null 2>&1; then
                TYPES_STATUS="pass"; TYPES_REASON="tsc_clean"
            else
                TYPES_STATUS="fail"; TYPES_REASON="tsc_diagnostics"
            fi
        fi
    fi
fi

# Composite decision: первый fail wins; иначе worst non-skipped.
DECISION="skipped"; DECISION_REASON="no_gates_ran"
for pair in "$TEST_STATUS:$TEST_REASON" "$LINT_STATUS:$LINT_REASON" "$TYPES_STATUS:$TYPES_REASON"; do
    status="${pair%%:*}"; reason="${pair##*:}"
    if [[ "$status" == "fail" ]]; then
        DECISION="fail"; DECISION_REASON="$reason"; break
    fi
    if [[ "$status" == "pass" && "$DECISION" == "skipped" ]]; then
        DECISION="pass"; DECISION_REASON="$reason"
    fi
done

# Structured log
if command -v jq >/dev/null 2>&1; then
    jq -cn \
        --arg ts "$ts" \
        --arg decision "$DECISION" --arg reason "$DECISION_REASON" \
        --argjson files "$FILE_COUNT" \
        --arg ts_status "$TEST_STATUS"  --arg ts_reason "$TEST_REASON" \
        --arg ls_status "$LINT_STATUS"  --arg ls_reason "$LINT_REASON" \
        --arg ys_status "$TYPES_STATUS" --arg ys_reason "$TYPES_REASON" \
        '{ts:$ts, decision:$decision, reason:$reason, files_changed:$files,
          gates:{test:{status:$ts_status,reason:$ts_reason},
                 lint:{status:$ls_status,reason:$ls_reason},
                 types:{status:$ys_status,reason:$ys_reason}}}' >> "$LOG_FILE"
else
    printf '{"ts":"%s","decision":"%s","reason":"%s","files_changed":%d,"gates":{"test":{"status":"%s","reason":"%s"},"lint":{"status":"%s","reason":"%s"},"types":{"status":"%s","reason":"%s"}}}\n' \
        "$ts" "$DECISION" "$DECISION_REASON" "$FILE_COUNT" \
        "$TEST_STATUS" "$TEST_REASON" \
        "$LINT_STATUS" "$LINT_REASON" \
        "$TYPES_STATUS" "$TYPES_REASON" >> "$LOG_FILE"
fi

# Surface failed gates (advisory)
FAILURES=()
[[ "$TEST_STATUS"  == "fail" ]] && FAILURES+=("tests:$TEST_REASON")
[[ "$LINT_STATUS"  == "fail" ]] && FAILURES+=("lint:$LINT_REASON")
[[ "$TYPES_STATUS" == "fail" ]] && FAILURES+=("types:$TYPES_REASON")
if [[ ${#FAILURES[@]} -gt 0 ]]; then
    (IFS=', '; echo "stop-validation: phantom-completion check failed — ${FAILURES[*]}. Files changed: $FILE_COUNT. Re-run manually." >&2)
fi

# Stop hook exit codes: 0 allow, 2 force-continue. Advisory — never force.
exit 0
