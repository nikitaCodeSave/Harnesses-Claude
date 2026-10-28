#!/usr/bin/env bash
# Self-check for the L1 multi-session fixture (library lending: fines -> holds -> renewals).
# Works on fresh temp copies; never touches repo/ itself.
#   (a) pristine repo: repo tests + test_regression pass; test_f1/f2/f3/cross all fail
#   (b) reference f1 -> f2 -> f3, applied cumulatively: after step k the repo tests,
#       test_regression and test_f1..test_fk pass; after f3 test_cross passes too
#   (c) amnesic chain (reference f1 + amnesic_f2 + amnesic_f3): repo tests, regression
#       and test_f1 pass, own-feature oracles pass >= 80%; report test_cross pass/total,
#       which must sit inside the 20-60% band
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export PYTHONDONTWRITEBYTECODE=1

# The oracle runs from a directory outside any repo copy, as the benchmark runner does.
cp -r "$HERE/oracle" "$WORK/oracle"
declare -A N
for f in test_regression test_f1 test_f2 test_f3 test_cross; do
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

expect_all_pass() {  # expect_all_pass <dir> <file> <label>
  local passed total
  read -r passed total < <(oracle "$1" "$2" "$3")
  [[ "$total" == "${N[$2]}" ]] || die "$3: $2 collected $total tests, expected ${N[$2]}"
  [[ "$passed" == "$total" ]] || { cat "$WORK/$3.$2.log" >&2; die "$3: $2 passed $passed/$total"; }
  echo "  $2: $passed/$total passed"
}

expect_all_fail() {  # expect_all_fail <dir> <file> <label>
  local passed total
  read -r passed total < <(oracle "$1" "$2" "$3")
  [[ "$total" == "${N[$2]}" ]] || die "$3: $2 collected $total tests, expected ${N[$2]}"
  [[ "$passed" == "0" ]] || die "$3: $passed/$total of $2 pass before the feature exists"
  echo "  $2: 0/$total passed (all fail, as required)"
}

expect_mostly_pass() {  # expect_mostly_pass <dir> <file> <label>  (>= 80%)
  local passed total
  read -r passed total < <(oracle "$1" "$2" "$3")
  [[ "$total" == "${N[$2]}" ]] || die "$3: $2 collected $total tests, expected ${N[$2]}"
  (( passed * 100 >= total * 80 )) || die "$3: $2 passed only $passed/$total (< 80%)"
  echo "  $2: $passed/$total passed"
}

echo "(a) pristine"
P="$(fresh pristine)"
repo_tests "$P" pristine
expect_all_pass "$P" test_regression pristine
for f in test_f1 test_f2 test_f3 test_cross; do expect_all_fail "$P" "$f" pristine; done

echo "(b) reference chain"
R="$(fresh reference)"
done_features=()
for k in 1 2 3; do
  echo " after f$k"
  apply "$R" "f$k" "reference f$k"
  done_features+=("test_f$k")
  repo_tests "$R" "ref$k"
  expect_all_pass "$R" test_regression "ref$k"
  for f in "${done_features[@]}"; do expect_all_pass "$R" "$f" "ref$k"; done
done
expect_all_pass "$R" test_cross ref3

echo "(c) amnesic chain"
A="$(fresh amnesic)"
apply "$A" f1 "amnesic base"
echo " after amnesic f2"
apply "$A" amnesic_f2 "amnesic f2"
repo_tests "$A" am2
expect_all_pass "$A" test_regression am2
expect_all_pass "$A" test_f1 am2
expect_mostly_pass "$A" test_f2 am2
echo " after amnesic f3"
apply "$A" amnesic_f3 "amnesic f3"
repo_tests "$A" am3
expect_all_pass "$A" test_regression am3
expect_all_pass "$A" test_f1 am3
expect_mostly_pass "$A" test_f2 am3
expect_mostly_pass "$A" test_f3 am3
read -r cross_passed cross_total < <(oracle "$A" test_cross am3)
[[ "$cross_total" == "${N[test_cross]}" ]] \
  || die "amnesic: test_cross collected $cross_total tests, expected ${N[test_cross]}"
echo "  test_cross: $cross_passed/$cross_total passed"
(( cross_passed * 100 >= cross_total * 20 && cross_passed * 100 <= cross_total * 60 )) \
  || die "amnesic cross $cross_passed/$cross_total is outside the 20-60% band"

echo "VALIDATE OK amnesic_cross=$cross_passed/$cross_total"
