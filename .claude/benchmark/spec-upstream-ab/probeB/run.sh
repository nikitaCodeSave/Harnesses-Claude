#!/usr/bin/env bash
# Проба B: spec-faithfulness review A/B. Usage: bash run.sh <runs_root> [N]
# Каждый run-dir — git-репо с base-коммитом (стаб) и рабочим диффом (реализация).
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${1:?runs_root required}"
N="${2:-3}"

mkdir -p "$ROOT"
pids=()
for arm in A B; do
  PROMPT="$(cat "$DIR/protocol-$arm.md")"
  for i in $(seq 1 "$N"); do
    rd="$ROOT/$arm-r$i"
    rm -rf "$rd"; mkdir -p "$rd"
    cp -r "$DIR/fixture/." "$rd/"
    cp "$DIR/base-bank_import.py" "$rd/app/bank_import.py"
    ( cd "$rd" \
      && git init -q && git add -A \
      && git -c user.email=bench@local -c user.name=bench commit -qm "spec + tests + skeleton" \
      && cp "$DIR/fixture/app/bank_import.py" app/bank_import.py \
      && timeout 900 claude --print --model opus --permission-mode acceptEdits "$PROMPT" > out.md 2> err.log
      echo "$?" > exit.code ) &
    pids+=($!)
  done
done
wait "${pids[@]}"
echo "done: $ROOT"
for f in "$ROOT"/*/out.md; do printf '%s %s bytes exit=%s\n' "$f" "$(wc -c < "$f")" "$(cat "$(dirname "$f")/exit.code" 2>/dev/null)"; done
