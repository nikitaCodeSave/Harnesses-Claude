#!/usr/bin/env bash
# A/B/C: ваниль vs harness vs harness+§8 на задаче silent-wrong класса (PreToolUse guard).
# Оракул — held-out `test-system-guard.sh` (239 кейсов), агенту не показывается.
#
#   ./run.sh runs     — прогнать все плечи (9 авторских сессий + 3 refute + 3 fix)
#   ./run.sh score    — прогнать оракул по собранным артефактам
#   ./run.sh all
set -uo pipefail

R="$(cd "$(dirname "$0")" && pwd)"
WORK="${GUARD_AB_WORK:-/tmp/claude-1000/-home-nikita-PROJECTS-Harnesses-Claude/fd322c86-f8c9-43a2-944b-8e1236dbd600/scratchpad/ab/runs}"
N="${GUARD_AB_N:-3}"
MODEL="${GUARD_AB_MODEL:-claude-opus-5}"
TIMEOUT="${GUARD_AB_TIMEOUT:-1800}"
mkdir -p "$WORK" "$R/results"

# Единые permissions для всех плеч: writes без промптов, Bash разрешён (агенту нужен
# runnable-оракул), деструктив закрыт deny-правилами — safe-mode отключает хуки, так что
# глобальный system-guard в этих сессиях не работает.
mk_settings() {
  cat > "$1/settings.json" <<'EOF'
{
  "permissions": {
    "defaultMode": "acceptEdits",
    "allow": ["Read", "Write", "Edit", "Glob", "Grep", "Bash"],
    "deny": ["Bash(rm:*)", "Bash(sudo:*)", "Bash(dd:*)", "Bash(mkfs:*)", "Bash(mkfs.ext4:*)",
             "Bash(shutdown:*)", "Bash(reboot:*)", "Bash(chmod:*)", "Bash(chown:*)"]
  }
}
EOF
}
# Рефьютеру писать нечем — он судит, а не правит.
mk_settings_ro() {
  cat > "$1/settings-ro.json" <<'EOF'
{
  "permissions": {
    "defaultMode": "acceptEdits",
    "allow": ["Read", "Glob", "Grep", "Bash"],
    "deny": ["Write", "Edit", "Bash(rm:*)", "Bash(sudo:*)", "Bash(dd:*)", "Bash(mkfs:*)",
             "Bash(mkfs.ext4:*)", "Bash(shutdown:*)", "Bash(reboot:*)"]
  }
}
EOF
}

prep() { # arm i -> печатает путь run-dir
  local d="$WORK/$1-$2"
  rm -rf "$d" 2>/dev/null; mkdir -p "$d"
  cp "$R/TASK.md" "$d/"; mk_settings "$d"; mk_settings_ro "$d"
  printf '%s' "$d"
}

author() { # run-dir arm i  — авторская сессия
  local d="$1" arm="$2" i="$3" prompt
  prompt="$d/prompt.txt"
  if [ "$arm" = "A" ]; then
    cat "$R/TASK.md" > "$prompt"
  else
    { cat "$R/HARNESS.md"; printf '\n\n---\n\n'; cat "$R/TASK.md"; } > "$prompt"
  fi
  ( cd "$d" && timeout "$TIMEOUT" claude --print --safe-mode --model "$MODEL" \
      --settings ./settings.json < "$prompt" > "$R/results/$arm-$i.author.log" 2>&1 )
  [ -f "$d/guard.sh" ] && cp "$d/guard.sh" "$R/results/$arm-$i.guard.sh"
}

refute() { # run-dir i — независимый свежий контекст, ничего не знает об авторской сессии
  local d="$1" i="$2"
  cp "$R/REFUTE.md" "$d/"
  ( cd "$d" && timeout "$TIMEOUT" claude --print --safe-mode --model "$MODEL" \
      --settings ./settings-ro.json < "$R/REFUTE.md" > "$R/results/C-$i.refute.log" 2>&1 )
}

fixup() { # run-dir i — автор триажирует находки рефьютера и правит
  local d="$1" i="$2" p="$d/fix-prompt.txt"
  {
    cat "$R/HARNESS.md"; printf '\n\n---\n\n'; cat "$R/TASK.md"
    printf '\n\n---\n\n# Отчёт независимого ревьюера о твоей реализации\n\n'
    printf 'Свежий контекст, который твоих рассуждений не видел, прогнал `guard.sh` живыми вызовами.\n'
    printf 'Триажируй каждую находку: воспроизведи её сам, и если она реальна — исправь `guard.sh`.\n'
    printf 'Находку, которая не воспроизводится или противоречит ТЗ, отклони с одной фразой почему.\n\n'
    cat "$R/results/C-$i.refute.log"
    printf '\n\nКогда закончишь — ответь одной строкой: FIXED.\n'
  } > "$p"
  ( cd "$d" && timeout "$TIMEOUT" claude --print --safe-mode --model "$MODEL" \
      --settings ./settings.json < "$p" > "$R/results/C-$i.fix.log" 2>&1 )
  [ -f "$d/guard.sh" ] && cp "$d/guard.sh" "$R/results/C-$i.guard.sh"
}

do_runs() {
  echo "== фаза 1: авторские сессии (A,B,C × $N) =="
  for i in $(seq 1 "$N"); do
    for arm in A B C; do
      d=$(prep "$arm" "$i"); author "$d" "$arm" "$i" &
    done
  done
  wait
  echo "== фаза 2: независимый рефьютер (только плечо C) =="
  for i in $(seq 1 "$N"); do refute "$WORK/C-$i" "$i" & done
  wait
  echo "== фаза 3: автор чинит по находкам (только плечо C) =="
  for i in $(seq 1 "$N"); do fixup "$WORK/C-$i" "$i" & done
  wait
  echo "готово; артефакты в $R/results"
}

do_score() {
  echo "arm run  PASS FAIL  (из 239)"
  for arm in A B C; do
    for i in $(seq 1 "$N"); do
      g="$R/results/$arm-$i.guard.sh"
      if [ ! -f "$g" ]; then printf '%-3s %-4s  ARTEFACT MISSING\n' "$arm" "$i"; continue; fi
      out=$(GUARD="$g" timeout 1800 bash "$R/oracle.sh" 2>/dev/null | tail -1)
      p=$(printf '%s' "$out" | grep -o 'PASS=[0-9]*' | cut -d= -f2)
      f=$(printf '%s' "$out" | grep -o 'FAIL=[0-9]*' | cut -d= -f2)
      printf '%-3s %-4s %4s %4s\n' "$arm" "$i" "${p:-?}" "${f:-?}"
      GUARD="$g" timeout 1800 bash "$R/oracle.sh" > "$R/results/$arm-$i.oracle.txt" 2>&1
    done
  done
}

case "${1:-all}" in
  runs) do_runs ;;
  score) do_score ;;
  all) do_runs; do_score ;;
  *) echo "usage: $0 {runs|score|all}"; exit 2 ;;
esac
