#!/usr/bin/env bash
# Bash test for validate-claude-output.sh.
# Runs --from-file mode on synthetic JSON fixtures.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/validate-claude-output.sh"
TMPDIR_LOCAL="$(mktemp -d -t test-validate-claude-XXXXXX)"
trap 'rm -rf "$TMPDIR_LOCAL"' EXIT

PASS=0; FAIL=0
assert_exit() {
    local expected="$1" actual="$2" label="$3"
    if [[ "$expected" == "$actual" ]]; then
        echo "  PASS: $label"; PASS=$((PASS+1))
    else
        echo "  FAIL: $label (expected exit=$expected, got exit=$actual)"; FAIL=$((FAIL+1))
    fi
}

# Fixture A: all 8 fields present.
cat > "$TMPDIR_LOCAL/valid.json" <<'JSON'
{
  "num_turns": 5,
  "total_cost_usd": 0.123,
  "usage": {
    "input_tokens": 10,
    "output_tokens": 100,
    "cache_creation_input_tokens": 200,
    "cache_read_input_tokens": 300
  },
  "result": "done",
  "stop_reason": "end_turn"
}
JSON

# Fixture B: missing total_cost_usd.
cat > "$TMPDIR_LOCAL/missing_cost.json" <<'JSON'
{
  "num_turns": 5,
  "usage": {
    "input_tokens": 10,
    "output_tokens": 100,
    "cache_creation_input_tokens": 200,
    "cache_read_input_tokens": 300
  },
  "result": "done",
  "stop_reason": "end_turn"
}
JSON

# Fixture C: missing nested usage.input_tokens.
cat > "$TMPDIR_LOCAL/missing_input.json" <<'JSON'
{
  "num_turns": 5,
  "total_cost_usd": 0.123,
  "usage": {
    "output_tokens": 100,
    "cache_creation_input_tokens": 200,
    "cache_read_input_tokens": 300
  },
  "result": "done",
  "stop_reason": "end_turn"
}
JSON

# Fixture D: malformed JSON.
echo "{not valid json" > "$TMPDIR_LOCAL/bad.json"

# Test 1: valid JSON → exit 0.
bash "$SCRIPT" --from-file "$TMPDIR_LOCAL/valid.json" >/dev/null 2>&1
assert_exit 0 $? "valid JSON exits 0"

# Test 2: missing top-level field → exit 1.
bash "$SCRIPT" --from-file "$TMPDIR_LOCAL/missing_cost.json" >/dev/null 2>&1
assert_exit 1 $? "missing .total_cost_usd exits 1"

# Test 3: missing nested field → exit 1.
bash "$SCRIPT" --from-file "$TMPDIR_LOCAL/missing_input.json" >/dev/null 2>&1
assert_exit 1 $? "missing .usage.input_tokens exits 1"

# Test 4: malformed JSON → exit 1.
bash "$SCRIPT" --from-file "$TMPDIR_LOCAL/bad.json" >/dev/null 2>&1
assert_exit 1 $? "malformed JSON exits 1"

# Test 5: nonexistent path → exit 2.
bash "$SCRIPT" --from-file "$TMPDIR_LOCAL/nope.json" >/dev/null 2>&1
assert_exit 2 $? "nonexistent path exits 2"

# Test 6: unknown arg → exit 2.
bash "$SCRIPT" --bogus-flag >/dev/null 2>&1
assert_exit 2 $? "unknown arg exits 2"

echo ""
echo "=== Test summary: $PASS pass, $FAIL fail ==="
[[ $FAIL -eq 0 ]]
