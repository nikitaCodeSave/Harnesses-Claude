#!/usr/bin/env bash
# Stop hook — Evaluator-node reminder (project-portable, opt-in, never blocks).
#
# Companion to .claude/agents/discovery-critic.md and .claude/commands/critique.md.
# This hook is a PRE-/critique reminder: it nags about missing/incomplete PREMORTEM
# and EVIDENCE before the agent stops. Never blocks (always exit 0). The /critique
# slash command does the actual evaluator pass and parses CRITIC.json directly —
# no need to duplicate that validation here.
#
# Trigger (any one activates; default off — pass-through exit 0):
#   - EVALUATOR_GATE_ACTIVE=1            (env var, per-shell)
#   - .claude/.evaluator-active          (marker file, per-project)
#
# Behavior when active:
#   - Always exit 0. Never blocks the agent stop. Reminder, not gate.
#   - One JSONL audit row to .claude/memory/discovery-gate.jsonl per invocation.
#     decision={allow|advisory}, allow_reason={clean|errors_advisory}.
#   - On missing/short/spread-failing PREMORTEM or EVIDENCE → stderr reminder.
#
# Required artifacts (parsed via jq):
#   - PREMORTEM.json   ≥4 entries in .failure_modes[]; categories span ≥3 distinct
#   - EVIDENCE.json    ≥3 entries in .runs[]
#
# JSON parsing: jq required when active. Without jq, hook degrades to pass-through
# with stderr warning (does not break sessions without jq).

set -uo pipefail

if ! cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null; then
    echo "discovery-gate: cd '${CLAUDE_PROJECT_DIR:-.}' failed, passing through" >&2
    exit 0
fi

# --- Trigger detection ---
ACTIVE=0
[[ "${EVALUATOR_GATE_ACTIVE:-0}" == "1" ]] && ACTIVE=1
[[ -f ".claude/.evaluator-active" ]] && ACTIVE=1
[[ $ACTIVE -eq 1 ]] || exit 0

# --- jq dependency ---
if ! command -v jq >/dev/null 2>&1; then
    echo "discovery-gate: jq not found; reminder degraded to pass-through. Install jq to enable JSON validation." >&2
    exit 0
fi

# --- Paths ---
PREMORTEM="PREMORTEM.json"
EVIDENCE="EVIDENCE.json"
LOG_DIR=".claude/memory"
mkdir -p "$LOG_DIR" 2>/dev/null
LOG_FILE="$LOG_DIR/discovery-gate.jsonl"
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Coerce a possibly-malformed integer string to a valid non-negative int.
normalize_int() {
    local v="${1%%.*}"
    v="${v//[!0-9]/}"
    echo "${v:-0}"
}

# Validate JSON array artifact: file exists, valid JSON, top-level array of min_count entries.
# Pushes domain-specific errors into the global errors[] array; sets out_var to entry count.
validate_json_array_artifact() {
    local file="$1" field="$2" min_count="$3"
    local missing_msg="$4" type_msg="$5" count_msg_template="$6"
    local -n out="$7"
    out=0
    if [[ ! -f "$file" ]]; then
        errors+=("$missing_msg")
        return
    fi
    if ! jq empty "$file" 2>/dev/null; then
        errors+=("$file is not valid JSON. Run 'jq empty $file' to see parser error.")
        return
    fi
    if ! jq -e ".${field} | type == \"array\"" "$file" >/dev/null 2>&1; then
        errors+=("$type_msg")
        return
    fi
    out=$(normalize_int "$(jq ".${field} | length" "$file" 2>/dev/null)")
    if (( out < min_count )); then
        errors+=("${count_msg_template//__COUNT__/$out}")
    fi
}

errors=()
premortem_count=0
premortem_categories=0
evidence_count=0

validate_json_array_artifact "$PREMORTEM" "failure_modes" 4 \
    "PREMORTEM.json missing. Before declaring done on high-stakes work, write a failure-mode catalog (≥4 entries, ≥3 distinct categories: state|precondition|boundary|resource|concurrency|security|semantics|other). Then run /critique for adversarial review." \
    "PREMORTEM.json .failure_modes is not an array (must be JSON array, not string/object/number)." \
    "PREMORTEM.json has only __COUNT__ entries in failure_modes[] (≥4 required)." \
    premortem_count

# Category-spread check (≥3 distinct categories) — stuffing same-category findings bypasses adversarial intent.
if [[ -f "$PREMORTEM" ]] && jq empty "$PREMORTEM" 2>/dev/null && jq -e '.failure_modes | type == "array"' "$PREMORTEM" >/dev/null 2>&1; then
    premortem_categories=$(normalize_int "$(jq '[.failure_modes[].category] | unique | length' "$PREMORTEM" 2>/dev/null)")
    if (( premortem_count >= 4 )) && (( premortem_categories < 3 )); then
        errors+=("PREMORTEM.json failure_modes span only $premortem_categories distinct categories (≥3 required). Diversify across state|precondition|boundary|resource|concurrency|security|semantics.")
    fi
fi

validate_json_array_artifact "$EVIDENCE" "runs" 3 \
    "EVIDENCE.json missing. Document ≥3 real executions (real_or_mock=\"real\"). For inherently destructive deliverables (migrations, deploy scripts) add at least one read-only post-state verification run (table grep, ls of created files, curl GET against affected endpoint) so the critic can re-execute it. Then run /critique." \
    "EVIDENCE.json .runs is not an array." \
    "EVIDENCE.json has only __COUNT__ entries in runs[] (≥3 required)." \
    evidence_count

# --- Decision ---
# allow_reason distinguishes clean from reminder-with-issues — JSONL audit grep
# can filter `allow_reason=="clean"` to exclude reminder invocations.
decision="allow"
allow_reason="clean"
if (( ${#errors[@]} > 0 )); then
    decision="advisory"
    allow_reason="errors_advisory"
fi

# --- Log ---
jq -cn --arg ts "$ts" --arg decision "$decision" --arg areason "$allow_reason" \
    --argjson p "$premortem_count" --argjson pc "$premortem_categories" --argjson e "$evidence_count" \
    --argjson errn "${#errors[@]}" \
    '{ts:$ts, decision:$decision, allow_reason:$areason,
      premortem_count:$p, premortem_categories:$pc, evidence_count:$e,
      errors_count:$errn}' \
    >> "$LOG_FILE" 2>/dev/null

# --- Surface ---
if (( ${#errors[@]} > 0 )); then
    {
        echo "=========================================="
        echo "EVALUATOR REMINDER — issues found (not blocking)"
        echo "=========================================="
        echo ""
        for err in "${errors[@]}"; do
            echo "  • $err"
            echo ""
        done
        echo "This is a pre-/critique nudge — once PREMORTEM/EVIDENCE are complete,"
        echo "run /critique for the actual adversarial review. Hook never blocks."
    } >&2
fi

exit 0
