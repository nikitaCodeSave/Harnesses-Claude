#!/usr/bin/env bash
# Tier 1 runner — validates task suite structure, lists tasks для manual execution.
# Future: automate via `claude --bare --print --add-dir <fixture>` cycle.
set -uo pipefail

cd "$(dirname "$0")/../../.."

TASKS_DIR=".claude/benchmark/tier1/tasks"
FIXTURE_PATH="${FIXTURE_PATH:-.claude/benchmark/fixtures/sample-py-app}"

echo "Fixture: $FIXTURE_PATH"

if [[ ! -d "$FIXTURE_PATH" ]]; then
    echo "FAIL: fixture not found"
    exit 1
fi

if [[ ! -d "$TASKS_DIR" ]]; then
    echo "FAIL: tasks dir not found"
    exit 1
fi

# Validate fixture минимально
FIXTURE_FILES=$(find "$FIXTURE_PATH" -maxdepth 2 -type f 2>/dev/null | wc -l)
if [[ $FIXTURE_FILES -lt 2 ]]; then
    echo "FAIL: fixture has $FIXTURE_FILES files (need ≥2)"
    exit 1
fi

# Validate tasks structure
TASK_COUNT=0
INVALID=0
for task_yaml in "$TASKS_DIR"/*.yaml; do
    [[ -f "$task_yaml" ]] || continue
    TASK_COUNT=$((TASK_COUNT + 1))
    task_id="$(basename "$task_yaml" .yaml)"
    if ! grep -q "^id:" "$task_yaml" || ! grep -q "^type:" "$task_yaml" || ! grep -q "^prompt:" "$task_yaml"; then
        echo "  ✗ $task_id (missing required fields)"
        INVALID=$((INVALID + 1))
    else
        echo "  ✓ $task_id"
    fi
done

echo ""
echo "Discovered $TASK_COUNT tasks ($INVALID invalid)."

if [[ $INVALID -gt 0 ]]; then
    echo "FAIL: $INVALID malformed task definitions"
    exit 1
fi

echo ""
echo "Execution mode: MANUAL (interactive Claude session)"
echo "  For each task:"
echo "    1. Read prompt из $TASKS_DIR/<task>.yaml"
echo "    2. Apply on fixture: $FIXTURE_PATH"
echo "    3. Capture metrics (tokens, turns, files, success)"
echo "    4. Save report at .claude/benchmark/reports/tier1-<task>-<date>.md"
echo ""
echo "=== Tier 1 scaffolding validated ==="
