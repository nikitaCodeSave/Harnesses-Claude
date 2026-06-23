#!/usr/bin/env bash
# Pre-seed run-директорий для SCOPED-DELIVERY условия: протокол доставляется
# ТОЛЬКО через nested CLAUDE.md в run-dir (в промпт сессии не ре-инжектится).
# Usage: bash seed-runs-scoped.sh <N>  — создаёт runs/scoped-{A,B}-rI для I=1..N
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
N="${1:-3}"
RUNS="$DIR/runs"
mkdir -p "$RUNS"
for arm in A B; do
  for i in $(seq 1 "$N"); do
    rd="$RUNS/scoped-${arm}-r${i}"
    mkdir -p "$rd"
    cp "$DIR/seed/backlog.md" "$rd/backlog.md"
    cp "$DIR/seed/features.json" "$rd/features.json"
    cp "$DIR/scoped/${arm}-CLAUDE.md" "$rd/CLAUDE.md"
    if [ "$arm" = "B" ]; then
      cp "$DIR/project_backlog.py" "$rd/project_backlog.py"
    fi
  done
done
echo "seeded $((N*2)) scoped run-dirs under $RUNS"
ls -1d "$RUNS"/scoped-*