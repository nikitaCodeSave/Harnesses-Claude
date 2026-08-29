#!/usr/bin/env bash
# Пересдача плеча C для прогонов, чей рефьютер отвалился с пустым отчётом.
# Стартует от сохранённой pre-версии, идёт ПОСЛЕДОВАТЕЛЬНО (параллельный старт трёх
# сессий в одну секунду и был причиной отказа).
set -uo pipefail
R="$(cd "$(dirname "$0")" && pwd)"
WORK=/tmp/claude-1000/-home-nikita-PROJECTS-Harnesses-Claude/fd322c86-f8c9-43a2-944b-8e1236dbd600/scratchpad/ab/runs
for i in "$@"; do
  d="$WORK/C-$i"
  cp "$R/results/Cpre-$i.guard.sh" "$d/guard.sh"
  cp "$R/REFUTE.md" "$d/"
  echo "== refute C-$i =="
  ( cd "$d" && timeout 2400 claude --print --safe-mode --model claude-opus-5 \
      --settings ./settings-ro.json < "$R/REFUTE.md" > "$R/results/C-$i.refute.log" 2>&1 )
  echo "   $(wc -c < "$R/results/C-$i.refute.log") байт, $(grep -o 'DEFECTS([0-9]*)' "$R/results/C-$i.refute.log" | tail -1)"
  [ -s "$R/results/C-$i.refute.log" ] || { echo "   ПУСТО — пропускаю fix"; continue; }
  p="$d/fix-prompt.txt"
  {
    cat "$R/HARNESS.md"; printf '\n\n---\n\n'; cat "$R/TASK.md"
    printf '\n\n---\n\n# Отчёт независимого ревьюера о твоей реализации\n\n'
    printf 'Свежий контекст, который твоих рассуждений не видел, прогнал `guard.sh` живыми вызовами.\n'
    printf 'Триажируй каждую находку: воспроизведи её сам, и если она реальна — исправь `guard.sh`.\n'
    printf 'Находку, которая не воспроизводится или противоречит ТЗ, отклони с одной фразой почему.\n\n'
    cat "$R/results/C-$i.refute.log"
    printf '\n\nКогда закончишь — ответь одной строкой: FIXED.\n'
  } > "$p"
  echo "== fix C-$i =="
  ( cd "$d" && timeout 2400 claude --print --safe-mode --model claude-opus-5 \
      --settings ./settings.json < "$p" > "$R/results/C-$i.fix.log" 2>&1 )
  cp "$d/guard.sh" "$R/results/C-$i.guard.sh"
  echo "   fix: $(wc -c < "$R/results/C-$i.fix.log") байт"
done
