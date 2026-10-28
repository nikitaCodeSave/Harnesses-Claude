#!/usr/bin/env bash
# Validate the T2 fixture on fresh temp copies of repo/:
#   (a) pristine:          repo tests pass, regression oracle all pass, no acceptance test passes
#   (b) + reference.patch: repo tests pass, whole oracle passes
#   (c) + naive.patch:     repo tests pass; acceptance pass rate reported (must be 30%..70%)
# Prints `VALIDATE OK naive_acceptance=<p>/<n>` or exits non-zero.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY="${PYTHON:-python3}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export PYTHONDONTWRITEBYTECODE=1

fail() { echo "VALIDATE FAIL: $*" >&2; exit 1; }

command -v patch >/dev/null || fail "patch(1) not found"

# The oracle runs from a directory outside any repo copy, like the real scorer.
cp -r "$HERE/oracle" "$TMP/oracle"
mkdir "$TMP/run"

# fresh <name> [patch] -> path of a new copy of repo/, optionally patched
fresh() {
  local dst="$TMP/$1"
  cp -r "$HERE/repo" "$dst"
  if [[ -n "${2:-}" ]]; then
    (cd "$dst" && patch -p1 --batch --quiet --no-backup-if-mismatch < "$2") \
      || fail "$(basename "$2") does not apply to repo/"
  fi
  echo "$dst"
}

repo_tests() {
  (cd "$1" && "$PY" -m pytest -q -p no:cacheprovider >"$TMP/$2.repo.log" 2>&1) \
    || { cat "$TMP/$2.repo.log" >&2; fail "$2: repo tests do not pass"; }
}

# oracle <workspace> <test file> <label>  -> prints "<passed> <total>"
oracle() {
  local xml="$TMP/$3.xml"
  (cd "$TMP/run" && PYTHONPATH="$1/src" "$PY" -m pytest "$TMP/oracle/$2" -q \
      -p no:cacheprovider --junitxml="$xml" >"$TMP/$3.log" 2>&1) || true
  [[ -f "$xml" ]] || { cat "$TMP/$3.log" >&2; fail "$3: pytest produced no report"; }
  "$PY" - "$xml" <<'EOF'
import sys, xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
s = root if root.tag == "testsuite" else root.find("testsuite")
total = int(s.get("tests"))
bad = int(s.get("failures")) + int(s.get("errors")) + int(s.get("skipped"))
print(total - bad, total)
EOF
}

# (a) pristine ---------------------------------------------------------------
P="$(fresh pristine)"
repo_tests "$P" pristine
out="$(oracle "$P" test_regression.py pristine-regression)"; read -r rp rn <<<"$out"
(( rn >= 10 && rp == rn )) || { cat "$TMP/pristine-regression.log" >&2; fail "pristine: regression $rp/$rn"; }
out="$(oracle "$P" test_acceptance.py pristine-acceptance)"; read -r ap an <<<"$out"
(( an >= 25 && ap == 0 )) || { cat "$TMP/pristine-acceptance.log" >&2; fail "pristine: acceptance $ap/$an (want 0 passed)"; }
echo "pristine:  repo tests ok, regression $rp/$rn, acceptance $ap/$an"

# (b) reference --------------------------------------------------------------
R="$(fresh reference "$HERE/reference/reference.patch")"
repo_tests "$R" reference
out="$(oracle "$R" test_regression.py reference-regression)"; read -r rp rn <<<"$out"
out="$(oracle "$R" test_acceptance.py reference-acceptance)"; read -r ap an2 <<<"$out"
(( rp == rn )) || { cat "$TMP/reference-regression.log" >&2; fail "reference: regression $rp/$rn"; }
(( ap == an2 && an2 == an )) || { cat "$TMP/reference-acceptance.log" >&2; fail "reference: acceptance $ap/$an2"; }
echo "reference: repo tests ok, regression $rp/$rn, acceptance $ap/$an2"

# (c) naive ------------------------------------------------------------------
N="$(fresh naive "$HERE/reference/naive.patch")"
repo_tests "$N" naive
out="$(oracle "$N" test_regression.py naive-regression)"; read -r rp rn <<<"$out"
out="$(oracle "$N" test_acceptance.py naive-acceptance)"; read -r np nn <<<"$out"
echo "naive:     repo tests ok, regression $rp/$rn, acceptance $np/$nn"
(( nn == an && np * 100 >= 30 * nn && np * 100 <= 70 * nn )) \
  || fail "naive acceptance $np/$nn is outside the 30%..70% band"

echo "VALIDATE OK naive_acceptance=$np/$nn"
