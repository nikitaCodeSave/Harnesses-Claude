#!/usr/bin/env bash
# Tier 2 runner — validates eval set structure + counts entries.
# Actual trigger evaluation manual (requires Claude session с skill discovery).
set -uo pipefail

cd "$(dirname "$0")/../../.."

EVAL_DIR=".claude/benchmark/tier2/eval-sets"

if [[ ! -d "$EVAL_DIR" ]]; then
    echo "FAIL: eval-sets dir not found"
    exit 1
fi

# Discover skill eval sets (paired should-trigger + should-not-trigger)
declare -A SKILL_POS SKILL_NEG
TOTAL_SETS=0

for eval_file in "$EVAL_DIR"/*.txt; do
    [[ -f "$eval_file" ]] || continue
    fname="$(basename "$eval_file" .txt)"
    TOTAL_SETS=$((TOTAL_SETS + 1))

    case "$fname" in
        *-should-trigger)
            skill="${fname%-should-trigger}"
            SKILL_POS["$skill"]=$(grep -cv '^\s*$\|^\s*#' "$eval_file" 2>/dev/null || echo 0)
            ;;
        *-should-not-trigger)
            skill="${fname%-should-not-trigger}"
            SKILL_NEG["$skill"]=$(grep -cv '^\s*$\|^\s*#' "$eval_file" 2>/dev/null || echo 0)
            ;;
        *)
            echo "  warn: unrecognized eval file pattern: $fname"
            ;;
    esac
done

echo "Eval sets discovered: $TOTAL_SETS"
echo ""
echo "Skills coverage:"

EXIT_CODE=0
for skill in "${!SKILL_POS[@]}"; do
    pos=${SKILL_POS[$skill]:-0}
    neg=${SKILL_NEG[$skill]:-0}
    if [[ $pos -ge 5 && $neg -ge 5 ]]; then
        printf "  ✓ %-30s %2d should-trigger, %2d should-not-trigger\n" "$skill" "$pos" "$neg"
    else
        printf "  ⚠ %-30s %2d should-trigger, %2d should-not-trigger (need ≥5 each)\n" "$skill" "$pos" "$neg"
        EXIT_CODE=1
    fi
done

echo ""
echo "Execution mode: MANUAL"
echo "  For each skill:"
echo "    1. Send each query from should-trigger.txt — verify skill activates"
echo "    2. Send each query from should-not-trigger.txt — verify skill does NOT activate"
echo "    3. accuracy = (TP + TN) / total ≥ 85%"
echo ""

if [[ $EXIT_CODE -eq 0 ]]; then
    echo "=== Tier 2 scaffolding validated ==="
else
    echo "=== Tier 2 incomplete coverage (warnings above) ==="
fi
exit $EXIT_CODE
