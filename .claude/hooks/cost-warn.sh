#!/usr/bin/env bash
# UserPromptSubmit hook — warn when cumulative loop-iteration cost approaches budget.
# Reads .claude/loop/reports/iter-*.json (cost_usd field), sums across iters,
# injects additionalContext warning when sum >= COST_WARN_PCT% of LOOP_BUDGET_USD.
#
# Defaults match .claude/loop/run.sh: budget=$20, warn at 70%.
# Silent (exit 0, no output) when below threshold or when no reports present.
#
# Wiring (not done by this iter — settings.json is protected, requires proposal):
#   hooks.UserPromptSubmit += [{type: command, command: .claude/hooks/cost-warn.sh}]
#
# Per ADR-010: stays minimal. No state file — derives cumulative from existing reports.
set -euo pipefail
export LC_NUMERIC=C  # POSIX decimal separator (avoid locale-dependent comma)

cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0

threshold="${LOOP_BUDGET_USD:-20.00}"
warn_pct="${COST_WARN_PCT:-70}"

reports_dir=".claude/loop/reports"
[ -d "$reports_dir" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

total=0
for f in "$reports_dir"/iter-*.json; do
    [ -f "$f" ] || continue
    c=$(jq -r '.claude.cost_usd // .total_cost_usd // 0' "$f" 2>/dev/null || echo 0)
    total=$(awk -v a="$total" -v b="$c" 'BEGIN { printf "%.4f", a+b }')
done

warn_at=$(awk -v t="$threshold" -v p="$warn_pct" 'BEGIN { printf "%.4f", t*p/100 }')

if awk -v c="$total" -v w="$warn_at" 'BEGIN { exit !(c+0 >= w+0) }'; then
    over_budget=""
    if awk -v c="$total" -v t="$threshold" 'BEGIN { exit !(c+0 >= t+0) }'; then
        over_budget=" (OVER BUDGET)"
    fi
    msg="Cost warn: cumulative loop iter cost \$${total} ≥ ${warn_pct}% of \$${threshold} budget${over_budget}."
    jq -n --arg ctx "$msg" '{additionalContext: $ctx}'
fi

exit 0
