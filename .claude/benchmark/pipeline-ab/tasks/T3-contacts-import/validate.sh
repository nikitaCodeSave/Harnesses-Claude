#!/usr/bin/env bash
# Self-check of the T3 fixture. Works on fresh temp copies; never touches repo/.
#   (a) pristine repo: repo tests pass, regression oracle passes, no acceptance test passes
#   (b) repo + reference.patch: repo tests and the whole oracle pass
#   (c) repo + naive.patch: repo tests and regression pass; acceptance pass rate printed
#       and required to lie in [30%, 70%]
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY="${PYTHON:-python3}"
export PYTHONDONTWRITEBYTECODE=1
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() { echo "VALIDATE FAIL: $*" >&2; exit 1; }

cp -r "$HERE/oracle" "$WORK/oracle"
ORACLE="$WORK/oracle"

# workspace <name> [patch] -> prints path of a fresh repo copy, patch applied
workspace() {
  local dir="$WORK/ws-$1"
  cp -r "$HERE/repo" "$dir"
  find "$dir" -name __pycache__ -prune -exec rm -rf {} +
  if [[ $# -ge 2 ]]; then
    (cd "$dir" && patch -p1 -s --forward --no-backup-if-mismatch < "$2") \
      || fail "$(basename "$2") does not apply"
  fi
  echo "$dir"
}

repo_tests() {  # <workspace> -- the repo's own suite, run with its own pytest config
  (cd "$1" && "$PY" -m pytest -q -p no:cacheprovider >"$WORK/last.log" 2>&1) \
    || { cat "$WORK/last.log" >&2; fail "repo tests fail in $(basename "$1")"; }
}

# oracle <workspace> <target> -> prints "passed total"; runs from outside the repo
oracle() {
  local junit="$WORK/junit-$RANDOM.xml"
  (cd "$WORK" && PYTHONPATH="$1/src" "$PY" -m pytest "$2" -q -p no:cacheprovider \
      --junitxml="$junit" >"$WORK/last.log" 2>&1) || true
  [[ -s "$junit" ]] || { cat "$WORK/last.log" >&2; fail "no junit report for $2"; }
  "$PY" - "$junit" <<'EOF'
import sys
import xml.etree.ElementTree as ET

root = ET.parse(sys.argv[1]).getroot()
suites = [root] if root.tag == "testsuite" else root.findall("testsuite")
total = bad = 0
for suite in suites:
    total += int(suite.get("tests", 0))
    bad += sum(int(suite.get(k, 0)) for k in ("failures", "errors", "skipped"))
print(total - bad, total)
EOF
}

ACC="$ORACLE/test_acceptance.py"
REG="$ORACLE/test_regression.py"
N_ACC=$(grep -c '^def test_' "$ACC")
N_REG=$(grep -c '^def test_' "$REG")

# (a) pristine
ws=$(workspace pristine)
repo_tests "$ws"
res=$(oracle "$ws" "$REG"); read -r p t <<<"$res"
[[ $p -eq $t && $t -eq $N_REG ]] || fail "pristine: regression $p/$t (expected $N_REG/$N_REG)"
res=$(oracle "$ws" "$ACC"); read -r p t <<<"$res"
[[ $p -eq 0 ]] || fail "pristine: $p acceptance tests pass (expected 0)"
echo "(a) pristine: repo tests ok, regression $N_REG/$N_REG, acceptance passing 0"

# (b) reference
ws=$(workspace reference "$HERE/reference/reference.patch")
repo_tests "$ws"
res=$(oracle "$ws" "$ORACLE"); read -r p t <<<"$res"
[[ $p -eq $t && $t -eq $((N_ACC + N_REG)) ]] \
  || { cat "$WORK/last.log" >&2; fail "reference: oracle $p/$t (expected $((N_ACC + N_REG)))"; }
echo "(b) reference: repo tests ok, oracle $p/$t"

# (c) naive
ws=$(workspace naive "$HERE/reference/naive.patch")
repo_tests "$ws"
res=$(oracle "$ws" "$REG"); read -r p t <<<"$res"
[[ $p -eq $t ]] || fail "naive: regression $p/$t"
res=$(oracle "$ws" "$ACC"); read -r p t <<<"$res"
[[ $t -eq $N_ACC ]] || fail "naive: acceptance collected $t tests (expected $N_ACC)"
echo "(c) naive: repo tests ok, regression ok, acceptance $p/$t"
(( p * 100 >= 30 * t && p * 100 <= 70 * t )) || fail "naive acceptance $p/$t outside 30-70%"

echo "VALIDATE OK naive_acceptance=$p/$t"
