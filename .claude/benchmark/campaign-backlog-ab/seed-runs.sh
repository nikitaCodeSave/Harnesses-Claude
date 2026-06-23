#!/usr/bin/env bash
# Pre-seed run-директории для A/B (workflow сам файлы не пишет).
# Usage: bash seed-runs.sh <N>   — создаёт runs/A-rI и runs/B-rI для I=1..N
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
N="${1:-1}"
RUNS="$DIR/runs"
rm -rf "$RUNS"
mkdir -p "$RUNS"
for arm in A B; do
  for i in $(seq 1 "$N"); do
    rd="$RUNS/${arm}-r${i}"
    mkdir -p "$rd"
    cp "$DIR/seed/backlog.md" "$rd/backlog.md"
    cp "$DIR/seed/features.json" "$rd/features.json"
    cp "$DIR/protocols/${arm}.md" "$rd/PROTOCOL.md"
    if [ "$arm" = "B" ]; then
      cp "$DIR/project_backlog.py" "$rd/project_backlog.py"
    fi
  done
done
echo "seeded $((N*2)) run-dirs under $RUNS"
ls -1 "$RUNS"
