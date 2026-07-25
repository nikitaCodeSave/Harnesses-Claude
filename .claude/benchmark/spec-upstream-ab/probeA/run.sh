#!/usr/bin/env bash
# Проба A: spec-synthesis A/B. Usage: bash run.sh <runs_root> [N]
# Каждый прогон — изолированный cwd вне репо (чтобы не подхватить проектный CLAUDE.md).
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${1:?runs_root required}"
N="${2:-3}"
TRANSCRIPT="$(cat "$DIR/grill-transcript.md")"

mkdir -p "$ROOT"
pids=()
for arm in A B; do
  PROTO="$(cat "$DIR/protocol-$arm.md")"
  PROMPT="$PROTO

---

$TRANSCRIPT"
  for i in $(seq 1 "$N"); do
    rd="$ROOT/$arm-r$i"; mkdir -p "$rd"
    ( cd "$rd" && timeout 600 claude --print --model opus "$PROMPT" > out.md 2> err.log; echo "$?" > exit.code ) &
    pids+=($!)
  done
done
wait "${pids[@]}"
echo "done: $ROOT"
for f in "$ROOT"/*/out.md; do printf '%s %s bytes exit=%s\n' "$f" "$(wc -c < "$f")" "$(cat "$(dirname "$f")/exit.code")"; done
