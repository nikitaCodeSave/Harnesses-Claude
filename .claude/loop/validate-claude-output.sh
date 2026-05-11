#!/usr/bin/env bash
# validate-claude-output.sh — verify `claude --print --output-format json`
# emits the 8 fields headless-runner.sh extracts (lines 147-154).
#
# Tripwire against CLI version drift. Run manually after `claude` upgrade.
# Fails loud if any field disappears or renames.
#
# Usage:
#   validate-claude-output.sh                        # live mode: costs subscription tokens
#   validate-claude-output.sh --from-file <path>     # static mode: no Claude invocation
#   validate-claude-output.sh --prompt "<text>"      # custom prompt for live mode (default: "ok")

set -uo pipefail

MODE="live"
FROM_FILE=""
PROMPT="ok"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --from-file) MODE="file"; FROM_FILE="${2:-}"; shift 2 ;;
        --live)      MODE="live"; shift ;;
        --prompt)    PROMPT="${2:-}"; shift 2 ;;
        -h|--help)   sed -n '2,/^$/p' "$0"; exit 0 ;;
        *)           echo "Unknown arg: $1" >&2; exit 2 ;;
    esac
done

command -v jq >/dev/null 2>&1 || { echo "FAIL: 'jq' required" >&2; exit 2; }

# Mirror headless-runner.sh:147-154 jq paths.
REQUIRED_FIELDS=(
    ".num_turns"
    ".total_cost_usd"
    ".usage.input_tokens"
    ".usage.output_tokens"
    ".usage.cache_creation_input_tokens"
    ".usage.cache_read_input_tokens"
    ".result"
    ".stop_reason"
)

if [[ "$MODE" == "file" ]]; then
    [[ -z "$FROM_FILE" || ! -f "$FROM_FILE" ]] && { echo "FAIL: --from-file path missing: '$FROM_FILE'" >&2; exit 2; }
    JSON_FILE="$FROM_FILE"
else
    command -v claude >/dev/null 2>&1 || { echo "FAIL: 'claude' CLI not found in PATH" >&2; exit 2; }
    JSON_FILE="$(mktemp -t validate-claude-XXXXXX.json)"
    trap 'rm -f "$JSON_FILE"' EXIT
    echo "[live] Invoking 'claude --print --output-format json' (subscription tokens billed)..." >&2
    printf "%s" "$PROMPT" | claude --print --output-format json --no-session-persistence \
        > "$JSON_FILE" 2>/dev/null
fi

jq -e . "$JSON_FILE" >/dev/null 2>&1 || { echo "FAIL: not valid JSON: '$JSON_FILE'" >&2; exit 1; }

MISSING=()
for field in "${REQUIRED_FIELDS[@]}"; do
    val=$(jq -r "$field // \"<missing>\"" "$JSON_FILE")
    [[ "$val" == "<missing>" ]] && MISSING+=("$field")
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo "FAIL: missing fields in 'claude --output-format json' output:"
    printf '  - %s\n' "${MISSING[@]}"
    echo "Update headless-runner.sh jq expressions accordingly."
    exit 1
fi

echo "OK: all ${#REQUIRED_FIELDS[@]} fields present."
exit 0
