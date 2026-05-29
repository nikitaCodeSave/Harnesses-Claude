#!/usr/bin/env bash
# run-audit.sh — adversarial post-test audit на single artifact.
#
# Запускает fresh claude --print session в копии артефакта с critic-промптом
# (audit-prompt.md) + spec inline. Парсит JSON-line findings + SUMMARY.
#
# Usage:
#   run-audit.sh --artifact <dir> --spec <file> [--output <dir>]
#                [--model claude-opus-4-7] [--timeout-sec 600]
#
# Output: <output>/findings.jsonl + <output>/summary.json + <output>/raw-stream.jsonl

set -uo pipefail

ARTIFACT=""
SPEC=""
OUTPUT=""
MODEL="claude-opus-4-7"
TIMEOUT_SEC=900   # 15 min hard cap (audit is supposed to take ~10)

while [[ $# -gt 0 ]]; do
    case "$1" in
        --artifact)    ARTIFACT="$2"; shift 2 ;;
        --spec)        SPEC="$2"; shift 2 ;;
        --output)      OUTPUT="$2"; shift 2 ;;
        --model)       MODEL="$2"; shift 2 ;;
        --timeout-sec) TIMEOUT_SEC="$2"; shift 2 ;;
        *)             echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

[[ -d "$ARTIFACT" ]] || { echo "FAIL: artifact dir missing: $ARTIFACT" >&2; exit 2; }
[[ -f "$SPEC" ]]     || { echo "FAIL: spec file missing: $SPEC" >&2; exit 2; }

HARNESS_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PROMPT_TPL="$HARNESS_ROOT/benchmark/audit/audit-prompt.md"
[[ -f "$PROMPT_TPL" ]] || { echo "FAIL: audit-prompt.md missing at $PROMPT_TPL" >&2; exit 2; }

TS=$(date -u +%Y%m%dT%H%M%SZ)
ARTIFACT_NAME=$(basename "$ARTIFACT")
[[ -z "$OUTPUT" ]] && OUTPUT="$HARNESS_ROOT/benchmark/audit/results/${ARTIFACT_NAME}-${TS}"
mkdir -p "$OUTPUT"

# Fresh copy of artifact (critic is read-only by prompt, but we double-isolate).
WORK_DIR="/tmp/audit-${ARTIFACT_NAME}-${TS}"
cp -r "$ARTIFACT" "$WORK_DIR"
# Strip injected harness if present (critic should see only deliverable).
rm -rf "$WORK_DIR/.claude" 2>/dev/null
# Strip bench-internal artifacts.
rm -f "$WORK_DIR/.bench-stream.jsonl" "$WORK_DIR/.bench-stderr.log" \
      "$WORK_DIR/.bench-install.log" 2>/dev/null

# Build prompt: spec inline + audit instructions.
PROMPT=$(cat <<EOF
## SPEC (what the deliverable should do)

\`\`\`
$(cat "$SPEC")
\`\`\`

## AUDIT INSTRUCTIONS

$(cat "$PROMPT_TPL")
EOF
)

STREAM_FILE="$OUTPUT/raw-stream.jsonl"
STDERR_FILE="$OUTPUT/stderr.log"
START_EPOCH=$(date +%s)

cd "$WORK_DIR"
echo "[audit] artifact=$ARTIFACT_NAME work=$WORK_DIR output=$OUTPUT model=$MODEL timeout=${TIMEOUT_SEC}s"
echo "[audit] starting at $(date -u +%Y-%m-%dT%H:%M:%SZ)..."

set +e
echo "$PROMPT" | timeout "$TIMEOUT_SEC" claude --print \
    --model "$MODEL" \
    --output-format stream-json \
    --verbose \
    --permission-mode bypassPermissions \
    --no-session-persistence \
    > "$STREAM_FILE" 2> "$STDERR_FILE"
EXIT=$?
set -e

END_EPOCH=$(date +%s)
WALL=$((END_EPOCH - START_EPOCH))

# Parse result event for cost/turns.
COST=0; NUM_TURNS=0; STOP_REASON="<unknown>"; RESULT_TEXT=""
if [[ -s "$STREAM_FILE" ]]; then
    RESULT_EVENT=$(jq -c 'select(.type=="result")' "$STREAM_FILE" 2>/dev/null | tail -1)
    if [[ -n "$RESULT_EVENT" ]]; then
        NUM_TURNS=$(echo   "$RESULT_EVENT" | jq -r '.num_turns // 0')
        COST=$(echo        "$RESULT_EVENT" | jq -r '.total_cost_usd // 0')
        STOP_REASON=$(echo "$RESULT_EVENT" | jq -r '.stop_reason // "<unknown>"')
        RESULT_TEXT=$(echo "$RESULT_EVENT" | jq -r '.result // ""')
    fi
fi

# Extract assistant text (where JSON-line findings live).
ASSISTANT_TEXT_FILE="$OUTPUT/assistant-text.txt"
jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text' \
    "$STREAM_FILE" 2>/dev/null > "$ASSISTANT_TEXT_FILE" || true
# Append result text (sometimes findings end up only in result).
echo "$RESULT_TEXT" >> "$ASSISTANT_TEXT_FILE"

# Extract JSON-line findings: lines starting with `{"id":` and parsing as JSON.
FINDINGS_FILE="$OUTPUT/findings.jsonl"
grep -E '^\s*\{"id"' "$ASSISTANT_TEXT_FILE" | \
    while IFS= read -r line; do
        if echo "$line" | jq -e . >/dev/null 2>&1; then
            echo "$line"
        fi
    done > "$FINDINGS_FILE" || true

TOTAL=$(wc -l < "$FINDINGS_FILE" | tr -d '[:space:]')
[[ -z "$TOTAL" ]] && TOTAL=0

# Parse SUMMARY line if present.
SUMMARY_LINE=$(grep -E '^SUMMARY:' "$ASSISTANT_TEXT_FILE" | tail -1)
SUMMARY_PARSED='{}'
if [[ -n "$SUMMARY_LINE" ]]; then
    # Parse "SUMMARY: total=N critical=N major=N minor=N verified=N reasoned=N speculative=N"
    SUMMARY_PARSED=$(echo "$SUMMARY_LINE" | python3 -c '
import sys, re, json
line = sys.stdin.read().strip()
m = re.findall(r"(\w+)=(\d+)", line)
print(json.dumps({k: int(v) for k, v in m}))
' 2>/dev/null || echo '{}')
fi

# Independent counts from JSON lines.
CRITICAL=$(jq -s '[.[] | select(.severity=="critical")] | length' "$FINDINGS_FILE" 2>/dev/null || echo 0)
MAJOR=$(jq -s    '[.[] | select(.severity=="major")] | length'    "$FINDINGS_FILE" 2>/dev/null || echo 0)
MINOR=$(jq -s    '[.[] | select(.severity=="minor")] | length'    "$FINDINGS_FILE" 2>/dev/null || echo 0)
VERIFIED=$(jq -s '[.[] | select(.demonstrability=="verified")] | length' "$FINDINGS_FILE" 2>/dev/null || echo 0)
REASONED=$(jq -s '[.[] | select(.demonstrability=="reasoned")] | length' "$FINDINGS_FILE" 2>/dev/null || echo 0)
SPEC_CT=$(jq -s  '[.[] | select(.demonstrability=="speculative")] | length' "$FINDINGS_FILE" 2>/dev/null || echo 0)

# Categories breakdown.
CATEGORIES=$(jq -sc 'group_by(.category) | map({category: .[0].category, count: length}) | sort_by(-.count)' "$FINDINGS_FILE" 2>/dev/null || echo '[]')

# Final summary JSON.
jq -n \
    --arg artifact "$ARTIFACT" \
    --arg artifact_name "$ARTIFACT_NAME" \
    --arg model "$MODEL" \
    --argjson exit "$EXIT" \
    --argjson wall "$WALL" \
    --argjson cost "$COST" \
    --argjson turns "$NUM_TURNS" \
    --arg stop "$STOP_REASON" \
    --argjson total "$TOTAL" \
    --argjson critical "$CRITICAL" \
    --argjson major "$MAJOR" \
    --argjson minor "$MINOR" \
    --argjson verified "$VERIFIED" \
    --argjson reasoned "$REASONED" \
    --argjson speculative "$SPEC_CT" \
    --argjson categories "$CATEGORIES" \
    --argjson critic_summary "$SUMMARY_PARSED" \
    '{
        artifact: $artifact,
        artifact_name: $artifact_name,
        audit: {
            model: $model,
            exit: $exit,
            wall_seconds: $wall,
            num_turns: $turns,
            cost_usd: $cost,
            stop_reason: $stop
        },
        findings: {
            total: $total,
            by_severity: {critical: $critical, major: $major, minor: $minor},
            by_demonstrability: {verified: $verified, reasoned: $reasoned, speculative: $speculative},
            by_category: $categories
        },
        critic_summary_line: $critic_summary
    }' > "$OUTPUT/summary.json"

echo ""
echo "=== Audit summary ==="
echo "Artifact: $ARTIFACT_NAME"
echo "Wall: ${WALL}s | Cost: \$$COST | Turns: $NUM_TURNS | Stop: $STOP_REASON"
echo "Findings: $TOTAL total ($CRITICAL critical, $MAJOR major, $MINOR minor)"
echo "Demonstrability: $VERIFIED verified, $REASONED reasoned, $SPEC_CT speculative"
echo "Output: $OUTPUT"

# Cleanup work dir (artifact preserved at original path).
rm -rf "$WORK_DIR" 2>/dev/null

exit 0
