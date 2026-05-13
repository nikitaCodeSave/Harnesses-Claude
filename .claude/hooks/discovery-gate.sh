#!/usr/bin/env bash
# Stop hook — Evaluator-node gate (harness-internal, opt-in).
#
# Pairs with .claude/agents/discovery-critic.md (project-agnostic) and
# .claude/commands/critique.md (manual user-invoked).
#
# Scope of this hook: HARNESS-INTERNAL automation for headless runs (ralph-loop,
# CI benchmark) where there is no human-in-the-loop to read CRITIC.json. For
# interactive sessions use /critique slash command — it spawns the same agent
# but does not require this hook.
#
# Triggers (any one activates the hook; default off — pass-through exit 0):
#   - EVALUATOR_GATE_ACTIVE=1        (primary, neutral)
#   - .claude/.evaluator-active      (primary, neutral marker)
#   - HARNESS_BENCH_MODE=1           (legacy alias — ralph-loop / battle-test-runner)
#   - .claude/.benchmark-active      (legacy alias — battle-test-runner)
#
# Enforcement mode (when active):
#   - Default: ADVISORY — log + stderr surface, exit 0. Does not block Stop.
#   - EVALUATOR_GATE_ENFORCE=1: BLOCKING — exit 2 forces agent to continue.
#     Use only in headless contexts (ralph-loop, CI) where a human cannot
#     react to advisory warnings.
#
# Required artifacts (parsed as JSON via jq):
#   - PREMORTEM.json   ≥4 entries in .failure_modes[]; categories span ≥3 distinct
#   - EVIDENCE.json    ≥3 entries in .runs[]
#   - CRITIC.json      (only when EVALUATOR_GATE_REQUIRE_CRITIC=1)
#                      Expects critic_version >= 2.0 schema with
#                      premortem_verification[].severity, accept_risk_quality,
#                      evidence_quality.reexecution_coverage. Single class-based
#                      filter `critic_critical_unaddressed`: any critical-severity
#                      entry whose verdict is not `addressed` and not
#                      `accept_risk` with `accept_risk_quality=justified` blocks.
#                      Replaces split symptom-specific filters (documented_only,
#                      accept_risk+weak) to avoid adjacent-class bypass.
#
# JSON parsing: jq is required when active. If jq missing, hook degrades to
# pass-through with stderr warning (does not break sessions without jq).

set -uo pipefail

cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0

# --- Trigger detection ---
ACTIVE=0
[[ "${EVALUATOR_GATE_ACTIVE:-0}" == "1" ]] && ACTIVE=1
[[ -f ".claude/.evaluator-active" ]] && ACTIVE=1
[[ "${HARNESS_BENCH_MODE:-0}" == "1" ]] && ACTIVE=1
[[ -f ".claude/.benchmark-active" ]] && ACTIVE=1
[[ $ACTIVE -eq 1 ]] || exit 0

# --- jq dependency ---
if ! command -v jq >/dev/null 2>&1; then
    echo "discovery-gate: jq not found; gate degraded to pass-through. Install jq to enable JSON validation." >&2
    exit 0
fi

# --- Enforcement mode ---
ENFORCE=0
[[ "${EVALUATOR_GATE_ENFORCE:-0}" == "1" ]] && ENFORCE=1

# --- Critic requirement (opt-in) ---
# Accept neutral name primary, legacy DISCOVERY_GATE_REQUIRE_CRITIC as alias.
REQUIRE_CRITIC="${EVALUATOR_GATE_REQUIRE_CRITIC:-${DISCOVERY_GATE_REQUIRE_CRITIC:-0}}"

# --- Max critic iterations cap ---
MAX_CRITIC_ITER="${EVALUATOR_GATE_MAX_CRITIC_ITER:-${DISCOVERY_GATE_MAX_CRITIC_ITER:-3}}"

# --- Paths ---
PREMORTEM="PREMORTEM.json"
EVIDENCE="EVIDENCE.json"
CRITIC="CRITIC.json"
LOG_DIR=".claude/memory"
mkdir -p "$LOG_DIR" 2>/dev/null
LOG_FILE="$LOG_DIR/discovery-gate.jsonl"
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Coerce a possibly-malformed integer string to a valid non-negative int.
# Strips fractional part and non-digits so subagent miscounts (e.g. "1.5") cannot amplify.
normalize_int() {
    local v="${1%%.*}"
    v="${v//[!0-9]/}"
    echo "${v:-0}"
}

# Coerce MAX_CRITIC_ITER through normalize_int (defends against non-numeric env values
# crashing `(( ))` under set -u) and clamp to minimum 1 (cap=0 would silently disable
# the gate by triggering cap-reached on first invocation).
MAX_CRITIC_ITER=$(normalize_int "$MAX_CRITIC_ITER")
(( MAX_CRITIC_ITER < 1 )) && MAX_CRITIC_ITER=1

# Validate that a JSON artifact has a top-level array field with at least min_count entries.
# Pushes domain-specific errors into the global errors[] array; sets out_var to the entry count.
# Args: file field min_count missing_msg type_msg count_msg_template out_var
# Count msg may reference __COUNT__ which is substituted with the actual count.
validate_json_array_artifact() {
    local file="$1" field="$2" min_count="$3"
    local missing_msg="$4" type_msg="$5" count_msg_template="$6"
    local -n out="$7"
    out=0
    if [[ ! -f "$file" ]]; then
        errors+=("$missing_msg")
        return
    fi
    if ! jq empty "$file" 2>/dev/null; then
        errors+=("$file is not valid JSON. Run 'jq empty $file' to see parser error and fix.")
        return
    fi
    if ! jq -e ".${field} | type == \"array\"" "$file" >/dev/null 2>&1; then
        errors+=("$type_msg")
        return
    fi
    out=$(normalize_int "$(jq ".${field} | length" "$file" 2>/dev/null)")
    if (( out < min_count )); then
        errors+=("${count_msg_template//__COUNT__/$out}")
    fi
}

errors=()
premortem_count=0
premortem_categories=0
evidence_count=0
critic_new_critical=0
critic_documented=0
critic_critical_unaddressed=0
critic_accept_risk_weak=0
critic_reexec_coverage="unknown"
critic_evidence="unknown"
critic_blocking_issue="null"

validate_json_array_artifact "$PREMORTEM" "failure_modes" 4 \
    "PREMORTEM.json missing. Before declaring done, write a failure-mode catalog. Schema: {\"deliverable\": \"...\", \"context\": {\"git_head\": \"...\", \"dirty\": bool, \"iter_round\": N}, \"failure_modes\": [{title, category, trigger, impact, severity, mitigation_status, mitigation_note}, ...]}. At least 4 entries required, categories must span ≥3 distinct values. Categories: state|precondition|boundary|resource|concurrency|security|semantics|other. This gate does not prescribe which failures to catalog — that is discovery work." \
    "PREMORTEM.json .failure_modes is not an array (must be JSON array, not string/object/number). length-count gates require array type." \
    "PREMORTEM.json has only __COUNT__ entries in failure_modes[] (≥4 required). Add more distinct failure modes." \
    premortem_count

# Category-spread check (≥3 distinct categories). Stuffing 4 boundary findings would
# pass count alone but bypass adversarial intent — class-based gate.
if [[ -f "$PREMORTEM" ]] && jq empty "$PREMORTEM" 2>/dev/null && jq -e '.failure_modes | type == "array"' "$PREMORTEM" >/dev/null 2>&1; then
    premortem_categories=$(normalize_int "$(jq '[.failure_modes[].category] | unique | length' "$PREMORTEM" 2>/dev/null)")
    if (( premortem_count >= 4 )) && (( premortem_categories < 3 )); then
        errors+=("PREMORTEM.json failure_modes span only $premortem_categories distinct categories (≥3 required). Diversify across state|precondition|boundary|resource|concurrency|security|semantics — piling findings in one category bypasses adversarial intent.")
    fi
fi

validate_json_array_artifact "$EVIDENCE" "runs" 3 \
    "EVIDENCE.json missing. Document real executions of the deliverable. Schema: {\"deliverable\": \"...\", \"runs\": [{name, command, real_or_mock, input, observed_output, expected, outcome, notes}, ...]}. At least 3 entries with real_or_mock=\"real\" required. Outcomes: pass|fail|surfaced_bug." \
    "EVIDENCE.json .runs is not an array (must be JSON array, not string/object/number). length-count gates require array type." \
    "EVIDENCE.json has only __COUNT__ entries in runs[] (≥3 required)." \
    evidence_count

# --- CRITIC.json check (opt-in) ---
critic_iter_count=0
critic_cap_reached=0

if [[ "$REQUIRE_CRITIC" == "1" ]]; then
    # Counts log rows where critic actually flagged a real issue: schema-fails and
    # missing-CRITIC rounds must not exhaust the cap. tail bounds the slurp at O(1)
    # regardless of log size — last 100 entries cover any plausible cap value.
    if [[ -s "$LOG_FILE" ]]; then
        critic_iter_count=$(tail -n 100 "$LOG_FILE" | jq -s '[.[] | select(
            .decision=="block"
            and (.require_critic // "") == "1"
            and (.premortem_count // 0) >= 4
            and (.premortem_categories // 0) >= 3
            and (.evidence_count // 0) >= 3
            and ((.critic_new_critical // 0) > 0
                 or (.critic_critical_unaddressed // 0) > 0
                 or ((.critic_evidence // "") == "low")
                 or ((.critic_reexec_coverage // "") == "none_all_side_effects"))
        )] | length' 2>/dev/null || echo 0)
        critic_iter_count=$(normalize_int "$critic_iter_count")
    fi

    if [[ ! -f "$CRITIC" ]]; then
        errors+=("CRITIC.json missing. After PREMORTEM.json and EVIDENCE.json are written, spawn the 'discovery-critic' subagent (Task tool with subagent_type='discovery-critic') for adversarial fresh-context review. Or use the /critique slash command. The subagent writes CRITIC.json with structured findings.")
    elif ! jq empty "$CRITIC" 2>/dev/null; then
        errors+=("CRITIC.json is not valid JSON. The discovery-critic subagent produced malformed output. Re-spawn.")
    elif ! jq -e '(.new_findings|type=="array") and (.premortem_verification|type=="array") and (.evidence_quality.overall_grade|type=="string") and (.verdict|type=="object")' "$CRITIC" >/dev/null 2>&1; then
        errors+=("CRITIC.json missing required schema (empty file, bare array, or absent .new_findings / .premortem_verification / .evidence_quality.overall_grade / .verdict). The discovery-critic subagent did not produce a complete verdict — re-spawn. This check catches zero-byte files, partial writes, and malformed verdicts that would otherwise bypass the gate silently.")
    elif ! jq -e 'all(.new_findings[]; has("severity") and (.severity|type=="string"))' "$CRITIC" >/dev/null 2>&1; then
        errors+=("CRITIC.json has new_findings entries missing severity field or with non-string severity. Every finding must declare severity (critical|major|minor) — missing-severity entries are silently invisible to the gate. Re-spawn critic with complete schema.")
    elif ! jq -e 'all(.premortem_verification[]; has("verdict") and (.verdict|type=="string"))' "$CRITIC" >/dev/null 2>&1; then
        errors+=("CRITIC.json has premortem_verification entries missing verdict field or with non-string verdict. Every entry must declare verdict (addressed|documented_only|unclear|accept_risk).")
    elif (( $(jq '.premortem_verification | length' "$CRITIC" 2>/dev/null || echo 0) < premortem_count )); then
        # Cross-length check: every PREMORTEM entry must appear in premortem_verification[].
        # Without this, a malformed or compromised critic returning [] passes all per-item
        # filters (critical_documented_only=0, etc.) and bypasses the gate.
        critic_pv_len=$(jq '.premortem_verification | length' "$CRITIC" 2>/dev/null || echo 0)
        errors+=("CRITIC.premortem_verification has $critic_pv_len entries but PREMORTEM.failure_modes has $premortem_count. Critic must verify EVERY PREMORTEM entry — shorter arrays can hide critical_documented_only items. Re-spawn critic with complete coverage.")
    else
        # Arrays are source of truth — scalars in .verdict.* are advisory. Case-fold + strip
        # whitespace so "Critical"/"CRITICAL"/"critical " all match the canonical lowercase.
        critic_blocking_issue=$(jq -r '.verdict.blocking_issue // "null"' "$CRITIC" 2>/dev/null || echo "null")
        critic_new_critical=$(normalize_int "$(jq '[.new_findings[] | select((.severity // "" | ascii_downcase | gsub("\\s"; "")) == "critical")] | length' "$CRITIC" 2>/dev/null)")
        critic_documented=$(normalize_int "$(jq '[.premortem_verification[] | select((.verdict // "" | ascii_downcase | gsub("\\s"; "")) == "documented_only")] | length' "$CRITIC" 2>/dev/null)")
        critic_accept_risk_weak=$(normalize_int "$(jq '[.premortem_verification[] | select((.accept_risk_quality // "" | ascii_downcase | gsub("\\s"; "")) == "weak")] | length' "$CRITIC" 2>/dev/null)")
        # Class-based "critical not safely resolved" filter — severity dominates verdict.
        # A critical-severity premortem item passes ONLY if either (a) verdict=addressed, or
        # (b) verdict=accept_risk AND accept_risk_quality=justified. Everything else blocks:
        # documented_only, unclear, accept_risk+weak, accept_risk+unjustified, accept_risk+n/a
        # (inconsistent), and unknown verdicts (fail-safe). All severity/verdict/quality
        # comparisons are case-folded and whitespace-stripped to match new_findings semantics.
        # jq does not have prefix `not` — using De Morgan: NOT (accept_risk AND justified)
        # ≡ (verdict != accept_risk) OR (accept_risk_quality != justified). Combined with
        # the leading (verdict != addressed) clause this is exactly "not in the safe set".
        critic_critical_unaddressed=$(normalize_int "$(jq '[.premortem_verification[]
            | select((.severity // "" | ascii_downcase | gsub("\\s"; "")) == "critical")
            | select(
                ((.verdict // "" | ascii_downcase | gsub("\\s"; "")) != "addressed")
                and (
                    ((.verdict // "" | ascii_downcase | gsub("\\s"; "")) != "accept_risk")
                    or ((.accept_risk_quality // "" | ascii_downcase | gsub("\\s"; "")) != "justified")
                )
            )] | length' "$CRITIC" 2>/dev/null)")
        critic_reexec_coverage=$(jq -r '.evidence_quality.reexecution_coverage // "unknown"' "$CRITIC" 2>/dev/null || echo "unknown")
        critic_reexec_coverage="${critic_reexec_coverage,,}"
        critic_reexec_coverage="${critic_reexec_coverage// /}"
        critic_evidence=$(jq -r '.evidence_quality.overall_grade // "unknown"' "$CRITIC" 2>/dev/null || echo "unknown")
        critic_evidence="${critic_evidence,,}"
        critic_evidence="${critic_evidence// /}"

        # Cap check: switch to advisory after MAX_CRITIC_ITER blocked rounds
        if (( critic_iter_count >= MAX_CRITIC_ITER )); then
            critic_cap_reached=1
            {
                echo "=========================================="
                echo "EVALUATOR GATE: max-critic-iterations cap reached ($critic_iter_count >= $MAX_CRITIC_ITER)"
                echo "=========================================="
                echo "Latest verdict: new_critical=$critic_new_critical critical_unaddressed=$critic_critical_unaddressed documented_total=$critic_documented accept_risk_weak=$critic_accept_risk_weak evidence=$critic_evidence reexec=$critic_reexec_coverage"
                (( critic_new_critical > 0 )) && echo "WARNING: $critic_new_critical critical findings remain. Document accept_risk in PREMORTEM before next session."
                (( critic_critical_unaddressed > 0 )) && echo "WARNING: $critic_critical_unaddressed critical-severity items NOT safely resolved (need addressed or accept_risk+justified)."
                (( critic_accept_risk_weak > 0 )) && echo "WARNING: $critic_accept_risk_weak accept_risk entries have weak justification."
                [[ "$critic_evidence" == "low" ]] && echo "WARNING: EVIDENCE quality LOW."
                [[ "$critic_reexec_coverage" == "none_all_side_effects" ]] && echo "WARNING: EVIDENCE re-execution coverage is none (all real runs side-effect-bearing)."
                echo "Allowing stop to prevent infinite loop."
            } >&2
        else
            if [[ "$critic_blocking_issue" != "null" && -n "$critic_blocking_issue" ]]; then
                errors+=("CRITIC.json reports blocking_issue: $critic_blocking_issue. Fix the input artifacts and re-spawn discovery-critic.")
            fi
            if (( critic_new_critical > 0 )); then
                current_iter=$((critic_iter_count + 1))
                errors+=("CRITIC found $critic_new_critical NEW critical findings (not in PREMORTEM). Read CRITIC.json .new_findings[] (filter by severity=critical), fix each in code, re-spawn discovery-critic. Iteration $current_iter/$MAX_CRITIC_ITER — after $MAX_CRITIC_ITER blocked rounds, gate switches to advisory.")
            fi
            if (( critic_critical_unaddressed > 0 )); then
                errors+=("CRITIC found $critic_critical_unaddressed critical-severity PREMORTEM items NOT safely resolved (not addressed AND not accept_risk+justified). Critical severity dominates: such items must be either fixed in code (verdict=addressed) or accept_risk with accept_risk_quality=justified. Other verdicts — documented_only, unclear, accept_risk+weak, accept_risk+unjustified — all block. Re-spawn critic after fixing in code or strengthening mitigation_note.")
            fi
            if [[ "$critic_evidence" == "low" ]]; then
                errors+=("CRITIC graded EVIDENCE quality LOW (mocks detected, no failure surfaces, or narrow coverage). Add real-data executions covering trap/edge/error paths. Re-spawn critic.")
            fi
            if [[ "$critic_reexec_coverage" == "none_all_side_effects" ]]; then
                errors+=("CRITIC reports reexecution_coverage=none_all_side_effects — all real EVIDENCE runs are side-effect-bearing (POST/PUT/DELETE/state-mutating), so critic could not verify any. Add at least one read-only safe-to-rerun verification run to EVIDENCE.json. Re-spawn critic.")
            fi
            if (( critic_accept_risk_weak > 0 )); then
                # Advisory only — surfaces to stderr regardless of ENFORCE mode below.
                # User judgment per slash command rubric: strengthen justification or implement.
                echo "discovery-gate: note — $critic_accept_risk_weak accept_risk entries have weak justification. Strengthen mitigation_note with concrete user-value trade-off or implement the fix." >&2
            fi
        fi
    fi
fi

# --- Decision ---
# allow_reason distinguishes clean-allow from advisory-with-errors so audit grep
# for allow_reason=="clean" excludes runs that surfaced issues even in advisory mode.
decision="allow"
allow_reason="clean"

if (( ${#errors[@]} > 0 )); then
    if (( ENFORCE == 1 )); then
        decision="block"
        allow_reason="errors_blocking"
    else
        decision="advisory"
        allow_reason="errors_advisory"
    fi
fi
[[ $critic_cap_reached -eq 1 ]] && allow_reason="critic_cap_reached"

# --- Log ---
jq -cn --arg ts "$ts" --arg decision "$decision" --arg areason "$allow_reason" \
    --argjson p "$premortem_count" --argjson pc "$premortem_categories" --argjson e "$evidence_count" \
    --argjson errn "${#errors[@]}" --arg req_critic "$REQUIRE_CRITIC" --argjson enforce "$ENFORCE" \
    --argjson cnc "$critic_new_critical" --argjson cdoc "$critic_documented" \
    --argjson ccu "$critic_critical_unaddressed" \
    --argjson carw "$critic_accept_risk_weak" \
    --arg crex "$critic_reexec_coverage" \
    --arg cev "$critic_evidence" --arg cblock "$critic_blocking_issue" \
    --argjson citer "$critic_iter_count" \
    '{ts:$ts, decision:$decision, allow_reason:$areason, enforce:$enforce,
      premortem_count:$p, premortem_categories:$pc, evidence_count:$e, errors_count:$errn,
      require_critic:$req_critic, critic_iter_count:$citer,
      critic_new_critical:$cnc, critic_documented:$cdoc,
      critic_critical_unaddressed:$ccu,
      critic_accept_risk_weak:$carw,
      critic_reexec_coverage:$crex,
      critic_evidence:$cev, critic_blocking_issue:$cblock}' \
    >> "$LOG_FILE" 2>/dev/null

# --- Surface ---
if (( ${#errors[@]} > 0 )); then
    {
        echo "=========================================="
        if (( ENFORCE == 1 )); then
            echo "EVALUATOR GATE: completion BLOCKED ($decision mode)"
        else
            echo "EVALUATOR GATE: ADVISORY — issues found, not blocking"
            echo "Set EVALUATOR_GATE_ENFORCE=1 in headless contexts to make this gate blocking."
        fi
        echo "=========================================="
        echo ""
        for err in "${errors[@]}"; do
            echo "  • $err"
            echo ""
        done
        echo "This gate is domain-agnostic — it enforces that you searched for"
        echo "failure modes and validated against reality, not which specific"
        echo "issues to find. That is your discovery work."
    } >&2

    if (( ENFORCE == 1 )); then
        exit 2  # block stop, force-continue
    fi
fi

exit 0
