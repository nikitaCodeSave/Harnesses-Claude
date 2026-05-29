#!/usr/bin/env bash
# llm-judge.sh — spawn neutral Claude judge для T/B residual scoring (47 pts).
#
# Не инжектируется harness — judge оценивает deliverable as-is. Использует
# `claude --print --output-format json` для structured output.
#
# Usage:
#   llm-judge.sh --clone-dir <dir> --judge-dir <dir> --model <model-id> --output <json>

set -uo pipefail

CLONE_DIR=""
JUDGE_DIR=""
MODEL="claude-opus-4-7"
OUTPUT=""
MAX_EVIDENCE_KB=150   # cap evidence package to avoid context overflow (Opus 4.7 handles >>100KB easily)
RETRY_ON_MALFORMED=1

while [[ $# -gt 0 ]]; do
    case "$1" in
        --clone-dir)  CLONE_DIR="$2"; shift 2 ;;
        --judge-dir)  JUDGE_DIR="$2"; shift 2 ;;
        --model)      MODEL="$2"; shift 2 ;;
        --output)     OUTPUT="$2"; shift 2 ;;
        -h|--help)    sed -n '2,/^$/p' "$0"; exit 0 ;;
        *)            echo "Unknown arg: $1" >&2; exit 2 ;;
    esac
done

[[ -z "$CLONE_DIR" || ! -d "$CLONE_DIR" ]] && { echo "FAIL: --clone-dir invalid" >&2; exit 2; }
[[ -z "$JUDGE_DIR" || ! -d "$JUDGE_DIR" ]] && { echo "FAIL: --judge-dir invalid" >&2; exit 2; }
[[ -z "$OUTPUT" ]] && { echo "FAIL: --output required" >&2; exit 2; }
[[ -f "$JUDGE_DIR/judge-prompt.md" ]] || { echo "FAIL: judge-prompt.md missing" >&2; exit 2; }

# Resolve all paths to absolute before any cd happens.
# Evidence builder uses `cd "$CLONE_DIR"` inside { ... } group command — that
# persists in script shell, so subsequent relative paths resolve relative to
# clone. Convert critical paths to absolute up-front.
CLONE_DIR="$(readlink -f "$CLONE_DIR")"
JUDGE_DIR="$(readlink -f "$JUDGE_DIR")"
# OUTPUT may not exist yet — use realpath -m which doesn't require existence
OUTPUT="$(readlink -m "$OUTPUT")"

# ─── Build evidence package ──────────────────────────────────────────────────
EVIDENCE_FILE="$(mktemp -t bench-evidence-XXXXXX.md)"
trap 'rm -f "$EVIDENCE_FILE"' EXIT

# 1. Cat judge-prompt.md
cat "$JUDGE_DIR/judge-prompt.md" > "$EVIDENCE_FILE"

# Common exclusions: harness inject (`.claude/`), python caches, build artifacts.
# These are NOT the deliverable Claude built — including them would crowd out
# real code в evidence package.
FIND_EXCLUDES=(
    -not -path '*/.venv/*'
    -not -path '*/__pycache__/*'
    -not -path '*/.git/*'
    -not -path './.claude/*'
    -not -path '*/.pytest_cache/*'
    -not -path '*/.ruff_cache/*'
    -not -path '*/.mypy_cache/*'
    -not -path '*/.tox/*'
    -not -path '*.egg-info/*'
    -not -name '*.pyc'
    -not -name '.bench-*'
    -not -name '*.log'
)

# 2. Append file tree (paths only, deliverable-only)
{
    echo ""
    echo "## File tree (deliverable)"
    echo '```'
    cd "$CLONE_DIR" && find . -type f "${FIND_EXCLUDES[@]}" | sort | head -100
    echo '```'
} >> "$EVIDENCE_FILE"

# 3. Append content of deliverable files (single find pass, alphabetic).
# Skip fixture inputs (.env, metadata.py) — operator-provided, not Claude's output.
# Cap per-file at 6KB; total cap applied at end of evidence builder.
{
    echo ""
    echo "## File contents (deliverable code)"
    echo ""
    cd "$CLONE_DIR"

    # Single find: all deliverable file types in alphabetic order.
    # `.py`, `.md`, `pyproject.toml`, `requirements*.txt`, `setup.{py,cfg}`,
    # `Dockerfile`, `*.{yaml,yml}`, `.env.example`.
    while IFS= read -r f; do
        # Skip fixture inputs and harness CLAUDE.md / AGENTS.md
        case "$f" in
            ./.env|./metadata.py|./AGENTS.md|./CLAUDE.md) continue ;;
        esac
        [[ ! -f "$f" ]] && continue
        rel="${f#./}"
        echo ""
        echo "### \`$rel\`"
        echo '```'
        head -c 6000 "$f"
        size=$(wc -c < "$f")
        if [[ "$size" -gt 6000 ]]; then
            echo ""
            echo "[... truncated, total ${size} bytes ...]"
        fi
        echo '```'
    done < <(find . -type f "${FIND_EXCLUDES[@]}" \( \
        -name '*.py' -o \
        -name '*.md' -o \
        -name 'pyproject.toml' -o \
        -name 'requirements*.txt' -o \
        -name 'setup.py' -o \
        -name 'setup.cfg' -o \
        -name 'Dockerfile' -o \
        -name '*.yaml' -o \
        -name '*.yml' -o \
        -name '.env.example' \
        \) 2>/dev/null | sort)
} >> "$EVIDENCE_FILE"

# Cap total size
EVIDENCE_SIZE_KB=$(($(wc -c < "$EVIDENCE_FILE") / 1024))
if [[ "$EVIDENCE_SIZE_KB" -gt "$MAX_EVIDENCE_KB" ]]; then
    # Truncate to MAX_EVIDENCE_KB
    head -c "$((MAX_EVIDENCE_KB * 1024))" "$EVIDENCE_FILE" > "$EVIDENCE_FILE.trimmed"
    echo "" >> "$EVIDENCE_FILE.trimmed"
    echo "[... evidence truncated to ${MAX_EVIDENCE_KB}KB ...]" >> "$EVIDENCE_FILE.trimmed"
    mv "$EVIDENCE_FILE.trimmed" "$EVIDENCE_FILE"
fi

echo "[llm-judge] Evidence package: $(wc -c < "$EVIDENCE_FILE") bytes"

# ─── Invoke neutral judge ────────────────────────────────────────────────────

JUDGE_OUT="$(mktemp -t bench-judge-out-XXXXXX.json)"
# Only clean tmp files (NOT the OUTPUT) on exit. OUTPUT survives by design.
trap 'rm -f "$EVIDENCE_FILE" "$JUDGE_OUT"' EXIT

invoke_judge() {
    local attempt="$1"
    echo "[llm-judge] Attempt $attempt (model=$MODEL)..."
    # claude --print, neutral mode (no harness inject because invocation cwd is /tmp,
    # no .claude/ alongside). --no-session-persistence + default permission mode.
    # We use --output-format json для top-level wrapper, then parse `.result` for our JSON.
    local tmp_clone="$(mktemp -d -t bench-judge-cwd-XXXXXX)"
    trap "rm -rf '$tmp_clone'" RETURN
    cat "$EVIDENCE_FILE" | (cd "$tmp_clone" && claude --print \
        --model "$MODEL" \
        --output-format json \
        --permission-mode default \
        --no-session-persistence \
        2>/dev/null) > "$JUDGE_OUT"
}

invoke_judge 1
JUDGE_RC=$?

# Parse: extract .result, expect strict JSON inside
parse_judge_output() {
    local raw_out="$1"
    if ! jq -e . "$raw_out" >/dev/null 2>&1; then
        echo "MALFORMED_WRAPPER"
        return 1
    fi
    # Top-level is claude --print JSON with .result containing judge's response
    local cost result
    cost=$(jq -r '.total_cost_usd // 0' "$raw_out")
    result=$(jq -r '.result // ""' "$raw_out")

    # Strip markdown code fence if present
    result=$(echo "$result" | sed -E 's/^```(json)?[[:space:]]*//; s/```[[:space:]]*$//')

    # Try to parse result as JSON
    if echo "$result" | jq -e . >/dev/null 2>&1; then
        # Add cost into the output
        echo "$result" | jq --argjson c "$cost" '. + {cost_usd: $c, status: "ok"}'
        return 0
    fi

    # Heuristic: find first { and last } and try again
    result_trimmed=$(echo "$result" | python3 -c "
import sys, re
text = sys.stdin.read()
m = re.search(r'\{.*\}', text, re.DOTALL)
print(m.group(0) if m else '', end='')
")
    if [[ -n "$result_trimmed" ]] && echo "$result_trimmed" | jq -e . >/dev/null 2>&1; then
        echo "$result_trimmed" | jq --argjson c "$cost" '. + {cost_usd: $c, status: "ok"}'
        return 0
    fi

    echo "MALFORMED_INNER"
    return 1
}

PARSED=$(parse_judge_output "$JUDGE_OUT")
PARSE_RC=$?

if [[ $PARSE_RC -ne 0 ]] && [[ $RETRY_ON_MALFORMED -eq 1 ]]; then
    echo "[llm-judge] First attempt malformed ($PARSED) — retrying once..."
    invoke_judge 2
    PARSED=$(parse_judge_output "$JUDGE_OUT")
    PARSE_RC=$?
fi

if [[ $PARSE_RC -ne 0 ]]; then
    echo "[llm-judge] Both attempts malformed — writing fallback zero scores" >&2
    jq -n --arg reason "$PARSED" '{
        status: "fallback_zero",
        reason: $reason,
        T3: {score:0,max:6,justification:"judge output unparseable"},
        T4: {score:0,max:6,justification:"judge output unparseable"},
        T7: {score:0,max:6,justification:"judge output unparseable"},
        B1: {score:0,max:6,justification:"judge output unparseable"},
        B2: {score:0,max:5,justification:"judge output unparseable"},
        B3: {score:0,max:6,justification:"judge output unparseable"},
        B5: {score:0,max:8,justification:"judge output unparseable"},
        total: 0,
        cost_usd: 0
    }' > "$OUTPUT"
    exit 0
fi

# Validate required keys present + compute total if missing.
# Write via tmpfile + mv to avoid any shell quoting / partial-write issues
# (line 207 historic bug: VALIDATED содержал команды-подобные substring'и).
# Write directly via jq stdout redirect — avoid tmp+mv pattern that interacted
# weirdly with bash subshell EXIT trap (file was disappearing after script exit).
mkdir -p "$(dirname "$OUTPUT")"
echo "$PARSED" | jq '
    . as $orig |
    [(.T3.score // 0), (.T4.score // 0), (.T7.score // 0),
     (.B1.score // 0), (.B2.score // 0), (.B3.score // 0), (.B5.score // 0)] | add as $sum |
    $orig + {
        total: ($orig.total // $sum // 0)
    }
' > "$OUTPUT" 2>"$OUTPUT.err" || { echo "[llm-judge] FAIL: jq validate failed" >&2; cat "$OUTPUT.err" >&2; exit 1; }
rm -f "$OUTPUT.err"

# Sanity check
jq -e . "$OUTPUT" >/dev/null 2>&1 || { echo "[llm-judge] FAIL: $OUTPUT not valid JSON after write" >&2; head -c 500 "$OUTPUT" >&2; exit 1; }

# Ensure file is fully synced before script exits + trap fires.
# Without explicit sync, kernel may have buffered write that gets clobbered.
sync
[[ -s "$OUTPUT" ]] || { echo "[llm-judge] FAIL: $OUTPUT zero bytes after sync" >&2; exit 1; }

TOTAL=$(jq -r '.total // 0' "$OUTPUT")
COST=$(jq -r '.cost_usd // 0' "$OUTPUT")
echo "[llm-judge] Wrote $OUTPUT (total=$TOTAL / 43, cost=\$$COST, size=$(wc -c < "$OUTPUT") bytes)"
exit 0
