#!/usr/bin/env bash
# battle-test-runner.sh — F-deliverable orchestrator for text2sql-Oracle (and future
# battle-test scenarios). Wraps headless-runner.sh core (clone/inject/stream-json)
# с расширенным post-run grading: invokes built deliverable, auto-grades F-Q*,
# scripted T/B subitems, LLM-judge для rest.
#
# Patterns borrowed from .claude/loop/run.sh (Ralph): notify() + cumulative cost
# + per-phase error containment + cancel-file watch.
#
# Usage:
#   battle-test-runner.sh --task <name>
#                         [--harness ours|noharness|<inject-from-dir>]
#                         [--build-model claude-opus-4-7|claude-sonnet-4-6|opus|sonnet|default]
#                         [--judge-model claude-opus-4-7]
#                         [--timeout-sec 7200]
#                         [--question-timeout-sec 120]
#                         [--report-dir <dir>]
#                         [--cleanup-on-success]
#                         [--skip-grade]            # only Phase 1-3+9 (build skeleton)
#                         [--skip-llm-judge]        # Phases 4-7 only, skip Phase 8
#                         [--watch]                 # full verbose stream tail (debug)
#                         [--preflight-only]        # Phase 1 only, exit clean (no OAuth)
#
# Cancel gracefully: touch $REPORT_DIR/.bench-cancel — runner stops at next phase.
#
# Pipeline (9 phases):
#   1. Preflight (Oracle/Ollama/python env/fixtures + binary checks)
#   2. Clone + Inject harness variant (judge sibling NEVER copied)
#   3. Build (claude --print stream-json) с progress milestones каждые 30s
#   4. Detect deliverable entry-point + provision venv
#   5. Run 5 questions × deliverable (per timeout, capture stdout/stderr/wall)
#   6. Auto-grade F-Q1..Q5 via grade.py (30 pts max)
#   7. Auto-grade scriptable T/B via grade.py (23 pts max)
#   8. LLM-judge T/B residual via llm-judge.sh (47 pts max)
#   9. Aggregate report (always — partial subscores OK)
#
# See .claude/benchmark/text2sql-judge/README.md для methodology.

set -uo pipefail

# ─── Defaults ────────────────────────────────────────────────────────────────
TASK="text2sql"
HARNESS_VARIANT="ours"
BUILD_MODEL="claude-opus-4-7"
JUDGE_MODEL="claude-opus-4-7"
TIMEOUT_SEC=7200
QUESTION_TIMEOUT_SEC=120
REPORT_DIR=""
CLEANUP_ON_SUCCESS=0
SKIP_GRADE=0
SKIP_LLM_JUDGE=0
WATCH=0
PREFLIGHT_ONLY=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --task)                    TASK="$2"; shift 2 ;;
        --harness)                 HARNESS_VARIANT="$2"; shift 2 ;;
        --build-model)             BUILD_MODEL="$2"; shift 2 ;;
        --judge-model)             JUDGE_MODEL="$2"; shift 2 ;;
        --timeout-sec)             TIMEOUT_SEC="$2"; shift 2 ;;
        --question-timeout-sec)    QUESTION_TIMEOUT_SEC="$2"; shift 2 ;;
        --report-dir)              REPORT_DIR="$2"; shift 2 ;;
        --cleanup-on-success)      CLEANUP_ON_SUCCESS=1; shift ;;
        --skip-grade)              SKIP_GRADE=1; shift ;;
        --skip-llm-judge)          SKIP_LLM_JUDGE=1; shift ;;
        --watch)                   WATCH=1; shift ;;
        --preflight-only)          PREFLIGHT_ONLY=1; shift ;;
        -h|--help)                 sed -n '2,/^$/p' "$0"; exit 0 ;;
        *)                         echo "Unknown arg: $1" >&2; exit 2 ;;
    esac
done

HARNESS_ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
FIXTURE_DIR="$HARNESS_ROOT/.claude/benchmark/$TASK"
JUDGE_DIR="$HARNESS_ROOT/.claude/benchmark/${TASK}-judge"
TS=$(date -u +%Y%m%dT%H%M%SZ)
[[ -z "$REPORT_DIR" ]] && REPORT_DIR="$HARNESS_ROOT/.claude/benchmark/reports/$(date -u +%Y-%m-%d)-${TASK}-${HARNESS_VARIANT}-${TS}"
mkdir -p "$REPORT_DIR"

PHASE_LOG="$REPORT_DIR/phases.log"
CANCEL_FILE="$REPORT_DIR/.bench-cancel"

# ─── Ralph-pattern helpers ───────────────────────────────────────────────────

notify() {
    local title="$1" msg="$2"
    local stamp; stamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    echo "[$stamp] $title — $msg" | tee -a "$PHASE_LOG"
    command -v notify-send >/dev/null 2>&1 && \
        notify-send -u normal "battle-test: $title" "$msg" 2>/dev/null || true
}

check_cancel() {
    if [[ -f "$CANCEL_FILE" ]]; then
        notify "CANCELLED" "operator touched $CANCEL_FILE — aborting at phase $1"
        write_partial_report "cancelled at phase $1"
        exit 0
    fi
}

# Cumulative cost across all OAuth invocations (build + LLM-judge). Awk for float math.
CUMULATIVE_USD="0.0000"
acc_cost() {
    local delta="$1"
    [[ -z "$delta" || "$delta" == "null" ]] && return 0
    # Force LC_NUMERIC=C — system locale (ru_RU) makes awk emit "0,0000" with
    # decimal comma → breaks downstream jq --argjson parsing.
    CUMULATIVE_USD=$(LC_NUMERIC=C awk -v a="$CUMULATIVE_USD" -v b="$delta" 'BEGIN { printf "%.4f", a+b }')
}

# Emit partial report at any abort point (cancel, hard fail) so operator gets diagnostics
# regardless of which phase failed.
write_partial_report() {
    local reason="$1"
    local out="$REPORT_DIR/PARTIAL-${TS}.md"
    {
        echo "# Partial battle-test report"
        echo ""
        echo "**Aborted**: $reason"
        echo "**Task**: $TASK | **Harness**: $HARNESS_VARIANT | **Build model**: $BUILD_MODEL"
        echo "**Cumulative cost**: \$${CUMULATIVE_USD}"
        echo "**Report dir**: $REPORT_DIR"
        echo "**Clone**: ${CLONE_DIR:-not-created}"
        echo ""
        echo "## Phase log"
        echo '```'
        cat "$PHASE_LOG" 2>/dev/null || echo "(empty)"
        echo '```'
    } > "$out"
    notify "Partial" "Wrote $out"
}

phase_start() {
    local phase="$1" desc="$2"
    notify "[Phase $phase/9]" "$desc"
}

phase_end() {
    local phase="$1" status="$2"
    notify "[Phase $phase/9]" "$status"
}

# ─── Phase 1: Preflight ──────────────────────────────────────────────────────
echo "=========================================="
echo "  battle-test-runner v0.2 (Phases 1-9, Ralph-style)"
echo "  Task: $TASK | Harness: $HARNESS_VARIANT | Build: $BUILD_MODEL | Judge: $JUDGE_MODEL"
echo "  Report dir: $REPORT_DIR"
echo "  Cancel via: touch $CANCEL_FILE"
echo "=========================================="
echo "" | tee "$PHASE_LOG"

phase_start 1 "Preflight"
preflight_fail() { notify "PREFLIGHT FAIL" "$1"; write_partial_report "preflight: $1"; exit 2; }

for bin in claude jq docker python3 timeout; do
    command -v "$bin" >/dev/null 2>&1 || preflight_fail "'$bin' not in PATH"
done
[[ -d "$FIXTURE_DIR" ]] || preflight_fail "fixture dir missing: $FIXTURE_DIR"
[[ -f "$FIXTURE_DIR/.env" && -f "$FIXTURE_DIR/metadata.py" ]] || preflight_fail "fixture missing .env or metadata.py"
[[ -d "$JUDGE_DIR" ]] || preflight_fail "judge dir missing: $JUDGE_DIR"
for f in prompt.txt questions.yaml acceptance.yaml; do
    [[ -f "$JUDGE_DIR/$f" ]] || preflight_fail "judge $f missing"
done
GRADE_PY="$JUDGE_DIR/grade.py"
LLM_JUDGE_SH="$JUDGE_DIR/llm-judge.sh"
[[ $SKIP_GRADE -eq 0 ]] && [[ ! -f "$GRADE_PY" ]] && preflight_fail "grade.py missing at $GRADE_PY"
[[ $SKIP_GRADE -eq 0 && $SKIP_LLM_JUDGE -eq 0 ]] && [[ ! -f "$LLM_JUDGE_SH" ]] && \
    preflight_fail "llm-judge.sh missing at $LLM_JUDGE_SH"

if [[ "$TASK" == "text2sql" ]]; then
    docker inspect ai-analyst-oracle --format '{{.State.Running}}' 2>/dev/null | grep -q true || \
        preflight_fail "Oracle container 'ai-analyst-oracle' not running. docker start ai-analyst-oracle"
    python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:11434/api/tags', timeout=3)" 2>/dev/null || \
        preflight_fail "Ollama API unreachable at http://localhost:11434"
fi

OPERATOR_PY="$HARNESS_ROOT/.venv/bin/python3"
[[ -x "$OPERATOR_PY" ]] || preflight_fail "operator's .venv python not found at $OPERATOR_PY"
"$OPERATOR_PY" -c "import oracledb, yaml" 2>/dev/null || \
    preflight_fail "operator's .venv missing 'oracledb' or 'pyyaml'. Install: $OPERATOR_PY -m pip install oracledb pyyaml"

case "$HARNESS_VARIANT" in
    ours|noharness) ;;
    *) [[ -d "$HARNESS_VARIANT" ]] || preflight_fail "harness variant must be ours|noharness|<dir>: $HARNESS_VARIANT" ;;
esac

phase_end 1 "PASS (binaries + fixture + judge + Oracle + Ollama + venv all ready)"
check_cancel 1

if [[ $PREFLIGHT_ONLY -eq 1 ]]; then
    notify "Preflight-only mode" "Phase 1 passed. Exit без OAuth burn (use without --preflight-only для full run)."
    echo ""
    echo "=========================================="
    echo "  Preflight-only mode: ALL CHECKS PASSED"
    echo "  Drop --preflight-only для full run."
    echo "=========================================="
    exit 0
fi

# ─── Phase 2: Clone + Inject ─────────────────────────────────────────────────
phase_start 2 "Clone fixture + inject harness"

CLONE_DIR="/tmp/battle-${TASK}-${HARNESS_VARIANT}-${TS}"
cp -r "$FIXTURE_DIR" "$CLONE_DIR" || preflight_fail "clone copy failed"
find "$CLONE_DIR" -name '__pycache__' -type d -exec rm -rf {} + 2>/dev/null
find "$CLONE_DIR" -name '*.pyc' -delete 2>/dev/null

(cd "$CLONE_DIR" && \
    git init -q && \
    git add -A 2>/dev/null && \
    git -c user.email=bench@local.invalid -c user.name=bench-runner \
        commit -q -m "battle-test baseline" 2>/dev/null) || \
    notify "WARN" "git init failed in clone"

case "$HARNESS_VARIANT" in
    ours)
        cp -r "$HARNESS_ROOT/.claude" "$CLONE_DIR/.claude"
        rm -rf "$CLONE_DIR/.claude/settings.local.json" \
               "$CLONE_DIR/.claude/benchmark/fixtures/external" \
               "$CLONE_DIR/.claude/benchmark/reports" \
               "$CLONE_DIR/.claude/loop" \
               "$CLONE_DIR/.claude/memory" \
               "$CLONE_DIR/.claude/plans" \
               "$CLONE_DIR/.claude/worktrees" \
               "$CLONE_DIR/.claude/.cache" 2>/dev/null
        [[ -d "$CLONE_DIR/.claude/benchmark/${TASK}-judge" ]] && \
            rm -rf "$CLONE_DIR/.claude/benchmark/${TASK}-judge"
        # Discovery-gate trigger marker (hook activates only when present).
        touch "$CLONE_DIR/.claude/.benchmark-active"
        ;;
    noharness)
        :  # nothing injected
        ;;
    *)
        cp -r "$HARNESS_VARIANT" "$CLONE_DIR/.claude" 2>/dev/null
        # Discovery-gate marker for alt-harness variants too (if their settings
        # ship the hook — no-op otherwise).
        mkdir -p "$CLONE_DIR/.claude" 2>/dev/null
        touch "$CLONE_DIR/.claude/.benchmark-active" 2>/dev/null
        ;;
esac
phase_end 2 "Clone at $CLONE_DIR (variant: $HARNESS_VARIANT)"
check_cancel 2

# ─── Phase 3: Build ──────────────────────────────────────────────────────────
phase_start 3 "Build deliverable (claude --print model=$BUILD_MODEL timeout=${TIMEOUT_SEC}s)"

STREAM_FILE="$CLONE_DIR/.bench-stream.jsonl"
STDERR_FILE="$CLONE_DIR/.bench-stderr.log"
BUILD_START_EPOCH=$(date +%s)
BUILD_START_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

progress_monitor() {
    local sf="$1" start="$2" last_turn=0
    while true; do
        sleep 30
        [[ -f "$sf" ]] || continue
        local turns last_tool elapsed now
        turns=$(jq -c 'select(.type=="assistant")' "$sf" 2>/dev/null | wc -l | tr -d '[:space:]')
        [[ -z "$turns" ]] && turns=0
        if [[ "$turns" -gt "$last_turn" ]]; then
            last_tool=$(jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use") | .name' "$sf" 2>/dev/null | tail -1)
            now=$(date +%s); elapsed=$((now - start))
            printf "  [T+%02d:%02d] turn %d | last tool: %s\n" \
                $((elapsed/60)) $((elapsed%60)) "$turns" "${last_tool:-—}" | tee -a "$PHASE_LOG"
            last_turn=$turns
        fi
    done
}

progress_monitor "$STREAM_FILE" "$BUILD_START_EPOCH" &
MONITOR_PID=$!
trap 'kill $MONITOR_PID 2>/dev/null; true' EXIT INT TERM

BUILD_EXIT=0
set +e
# Permission mode: bypassPermissions для battle-test build phase.
# Rationale: clone — throwaway sandbox /tmp/, Claude нужны Bash + Edit + Write
# для pip install / pytest / module scaffolding. acceptEdits в --print mode не
# может answer Bash prompts (no interactive UI) → potential hang/denied.
# Settings.json's Bash allowlist частично покрывает чтение, но не pip/build.
# bypassPermissions безопасно в isolated clone — никаких harness/operator-repo
# files не достижимы.
BENCH_CLONE="$CLONE_DIR" BENCH_PROMPT_FILE="$JUDGE_DIR/prompt.txt" \
BENCH_MODEL="$BUILD_MODEL" BENCH_STREAM="$STREAM_FILE" BENCH_STDERR="$STDERR_FILE" \
HARNESS_BENCH_MODE=1 \
DISCOVERY_GATE_REQUIRE_CRITIC="${DISCOVERY_GATE_REQUIRE_CRITIC:-0}" \
    timeout "$TIMEOUT_SEC" bash -c '
    cd "$BENCH_CLONE" || exit 99
    cat "$BENCH_PROMPT_FILE" | claude --print \
        --model "$BENCH_MODEL" \
        --output-format stream-json \
        --include-hook-events \
        --verbose \
        --permission-mode bypassPermissions \
        --no-session-persistence \
        > "$BENCH_STREAM" 2> "$BENCH_STDERR"
'
BUILD_EXIT=$?
set -e

kill "$MONITOR_PID" 2>/dev/null || true
wait "$MONITOR_PID" 2>/dev/null || true

BUILD_END_EPOCH=$(date +%s)
BUILD_END_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
BUILD_WALL=$((BUILD_END_EPOCH - BUILD_START_EPOCH))

# Parse result event
NUM_TURNS=0; COST=0; INPUT_TOK=0; OUTPUT_TOK=0; CACHE_CR=0; CACHE_RD=0
RESULT_TEXT=""; STOP_REASON="<unknown>"
if [[ -s "$STREAM_FILE" ]]; then
    RESULT_EVENT=$(jq -c 'select(.type=="result")' "$STREAM_FILE" 2>/dev/null | tail -1)
    if [[ -n "$RESULT_EVENT" ]]; then
        NUM_TURNS=$(echo      "$RESULT_EVENT" | jq -r '.num_turns // 0')
        COST=$(echo           "$RESULT_EVENT" | jq -r '.total_cost_usd // 0')
        INPUT_TOK=$(echo      "$RESULT_EVENT" | jq -r '.usage.input_tokens // 0')
        OUTPUT_TOK=$(echo     "$RESULT_EVENT" | jq -r '.usage.output_tokens // 0')
        CACHE_CR=$(echo       "$RESULT_EVENT" | jq -r '.usage.cache_creation_input_tokens // 0')
        CACHE_RD=$(echo       "$RESULT_EVENT" | jq -r '.usage.cache_read_input_tokens // 0')
        RESULT_TEXT=$(echo    "$RESULT_EVENT" | jq -r '.result // "<no result>"' | head -c 2000)
        STOP_REASON=$(echo    "$RESULT_EVENT" | jq -r '.stop_reason // "<unknown>"')
    fi
fi
acc_cost "$COST"

# Trajectory parsing (Layer C)
TRAJECTORY="{}"
if [[ -s "$STREAM_FILE" ]]; then
    set +o pipefail
    TOOL_USES=$(jq -c 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use")' "$STREAM_FILE" 2>/dev/null)
    SKILLS=$(echo "$TOOL_USES" | jq -s '[.[] | select(.name=="Skill") | (.input.skill // .input.name // "unknown")] | unique' 2>/dev/null || echo '[]')
    SUBA_CNT=$(echo "$TOOL_USES" | jq -s '[.[] | select(.name=="Agent" or .name=="Task")] | length' 2>/dev/null || echo 0)
    SUBA_TYPES=$(echo "$TOOL_USES" | jq -s '[.[] | select(.name=="Agent" or .name=="Task") | (.input.subagent_type // .input.type // "default")] | unique' 2>/dev/null || echo '[]')
    TOOL_SUM=$(echo "$TOOL_USES" | jq -s 'group_by(.name) | map({name: .[0].name, count: length}) | sort_by(-.count)' 2>/dev/null || echo '[]')
    INV_PATTERNS='ANTHROPIC_API_KEY|--bare\b|--max-budget-usd|managed-agents-|--no-verify'
    declare -a PING_LIST=()
    while IFS=':' read -r count pat; do
        [[ -n "$pat" ]] && PING_LIST+=("{\"pattern\":\"$(echo "$pat" | sed 's/[][\\\/]/\\&/g; s/\"/\\\"/g')\",\"count\":$count}")
    done < <(grep -ohE "$INV_PATTERNS" "$STREAM_FILE" 2>/dev/null | sort | uniq -c | sed 's/^[[:space:]]*//' | awk '{printf "%s:%s\n", $1, $2}')
    INV_PINGS="[]"; [[ ${#PING_LIST[@]} -gt 0 ]] && INV_PINGS="[$(IFS=,; echo "${PING_LIST[*]}")]"
    set -o pipefail
    TRAJECTORY=$(jq -n \
        --argjson skills "$SKILLS" --argjson sc "$SUBA_CNT" --argjson st "$SUBA_TYPES" \
        --argjson tools "$TOOL_SUM" --argjson pings "$INV_PINGS" \
        '{skills_triggered: $skills, subagent_dispatches: {count: $sc, types: $st}, tool_calls_summary: $tools, invariant_pings: $pings}' 2>/dev/null || echo '{}')
fi
phase_end 3 "Build exit=$BUILD_EXIT turns=$NUM_TURNS wall=${BUILD_WALL}s cost=\$$COST (cum \$$CUMULATIVE_USD)"
check_cancel 3

# Early-exit gate: build failure → no deliverable → no grading possible
if [[ $BUILD_EXIT -ne 0 ]] && [[ $BUILD_EXIT -ne 124 ]]; then
    notify "Build hard-fail" "exit=$BUILD_EXIT; stderr tail: $(tail -c 300 "$STDERR_FILE" 2>/dev/null)"
fi

# ─── Phases 4-8: Grading (skipped via --skip-grade) ─────────────────────────

FQ_SCORES='{}'; TB_AUTO_SCORES='{}'; LLM_SCORES='{}'
DELIVERABLE_INFO='{"status":"skipped"}'

if [[ $SKIP_GRADE -eq 0 ]]; then
    phase_start 4 "Detect deliverable entry + provision venv"
    set +e
    "$OPERATOR_PY" "$GRADE_PY" detect \
        --clone-dir "$CLONE_DIR" \
        --output "$REPORT_DIR/detect.json" 2>&1 | tee -a "$PHASE_LOG"
    DETECT_EXIT=$?
    set -e

    if [[ $DETECT_EXIT -eq 0 && -f "$REPORT_DIR/detect.json" ]]; then
        DELIVERABLE_INFO=$(cat "$REPORT_DIR/detect.json")
        ENTRY_CMD=$(echo "$DELIVERABLE_INFO" | jq -r '.invocation_cmd // empty')
        ENTRY_KIND=$(echo "$DELIVERABLE_INFO" | jq -r '.entry_kind // "unknown"')
        VENV_STATUS=$(echo "$DELIVERABLE_INFO" | jq -r '.venv_status // "unknown"')
        phase_end 4 "entry=$ENTRY_KIND venv=$VENV_STATUS"
    else
        notify "Phase 4 FAIL" "detect failed exit=$DETECT_EXIT — F-Q* will be 0"
        ENTRY_CMD=""
    fi
    check_cancel 4

    phase_start 5 "Run 5 questions (timeout ${QUESTION_TIMEOUT_SEC}s/each)"
    if [[ -n "$ENTRY_CMD" ]]; then
        set +e
        "$OPERATOR_PY" "$GRADE_PY" run-questions \
            --clone-dir "$CLONE_DIR" \
            --questions "$JUDGE_DIR/questions.yaml" \
            --detect "$REPORT_DIR/detect.json" \
            --timeout-sec "$QUESTION_TIMEOUT_SEC" \
            --output "$REPORT_DIR/questions.json" 2>&1 | tee -a "$PHASE_LOG"
        Q_EXIT=$?
        set -e
        if [[ $Q_EXIT -eq 0 ]]; then
            phase_end 5 "5 questions done (see questions.json)"
        else
            notify "Phase 5 WARN" "run-questions exit=$Q_EXIT — F-Q* may be 0"
        fi
    else
        phase_end 5 "skipped (no entry detected)"
    fi
    check_cancel 5

    phase_start 6 "Auto-grade F-Q1..Q5 (30 pts max)"
    set +e
    "$OPERATOR_PY" "$GRADE_PY" grade-fq \
        --questions "$JUDGE_DIR/questions.yaml" \
        --answers "$REPORT_DIR/questions.json" \
        --output "$REPORT_DIR/fq-scores.json" 2>&1 | tee -a "$PHASE_LOG"
    set -e
    [[ -f "$REPORT_DIR/fq-scores.json" ]] && FQ_SCORES=$(cat "$REPORT_DIR/fq-scores.json")
    phase_end 6 "F-Q total: $(echo "$FQ_SCORES" | jq -r '.total // 0')/30"
    check_cancel 6

    phase_start 7 "Auto-grade scriptable T/B (23 pts max)"
    set +e
    "$OPERATOR_PY" "$GRADE_PY" grade-tb-auto \
        --clone-dir "$CLONE_DIR" \
        --questions-result "$REPORT_DIR/questions.json" \
        --output "$REPORT_DIR/tb-auto-scores.json" 2>&1 | tee -a "$PHASE_LOG"
    set -e
    [[ -f "$REPORT_DIR/tb-auto-scores.json" ]] && TB_AUTO_SCORES=$(cat "$REPORT_DIR/tb-auto-scores.json")
    phase_end 7 "T/B auto total: $(echo "$TB_AUTO_SCORES" | jq -r '.total // 0')/$(echo "$TB_AUTO_SCORES" | jq -r '.max // 27')"
    check_cancel 7

    if [[ $SKIP_LLM_JUDGE -eq 0 ]]; then
        phase_start 8 "LLM-judge T/B residual ($JUDGE_MODEL, 43 pts max)"
        set +e
        "$LLM_JUDGE_SH" \
            --clone-dir "$CLONE_DIR" \
            --judge-dir "$JUDGE_DIR" \
            --model "$JUDGE_MODEL" \
            --output "$REPORT_DIR/llm-judge.json" 2>&1 | tee -a "$PHASE_LOG"
        set -e
        if [[ -f "$REPORT_DIR/llm-judge.json" ]]; then
            LLM_SCORES=$(cat "$REPORT_DIR/llm-judge.json")
            LLM_COST=$(echo "$LLM_SCORES" | jq -r '.cost_usd // 0')
            acc_cost "$LLM_COST"
        fi
        phase_end 8 "LLM-judge total: $(echo "$LLM_SCORES" | jq -r '.total // 0')/43 (cost +\$$LLM_COST)"
    else
        phase_end 8 "skipped (--skip-llm-judge)"
    fi
fi

# ─── Phase 9: Aggregate ──────────────────────────────────────────────────────
phase_start 9 "Aggregate report"

REPORT_JSON="$REPORT_DIR/build-report.json"
SUMMARY_MD="$REPORT_DIR/summary.md"

FQ_TOTAL=$(echo "$FQ_SCORES" | jq -r '.total // 0')
TB_AUTO_TOTAL=$(echo "$TB_AUTO_SCORES" | jq -r '.total // 0')
LLM_TOTAL=$(echo "$LLM_SCORES" | jq -r '.total // 0')
GRAND_TOTAL=$(awk -v a="$FQ_TOTAL" -v b="$TB_AUTO_TOTAL" -v c="$LLM_TOTAL" 'BEGIN { print a+b+c }')

# Verdict per acceptance.yaml thresholds (≥70 accepted, 50-69 partial, <50 failure)
VERDICT="failure"
if   (( $(awk -v g="$GRAND_TOTAL" 'BEGIN{print (g>=70)}') )); then VERDICT="accepted"
elif (( $(awk -v g="$GRAND_TOTAL" 'BEGIN{print (g>=50)}') )); then VERDICT="partial"
fi

jq -n \
    --arg task "$TASK" --arg harness "$HARNESS_VARIANT" --arg build_model "$BUILD_MODEL" --arg judge_model "$JUDGE_MODEL" \
    --arg ts_start "$BUILD_START_TS" --arg ts_end "$BUILD_END_TS" \
    --argjson wall "$BUILD_WALL" --argjson build_exit "$BUILD_EXIT" \
    --arg stop "$STOP_REASON" --argjson turns "$NUM_TURNS" --argjson cost "$COST" \
    --argjson in_tok "$INPUT_TOK" --argjson out_tok "$OUTPUT_TOK" \
    --argjson cc "$CACHE_CR" --argjson cr "$CACHE_RD" \
    --argjson trajectory "$TRAJECTORY" --arg result "$RESULT_TEXT" \
    --arg cum_cost "$CUMULATIVE_USD" --arg clone "$CLONE_DIR" \
    --argjson deliverable "$DELIVERABLE_INFO" \
    --argjson fq "$FQ_SCORES" --argjson tb_auto "$TB_AUTO_SCORES" --argjson llm "$LLM_SCORES" \
    --arg grand_total "$GRAND_TOTAL" --arg verdict "$VERDICT" \
    '{
        task: $task, harness: $harness, build_model: $build_model, judge_model: $judge_model,
        timing: {start: $ts_start, end: $ts_end, wall_seconds: $wall},
        build: {
            exit_code: $build_exit, stop_reason: $stop, num_turns: $turns,
            cost_usd: $cost,
            tokens: {input: $in_tok, output: $out_tok, cache_creation: $cc, cache_read: $cr}
        },
        trajectory: $trajectory,
        result_excerpt: $result,
        deliverable: $deliverable,
        grading: {
            f_questions: $fq,
            tb_auto: $tb_auto,
            llm_judge: $llm,
            grand_total: ($grand_total | tonumber),
            max: 100,
            verdict: $verdict
        },
        cumulative_cost_usd: ($cum_cost | tonumber),
        clone_dir: $clone
    }' > "$REPORT_JSON"

cat > "$SUMMARY_MD" <<EOF
# Battle-test: $TASK / $HARNESS_VARIANT

**Date**: $BUILD_START_TS
**Build model**: $BUILD_MODEL
**Wall**: ${BUILD_WALL}s ($((BUILD_WALL/60))m $((BUILD_WALL%60))s) build only
**Total OAuth cost**: \$${CUMULATIVE_USD}

## Verdict: **$VERDICT** ($GRAND_TOTAL / 100)

| Section | Score | Max |
|---|---:|---:|
| F-Questions (auto) | $FQ_TOTAL | 30 |
| T/B auto (scriptable) | $TB_AUTO_TOTAL | 23 |
| T/B LLM-judge | $LLM_TOTAL | 47 |
| **Grand total** | **$GRAND_TOTAL** | **100** |

Thresholds: ≥70 accepted · 50-69 partial · <50 failure.

## Build phase

- exit_code: $BUILD_EXIT
- stop_reason: $STOP_REASON
- turns: $NUM_TURNS
- cost: \$$COST
- tokens: in=$INPUT_TOK out=$OUTPUT_TOK cache_create=$CACHE_CR cache_read=$CACHE_RD

## Trajectory (Layer C)

\`\`\`json
$(echo "$TRAJECTORY" | jq .)
\`\`\`

## Result excerpt

\`\`\`
$RESULT_TEXT
\`\`\`

## Deliverable info

\`\`\`json
$(echo "$DELIVERABLE_INFO" | jq .)
\`\`\`

## F-Question scores

\`\`\`json
$(echo "$FQ_SCORES" | jq .)
\`\`\`

## T/B auto scores

\`\`\`json
$(echo "$TB_AUTO_SCORES" | jq .)
\`\`\`

## LLM-judge scores

\`\`\`json
$(echo "$LLM_SCORES" | jq .)
\`\`\`

## Clone preservation

\`$CLONE_DIR\` — $(if [[ $BUILD_EXIT -ne 0 || $CLEANUP_ON_SUCCESS -eq 0 ]]; then echo "preserved для forensics"; else echo "removed (--cleanup-on-success)"; fi)

## Methodology

- \`.claude/docs/benchmark.md\` — 4-layer framework
- \`.claude/benchmark/text2sql-judge/README.md\` — battle-test specifics
- \`.claude/benchmark/text2sql-judge/acceptance.yaml\` — 100-pt rubric
EOF

# Cleanup decision
if [[ $BUILD_EXIT -eq 0 ]] && [[ $CLEANUP_ON_SUCCESS -eq 1 ]] && [[ "$VERDICT" != "failure" ]]; then
    rm -rf "$CLONE_DIR" 2>/dev/null
    notify "Cleanup" "clone removed (--cleanup-on-success + non-failure verdict)"
fi

phase_end 9 "Report at $REPORT_JSON | verdict=$VERDICT | grand=$GRAND_TOTAL/100"
notify "DONE" "$TASK / $HARNESS_VARIANT → $VERDICT ($GRAND_TOTAL/100, \$$CUMULATIVE_USD, $((BUILD_WALL/60))m)"

echo ""
echo "=========================================="
echo "  Verdict: $VERDICT ($GRAND_TOTAL/100)"
echo "  Report:  $REPORT_JSON"
echo "  Summary: $SUMMARY_MD"
echo "  Clone:   $CLONE_DIR"
echo "  Total cost: \$${CUMULATIVE_USD}"
echo "=========================================="

exit 0
