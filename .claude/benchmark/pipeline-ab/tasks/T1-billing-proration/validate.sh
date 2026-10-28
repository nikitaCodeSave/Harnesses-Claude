#!/usr/bin/env bash
# Self-check for the T1 fixture. Works on fresh temp copies; never touches repo/ itself.
#   (a) pristine repo: repo tests pass, regression oracle passes, every acceptance test fails
#   (b) repo + reference.patch: repo tests and the whole oracle pass
#   (c) repo + naive.patch: repo tests pass; report acceptance pass/total (must be 30-70%)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export PYTHONDONTWRITEBYTECODE=1

# The oracle runs from a directory outside any repo copy, as the benchmark runner does.
cp -r "$HERE/oracle" "$WORK/oracle"
N_ACC="$(grep -c '^def test_' "$HERE/oracle/test_acceptance.py")"
N_REG="$(grep -c '^def test_' "$HERE/oracle/test_regression.py")"

die() { echo "VALIDATE FAIL: $*" >&2; exit 1; }

fresh() {  # fresh <name> [patch] -> prints path of a new repo copy, patched if asked
  local dir="$WORK/$1"
  cp -r "$HERE/repo" "$dir"
  if [[ $# -ge 2 ]]; then
    (cd "$dir" && patch -p1 --batch --quiet < "$2") >&2 || die "$1: patch $2 does not apply"
  fi
  echo "$dir"
}

repo_tests() {  # repo_tests <dir> <label>
  (cd "$1" && python3 -m pytest -q -p no:cacheprovider) > "$WORK/$2.repo.log" 2>&1 \
    || { cat "$WORK/$2.repo.log" >&2; die "$2: repo tests fail"; }
}

oracle() {  # oracle <dir> <file> <label> -> prints "<passed> <total>"
  local xml="$WORK/$3.$2.xml"
  (cd "$WORK" && PYTHONPATH="$1/src" python3 -m pytest "oracle/$2.py" -q -p no:cacheprovider \
    --rootdir="$WORK" --junitxml="$xml") > "$WORK/$3.$2.log" 2>&1 || true
  [[ -s "$xml" ]] || { cat "$WORK/$3.$2.log" >&2; die "$3: pytest produced no report for $2"; }
  python3 - "$xml" <<'PY'
import sys
import xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
suites = [root] if root.tag == "testsuite" else list(root.iter("testsuite"))
total = sum(int(s.get("tests", 0)) for s in suites)
bad = sum(int(s.get(k, 0)) for s in suites for k in ("failures", "errors", "skipped"))
print(total - bad, total)
PY
}

expect_all_pass() {  # expect_all_pass <dir> <file> <expected_total> <label>
  read -r passed total < <(oracle "$1" "$2" "$4")
  [[ "$total" == "$3" ]] || die "$4: $2 collected $total tests, expected $3"
  [[ "$passed" == "$total" ]] || { cat "$WORK/$4.$2.log" >&2; die "$4: $2 passed $passed/$total"; }
  echo "  $2: $passed/$total passed"
}

echo "(a) pristine"
PRISTINE="$(fresh pristine)"
repo_tests "$PRISTINE" pristine
echo "  repo tests: pass"
expect_all_pass "$PRISTINE" test_regression "$N_REG" pristine
read -r passed total < <(oracle "$PRISTINE" test_acceptance pristine)
[[ "$total" == "$N_ACC" ]] || die "pristine: acceptance collected $total tests, expected $N_ACC"
[[ "$passed" == "0" ]] || die "pristine: $passed acceptance tests pass before the feature exists"
echo "  test_acceptance: 0/$total passed (all fail, as required)"

echo "(b) reference"
REF="$(fresh reference "$HERE/reference/reference.patch")"
repo_tests "$REF" reference
echo "  repo tests: pass"
expect_all_pass "$REF" test_regression "$N_REG" reference
expect_all_pass "$REF" test_acceptance "$N_ACC" reference

echo "(c) naive"
NAIVE="$(fresh naive "$HERE/reference/naive.patch")"
repo_tests "$NAIVE" naive
echo "  repo tests: pass"
read -r reg_passed reg_total < <(oracle "$NAIVE" test_regression naive)
echo "  test_regression: $reg_passed/$reg_total passed"
read -r naive_passed naive_total < <(oracle "$NAIVE" test_acceptance naive)
[[ "$naive_total" == "$N_ACC" ]] || die "naive: acceptance collected $naive_total tests, expected $N_ACC"
echo "  test_acceptance: $naive_passed/$naive_total passed"
(( naive_passed * 100 >= naive_total * 30 && naive_passed * 100 <= naive_total * 70 )) \
  || die "naive acceptance $naive_passed/$naive_total is outside the 30-70% band"

echo "VALIDATE OK naive_acceptance=$naive_passed/$naive_total"
