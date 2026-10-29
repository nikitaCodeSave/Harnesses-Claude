#!/usr/bin/env bash
# Self-check for the L2 accumulation fixture (library lending: F1..F8). Conditions are the ones
# preregistered in ../../README.md, «Стенд накопления L2». Works on fresh temp copies; never touches repo/.
#   (a) pristine repo: repo tests + test_regression pass; every other oracle fails entirely
#   (b) reference f1 -> f8, applied cumulatively: after step k the repo tests, test_regression and
#       test_f1..test_fk pass; after f8 test_cross and test_reversal pass too
#   (c) amnesic variant (reference + amnesic_f8: every "for later" decision replaced by a default):
#       test_fk >= 80% on every feature, test_cross inside the 20-60% band
#   (d) stale variant (reference + stale_f8: the first versions of the three changed decisions):
#       test_cross 100%, test_reversal <= 25%
# The variants are judged by the oracles only: their repo tests encode the reference decisions.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export PYTHONDONTWRITEBYTECODE=1

FEATURES=(f1 f2 f3 f4 f5 f6 f7 f8)
ORACLES=(test_regression test_f1 test_f2 test_f3 test_f4 test_f5 test_f6 test_f7 test_f8 test_cross test_reversal)

# The oracle runs from a directory outside any repo copy, as the benchmark runner does.
cp -r "$HERE/oracle" "$WORK/oracle"
declare -A N
for f in "${ORACLES[@]}"; do
  N[$f]="$(grep -c '^def test_' "$HERE/oracle/$f.py")"
done

die() { echo "VALIDATE FAIL: $*" >&2; exit 1; }

fresh() {  # fresh <name> -> prints path of a new pristine repo copy
  local dir="$WORK/$1"
  cp -r "$HERE/repo" "$dir"
  echo "$dir"
}

apply() {  # apply <dir> <patch-name> <label>
  (cd "$1" && patch -p1 --batch --quiet < "$HERE/reference/$2.patch") >&2 \
    || die "$3: reference/$2.patch does not apply"
}

repo_tests() {  # repo_tests <dir> <label>
  (cd "$1" && python3 -m pytest -q -p no:cacheprovider) > "$WORK/$2.repo.log" 2>&1 \
    || { cat "$WORK/$2.repo.log" >&2; die "$2: repo tests fail"; }
  echo "  repo tests: pass"
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

count() {  # count <dir> <file> <label> -> "<passed> <total>", total checked against the file
  local passed total
  read -r passed total < <(oracle "$1" "$2" "$3")
  [[ "$total" == "${N[$2]}" ]] || die "$3: $2 collected $total tests, expected ${N[$2]}"
  echo "$passed $total"
}

expect_all_pass() {  # expect_all_pass <dir> <file> <label>
  local passed total
  read -r passed total < <(count "$@")
  [[ "$passed" == "$total" ]] || { cat "$WORK/$3.$2.log" >&2; die "$3: $2 passed $passed/$total"; }
  echo "  $2: $passed/$total passed"
}

expect_all_fail() {  # expect_all_fail <dir> <file> <label>
  local passed total
  read -r passed total < <(count "$@")
  [[ "$passed" == "0" ]] || die "$3: $passed/$total of $2 pass before the feature exists"
  echo "  $2: 0/$total passed (all fail, as required)"
}

expect_mostly_pass() {  # expect_mostly_pass <dir> <file> <label>  (>= 80%)
  local passed total
  read -r passed total < <(count "$@")
  (( passed * 100 >= total * 80 )) || { cat "$WORK/$3.$2.log" >&2; die "$3: $2 passed only $passed/$total (< 80%)"; }
  echo "  $2: $passed/$total passed"
}

reference_chain() {  # reference_chain <dir> <label>: f1..f8 without checks
  for f in "${FEATURES[@]}"; do apply "$1" "$f" "$2 $f"; done
}

echo "(a) pristine"
P="$(fresh pristine)"
repo_tests "$P" pristine
expect_all_pass "$P" test_regression pristine
for f in "${ORACLES[@]:1}"; do expect_all_fail "$P" "$f" pristine; done

echo "(b) reference chain"
R="$(fresh reference)"
done_oracles=()
for k in 1 2 3 4 5 6 7 8; do
  echo " after f$k"
  apply "$R" "f$k" "reference f$k"
  done_oracles+=("test_f$k")
  repo_tests "$R" "ref$k"
  expect_all_pass "$R" test_regression "ref$k"
  for f in "${done_oracles[@]}"; do expect_all_pass "$R" "$f" "ref$k"; done
done
expect_all_pass "$R" test_cross ref8
expect_all_pass "$R" test_reversal ref8

echo "(c) amnesic variant"
A="$(fresh amnesic)"
reference_chain "$A" amnesic
apply "$A" amnesic_f8 "amnesic"
expect_all_pass "$A" test_regression amnesic
for k in 1 2 3 4 5 6 7 8; do expect_mostly_pass "$A" "test_f$k" amnesic; done
read -r cross_passed cross_total < <(count "$A" test_cross amnesic)
read -r rev_passed rev_total < <(count "$A" test_reversal amnesic)
echo "  test_cross: $cross_passed/$cross_total passed; test_reversal: $rev_passed/$rev_total"
(( cross_passed * 100 >= cross_total * 20 && cross_passed * 100 <= cross_total * 60 )) \
  || die "amnesic cross $cross_passed/$cross_total is outside the 20-60% band"

echo "(d) stale variant"
S="$(fresh stale)"
reference_chain "$S" stale
apply "$S" stale_f8 "stale"
expect_all_pass "$S" test_regression stale
expect_all_pass "$S" test_cross stale
read -r stale_passed stale_total < <(count "$S" test_reversal stale)
echo "  test_reversal: $stale_passed/$stale_total passed"
(( stale_passed * 100 <= stale_total * 25 )) || die "stale reversal $stale_passed/$stale_total is above 25%"

echo "VALIDATE OK amnesic_cross=$cross_passed/$cross_total amnesic_reversal=$rev_passed/$rev_total stale_reversal=$stale_passed/$stale_total"
