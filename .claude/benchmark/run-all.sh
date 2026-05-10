#!/usr/bin/env bash
# Top-level benchmark orchestrator — runs all tiers sequentially.
# Exits 0 if all pass, 1 if any tier fails.
set -uo pipefail

cd "$(dirname "$0")/../.."

echo "=== Tier 0 (static checks) ==="
if bash .claude/benchmark/static-checks.sh; then
    T0_STATUS="PASS"
else
    echo "Tier 0 FAIL — aborting"
    exit 1
fi

echo ""
echo "=== Tier 1 (pilot task suite) ==="
if bash .claude/benchmark/tier1/run-tier1.sh; then
    T1_STATUS="PASS"
else
    T1_STATUS="FAIL"
fi

echo ""
echo "=== Tier 2 (per-component evals) ==="
if bash .claude/benchmark/tier2/run-tier2.sh; then
    T2_STATUS="PASS"
else
    T2_STATUS="FAIL"
fi

echo ""
echo "=== Summary ==="
echo "Tier 0: $T0_STATUS"
echo "Tier 1: $T1_STATUS"
echo "Tier 2: $T2_STATUS"

if [[ "$T1_STATUS" == "FAIL" || "$T2_STATUS" == "FAIL" ]]; then
    exit 1
fi
