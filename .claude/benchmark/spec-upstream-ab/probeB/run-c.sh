#!/usr/bin/env bash
# Рукав C (контроль к пробе B): тот же дифф и тот же мандат рукава A, но docs/SPEC.md
# в репозитории НЕТ. Отвечает на вопрос: что сработало — мандат spec-faithfulness
# или само наличие спеки в репо.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${1:?runs_root required}"; N="${2:-3}"
PROMPT="$(cat "$DIR/protocol-A.md")"
mkdir -p "$ROOT"; pids=()
for i in $(seq 1 "$N"); do
  rd="$ROOT/C-r$i"; rm -rf "$rd"; mkdir -p "$rd"
  cp -r "$DIR/fixture/." "$rd/"; rm -rf "$rd/docs"
  cp "$DIR/base-bank_import.py" "$rd/app/bank_import.py"
  ( cd "$rd" && git init -q && git add -A \
    && git -c user.email=bench@local -c user.name=bench commit -qm "tests + skeleton" \
    && cp "$DIR/fixture/app/bank_import.py" app/bank_import.py \
    && timeout 900 claude --print --model opus --permission-mode acceptEdits "$PROMPT" > out.md 2> err.log
    echo "$?" > exit.code ) &
  pids+=($!)
done
wait "${pids[@]}"
for f in "$ROOT"/C-*/out.md; do printf '%s %s bytes\n' "$f" "$(wc -c < "$f")"; done
