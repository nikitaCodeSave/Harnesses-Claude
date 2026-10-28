#!/usr/bin/env bash
# pipeline-ab: vanilla (V) vs research flow (R) vs Pocock (P) on hidden-oracle tasks.
#
#   ./run.sh calibrate        — oracle sizes from reference solutions (once per task)
#   ./run.sh pilot            — first task x V,R,P x rep 1
#   ./run.sh full [N]         — every task x V,R,P x reps 1..N (default 3)
#   ./run.sh score            — (re)score every finished run
#   ./run.sh summary          — min / median / max table
#
# PAB_JOBS runs in parallel (default 3); workspaces go to PAB_WORK (default /tmp/pab-work).
set -uo pipefail

R="$(cd "$(dirname "$0")" && pwd)"
JOBS="${PAB_JOBS:-3}"
TASKS=$(cd "$R/tasks" && ls -d T*/ | tr -d /)

one() { # task arm rep
  if [ -f "${PAB_RESULTS:-$R/results}/$1/$2-$3/score.json" ]; then echo "skip  $1 $2-$3 (scored)"; return; fi
  echo "[$(date +%H:%M:%S)] start $1 $2-$3"
  python3 "$R/drive.py" --task "$1" --arm "$2" --rep "$3" && python3 "$R/score.py" run "$1" "$2-$3"
  echo "[$(date +%H:%M:%S)] end   $1 $2-$3"
}
export -f one; export R

matrix() { # reps tasks...
  local n="$1"; shift
  for i in $(seq 1 "$n"); do for t in "$@"; do for a in ${PAB_ARMS:-V R P}; do echo "$t $a $i"; done; done; done
}

case "${1:-}" in
  calibrate) for t in $TASKS; do python3 "$R/score.py" calibrate "$t"; done ;;
  pilot) matrix 1 "$(echo "$TASKS" | head -1)" | xargs -P "$JOBS" -L1 bash -c 'one "$0" "$1" "$2"' ;;
  full) matrix "${2:-3}" $TASKS | xargs -P "$JOBS" -L1 bash -c 'one "$0" "$1" "$2"' ;;
  score) for m in "${PAB_RESULTS:-$R/results}"/*/*/meta.json; do d=$(dirname "$m"); python3 "$R/score.py" run "$(basename "$(dirname "$d")")" "$(basename "$d")"; done ;;
  summary) python3 "$R/score.py" summary ;;
  *) sed -n '2,10p' "$0"; exit 2 ;;
esac
