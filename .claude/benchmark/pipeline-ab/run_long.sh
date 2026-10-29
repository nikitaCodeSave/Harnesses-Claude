#!/usr/bin/env bash
# pipeline-ab multi-session: arms on tasks-long/*, each run = the task's features F1 -> Fn in new sessions.
#   ./run_long.sh calibrate | full [N] | score | summary
# PAB_JOBS parallel runs (default 4); PAB_ARMS (default "PL K S"); PAB_TASKS (default every tasks-long/L*);
# results-long/, workspaces /tmp/pab-work-long; user mode busy. L2: PAB_TASKS=L2 PAB_ARMS="S N" ./run_long.sh full 3
set -uo pipefail
R="$(cd "$(dirname "$0")" && pwd)"
export PAB_RESULTS="${PAB_RESULTS:-$R/results-long}" PAB_WORK="${PAB_WORK:-/tmp/pab-work-long}" PAB_USER_MODE="${PAB_USER_MODE:-busy}"
JOBS="${PAB_JOBS:-4}"
TASKS="${PAB_TASKS:-$(cd "$R/tasks-long" && ls -d L*/ | tr -d /)}"
ARMS="${PAB_ARMS:-PL K S}"
one() {
  if [ -f "$PAB_RESULTS/$1/$2-$3/score.json" ]; then echo "skip  $1 $2-$3"; return; fi
  echo "[$(date +%H:%M:%S)] start $1 $2-$3"
  python3 "$R/drive_long.py" --task "$1" --arm "$2" --rep "$3" && python3 "$R/score_long.py" run "$1" "$2-$3"
  echo "[$(date +%H:%M:%S)] end   $1 $2-$3"
}
export -f one; export R
case "${1:-}" in
  calibrate) for t in $TASKS; do python3 "$R/score_long.py" calibrate "$t"; done ;;
  full) for i in $(seq 1 "${2:-3}"); do for a in $ARMS; do for t in $TASKS; do echo "$t $a $i"; done; done; done \
          | xargs -P "$JOBS" -L1 bash -c 'one "$0" "$1" "$2"' ;;
  score) for m in "$PAB_RESULTS"/*/*/meta.json; do d=$(dirname "$m"); python3 "$R/score_long.py" run "$(basename "$(dirname "$d")")" "$(basename "$d")"; done ;;
  summary) python3 "$R/score_long.py" summary ;;
  *) sed -n '2,4p' "$0"; exit 2 ;;
esac
