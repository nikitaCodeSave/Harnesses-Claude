---
description: Opt-in independent verification of a high-stakes deliverable via the discovery-critic subagent (Evaluator node of Planner→Generator→Evaluator).
allowed-tools: Read, Write, Bash, Glob, Grep, Task
argument-hint: [optional one-line description of the deliverable]
---

You are running an opt-in **Evaluator** pass on a high-stakes deliverable. This is the third node of the Planner→Generator→Evaluator pattern. The user invoked this command because they consider the work done and want a fresh-context adversarial review before declaring complete.

**When this command applies:** security-sensitive code, data migrations, new protocols, parsers of untrusted input, refactor of invariants, anything where silent-wrong-result cost is high. For typo fixes, single-file refactors, or doc-only changes — push back: tell the user this evaluator is overkill and skip it.

**Framing note**: `PREMORTEM.json` in this protocol is a *post-hoc failure-mode catalog*, not a Klein-style premortem ritual. The critic's independent probe (Phase 1) precedes PREMORTEM comparison (Phase 2) specifically to mitigate anchoring on the author's self-report.

## Standalone operation

This command + the `discovery-critic` agent are **self-sufficient**. `/critique` spawns the critic, parses the verdict via jq, and decides next steps directly — no hook or external infrastructure required. The optional Stop hook (`.claude/hooks/discovery-gate.sh`, opt-in via `EVALUATOR_GATE_ACTIVE=1` or `.claude/.evaluator-active` marker) is a **pre-/critique reminder**, not a gate — it nags about missing/incomplete PREMORTEM and EVIDENCE before agent stops, but never blocks (always exit 0). The actual verdict logic lives in this slash command's Step 3 rubric.

## Workflow

### Step 1 — Verify or produce input artifacts

The discovery-critic subagent reads two artifacts from cwd:

- **`PREMORTEM.json`** — failure-mode catalog (≥4 entries, ≥3 distinct categories)
- **`EVIDENCE.json`** — real-execution log (≥3 entries)

Auto-populate provenance so re-spawns on identical state are visible:

```bash
GIT_HEAD=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
GIT_DIRTY=$( [[ -z "$(git status --porcelain 2>/dev/null)" ]] && echo false || echo true )
PREV_ITER=$(test -f CRITIC.json && jq -r '.context.iter_round // 0' CRITIC.json 2>/dev/null || echo 0)
ITER_ROUND=$((PREV_ITER + 1))
```

Check each artifact:

```bash
# PREMORTEM — type, count, category spread, context block
test -f PREMORTEM.json \
  && jq empty PREMORTEM.json \
  && jq -e '.failure_modes | type == "array"' PREMORTEM.json \
  && jq -e '.failure_modes | length >= 4' PREMORTEM.json \
  && jq -e '[.failure_modes[].category] | unique | length >= 3' PREMORTEM.json \
  && jq -e '.context.git_head | type == "string"' PREMORTEM.json

# EVIDENCE — type, count, context block
test -f EVIDENCE.json \
  && jq empty EVIDENCE.json \
  && jq -e '.runs | type == "array"' EVIDENCE.json \
  && jq -e '.runs | length >= 3' EVIDENCE.json \
  && jq -e '.context.git_head | type == "string"' EVIDENCE.json
```

If either artifact is missing, schema-invalid, below the count threshold, fails category spread, or lacks `context` — **produce it yourself before spawning the critic**, populating `context` from `$GIT_HEAD`, `$GIT_DIRTY`, `$ITER_ROUND`. Do not delegate Step 1: the critic depends on this being honest discovery, not boilerplate.

#### PREMORTEM.json schema

```json
{
  "deliverable": "<one-line description of what was built>",
  "context": { "git_head": "<sha>", "dirty": false, "iter_round": 1 },
  "failure_modes": [
    {
      "title": "<short>",
      "category": "state|precondition|boundary|resource|concurrency|security|semantics|other",
      "trigger": "<concrete input or condition>",
      "impact": "<consequence>",
      "severity": "critical|major|minor",
      "mitigation_status": "addressed|documented_only|accept_risk",
      "mitigation_note": "<file:line if addressed; concrete user-value trade-off if accept_risk; empty if documented_only>"
    }
  ]
}
```

Think adversarially: ≥4 entries spanning ≥3 distinct categories. Don't pile 4 boundary findings — that bypasses the spread check on purpose.

#### EVIDENCE.json schema

```json
{
  "deliverable": "<one-line description>",
  "context": { "git_head": "<sha>", "dirty": false, "iter_round": 1 },
  "runs": [
    {
      "name": "Run 1: <what was tested>",
      "command": "<exact command executed>",
      "real_or_mock": "real|mock",
      "input": "<input given>",
      "observed_output": "<what actually happened>",
      "expected": "<expected behavior>",
      "outcome": "pass|fail|surfaced_bug",
      "notes": "<optional context>"
    }
  ]
}
```

At least 3 entries with `real_or_mock: "real"`. At least one of those entries should be **safe-to-rerun** (read-only, no side effects) — the critic re-executes one to verify the log is not a fake-real fabrication.

**For inherently-destructive deliverables** (DB migrations, deploy scripts, mutation-only endpoints, file-system writes without dry-run mode) — every "interesting" run is side-effect-bearing by nature. The critic will record `reexecution_coverage: none_all_side_effects` and the rubric will block. **Workaround**: add one read-only **post-state verification** run alongside the destructive run. Examples:

- migration applied → SELECT against the new schema (`psql -c "\\d new_table"` or `sqlite3 .schema`)
- file written → `ls -la created/file` or `head -5 output.csv`
- API POST → subsequent GET against the affected resource
- deploy → curl health endpoint, grep deployed version

Mark the verification run `safe-to-rerun` in the notes field. This satisfies re-execution coverage without forcing the original destructive run to be re-runnable.

### Step 2 — Spawn the critic

Prepare a scope hint (recommended for non-trivial repos):

```bash
DIFF_BASE="${DIFF_BASE:-HEAD~1}"
{
  git diff --stat "$DIFF_BASE"...HEAD 2>/dev/null
  echo "---"
  git diff "$DIFF_BASE"...HEAD --name-only 2>/dev/null
} > /tmp/critique-diff.txt
```

Spawn discovery-critic in a fresh context:

```
Task tool with:
  subagent_type: "discovery-critic"
  description:   "Adversarial review of <deliverable>"
  prompt:        "<brief: working dir, where deliverable lives, where spec is, project-specific context. Append: 'Scope: see /tmp/critique-diff.txt for the diff of files in this deliverable. Focus probing there; treat surrounding code as context only.'>"
```

The agent reads `PREMORTEM.json`, `EVIDENCE.json`, the code in cwd, and the scope hint. It writes `CRITIC.json` and exits. It does not modify code or input artifacts.

### Step 3 — Parse the verdict

When the critic returns, read `CRITIC.json`. **Counts come from arrays, not scalars.** Use case-folded comparison so capitalized variants are not silently missed — matches what the optional gate hook does.

#### Step 3a — Schema conformance check (BEFORE rubric)

The rubric below queries specific field paths and enum values. If the critic improvised the schema — renamed `overall_grade` → `grade`, invented a `FALSE_PREMISE` verdict, omitted `severity`, dropped the `context` block, returned an empty `premortem_verification[]`, or flagged inputs broken via `blocking_issue` — every rubric query silently falls back to its default (`0` / empty string) and a flawed deliverable passes as "all clear". Verify shape and coverage before parsing:

```bash
PV_LEN=$(jq '.premortem_verification | length' CRITIC.json 2>/dev/null)
PM_LEN=$(jq '.failure_modes | length' PREMORTEM.json 2>/dev/null)
LEN_OK="ok"
if ! [[ "$PV_LEN" =~ ^[0-9]+$ ]] || ! [[ "$PM_LEN" =~ ^[0-9]+$ ]] || (( PV_LEN < PM_LEN )); then
    LEN_OK="fail"
fi

SCHEMA_OK=$(jq -e '
    (.critic_version == "2.0")
    and (.context.git_head | type == "string")
    and (.context.iter_round | type == "number")
    and (.premortem_verification | type == "array")
    and (.new_findings | type == "array")
    and (.verdict.blocking_issue == null)
    and (.evidence_quality.overall_grade | IN("high","medium","low"))
    and (.evidence_quality.reexecution_coverage | IN("yes_at_least_one","none_all_side_effects","no_runs_real"))
    and ([.premortem_verification[].severity] | all(. as $s | ["critical","major","minor"] | index($s) != null))
    and ([.premortem_verification[].verdict] | all(. as $v | ["addressed","documented_only","unclear","accept_risk"] | index($v) != null))
    and ([.premortem_verification[].accept_risk_quality] | all(. as $q | ["justified","weak","unjustified","n/a"] | index($q) != null))
    and ([.new_findings[].severity] | all(. as $s | ["critical","major","minor"] | index($s) != null))
    and ([.new_findings[].category] | all(. as $c | ["state","precondition","boundary","resource","concurrency","security","semantics","other"] | index($c) != null))
    and ([.new_findings[].demonstrability] | all(. as $d | ["verified","reasoned"] | index($d) != null))
' CRITIC.json >/dev/null 2>&1 && echo ok || echo fail)

if [[ "$SCHEMA_OK" != "ok" || "$LEN_OK" != "ok" ]]; then
    SCHEMA_OK=fail  # collapse both signals into one for downstream branches
    echo "CRITIC.json does not conform to v2.0 schema — rubric cannot be applied safely."
    echo "Common drifts: renamed fields (grade vs overall_grade), invented verdicts (FALSE_PREMISE),"
    echo "missing severity/category/demonstrability, missing context block, nested reexecution object,"
    echo "empty premortem_verification[] (silently bypasses per-item filters), non-null blocking_issue."
    # Diagnostic: show which checks fail
    if [[ "$LEN_OK" != "ok" ]]; then
        echo "  FAIL: premortem_verification has ${PV_LEN:-?} entries; PREMORTEM has ${PM_LEN:-?} failure_modes (critic must verify every one)"
    fi
    for path in \
        '.critic_version == "2.0"' \
        '.context.git_head | type == "string"' \
        '.context.iter_round | type == "number"' \
        '.premortem_verification | type == "array"' \
        '.new_findings | type == "array"' \
        '.verdict.blocking_issue == null' \
        '.evidence_quality.overall_grade | IN("high","medium","low")' \
        '.evidence_quality.reexecution_coverage | IN("yes_at_least_one","none_all_side_effects","no_runs_real")' \
        '[.premortem_verification[].severity] | all(. as $s | ["critical","major","minor"] | index($s) != null)' \
        '[.premortem_verification[].verdict] | all(. as $v | ["addressed","documented_only","unclear","accept_risk"] | index($v) != null)' \
        '[.premortem_verification[].accept_risk_quality] | all(. as $q | ["justified","weak","unjustified","n/a"] | index($q) != null)' \
        '[.new_findings[].severity] | all(. as $s | ["critical","major","minor"] | index($s) != null)' \
        '[.new_findings[].category] | all(. as $c | ["state","precondition","boundary","resource","concurrency","security","semantics","other"] | index($c) != null)' \
        '[.new_findings[].demonstrability] | all(. as $d | ["verified","reasoned"] | index($d) != null)'
    do
        jq -e "$path" CRITIC.json >/dev/null 2>&1 || echo "  FAIL: $path"
    done
fi
```

Note on the cross-length check: an empty or truncated `premortem_verification[]` is the most insidious drift — every per-item jq filter (`CRITICAL_UNADDRESSED`, `MAJOR_RATIO`, `ARISK_WEAK`) returns 0 on an empty array, so the rubric passes vacuously. Verifying `PV_LEN ≥ PM_LEN` against the actual `PREMORTEM.json` forces the critic to address every documented failure mode. `PV_LEN > PM_LEN` (duplicates/extras) does not fail this check by itself — the enum and value checks above catch malformed entries.

**On schema fail** — do **not** proceed to the rubric below. The deliverable status is *unverified*, not "clean". Two options:

1. **Re-spawn the critic once** with an explicit reminder: «`CRITIC.json` violated the v2.0 schema (cite the failing paths). Fix it without modifying findings — use the exact field names, enum values, and `context` block as declared in your agent definition. Run the self-validation snippet from your prompt before exiting.»
2. **If a second pass still fails** — surface the schema drift to the user and stop. Do not paper over it with a "all clear" verdict; the gate is non-functional under drift.

Schema-conformance is a deliverable from the critic, on par with the findings themselves.

#### Step 3b — Rubric (only after Step 3a passes)

```bash
# Critical findings in new_findings[]
NEW_CRITICAL=$(jq '[.new_findings[]
    | select((.severity // "" | ascii_downcase | gsub("\\s"; "")) == "critical")] | length' CRITIC.json)

# Class-based "critical not safely resolved" — severity dominates verdict.
# Blocks ANY critical-severity entry except those with verdict=addressed OR
# (verdict=accept_risk AND accept_risk_quality=justified). All other verdicts
# (documented_only, unclear, accept_risk+weak, accept_risk+unjustified, accept_risk+n/a,
# unknown) block. All comparisons case-folded and whitespace-stripped.
CRITICAL_UNADDRESSED=$(jq '[.premortem_verification[]
    | select((.severity // "" | ascii_downcase | gsub("\\s"; "")) == "critical")
    | select(
        ((.verdict // "" | ascii_downcase | gsub("\\s"; "")) != "addressed")
        and (
            ((.verdict // "" | ascii_downcase | gsub("\\s"; "")) != "accept_risk")
            or ((.accept_risk_quality // "" | ascii_downcase | gsub("\\s"; "")) != "justified")
        )
    )] | length' CRITIC.json)

# Major-severity documented_only ratio (>0.3 → too many major items unaddressed)
MAJOR_RATIO=$(jq '
    [.premortem_verification[]
       | select((.severity // "" | ascii_downcase | gsub("\\s"; "")) == "major")] as $major
    | ($major | length) as $total
    | ($major
         | map(select((.verdict // "" | ascii_downcase | gsub("\\s"; "")) == "documented_only"))
         | length) as $undone
    | if $total == 0 then 0 else ($undone / $total) end' CRITIC.json)

# accept_risk entries with weak justification — surface to user, not auto-block
# (critical+accept_risk+weak is already caught by CRITICAL_UNADDRESSED above)
ARISK_WEAK=$(jq '[.premortem_verification[]
    | select((.accept_risk_quality // "" | ascii_downcase | gsub("\\s"; "")) == "weak")] | length' CRITIC.json)

# EVIDENCE grade + reexecution coverage
EVIDENCE_GRADE=$(jq -r '.evidence_quality.overall_grade // ""' CRITIC.json | tr '[:upper:]' '[:lower:]' | tr -d ' ')
REEXEC=$(jq -r '.evidence_quality.reexecution_coverage // ""' CRITIC.json | tr '[:upper:]' '[:lower:]' | tr -d ' ')

# Human-readable summary
jq '.verdict' CRITIC.json
jq '.new_findings[] | select((.severity // "" | ascii_downcase | gsub("\\s"; "")) == "critical")' CRITIC.json
jq '.premortem_verification[]
    | select((.severity // "" | ascii_downcase | gsub("\\s"; "")) == "critical")
    | select(
        ((.verdict // "" | ascii_downcase | gsub("\\s"; "")) != "addressed")
        and (
            ((.verdict // "" | ascii_downcase | gsub("\\s"; "")) != "accept_risk")
            or ((.accept_risk_quality // "" | ascii_downcase | gsub("\\s"; "")) != "justified")
        )
    )' CRITIC.json
jq '.evidence_quality' CRITIC.json
```

**Class-based decision rubric** (guidelines, not gates — apply judgment; counts come from arrays):

- **`NEW_CRITICAL > 0`** → fix in code, then re-invoke `/critique` for another pass.
- **`CRITICAL_UNADDRESSED > 0`** → critical-severity PREMORTEM item NOT safely resolved. The only safe verdicts for critical-class are `addressed` (fixed in code) or `accept_risk` with `accept_risk_quality=justified` (concrete trade-off named). All other verdicts block: `documented_only`, `unclear`, `accept_risk+weak`, `accept_risk+unjustified`, `accept_risk+n/a` (inconsistent), unknown verdicts (fail-safe). *Severity dominates verdict — this is a single class-based filter replacing earlier symptom-specific patches.*
- **`MAJOR_RATIO > 0.3`** → more than 30% of major items unaddressed. Implement or move to accept_risk; re-invoke.
- **`ARISK_WEAK > 0`** → surface to user. Either strengthen `mitigation_note` with concrete trade-off, or implement the fix. Human judgment, not auto-block.
- **`EVIDENCE_GRADE = low`** → EVIDENCE coverage insufficient (mocks, no failure surfaces, narrow coverage). Add real runs targeting trap/edge/error paths; re-invoke.
- **`REEXEC = none_all_side_effects`** → all real runs are side-effect-bearing; critic could not verify any. Add at least one read-only verification run; re-invoke.
- **All clear** → deliverable passes Evaluator. Report findings summary to the user. Suggest commit if changes are uncommitted.

### Step 4 — Report

Summarize to the user in plain language: deliverable, what the critic found (or confirmed clean), what was changed in response, and the final verdict counts. Do not dump raw `CRITIC.json` — extract the human-relevant signal.

## Bounds

- **Iteration cap**: at most 3 critic passes per deliverable. Track via `context.iter_round` — `/critique` auto-increments it from the previous CRITIC. If round 3 still reports `NEW_CRITICAL > 0` or `CRITICAL_UNADDRESSED > 0`, surface to the user — the loop is not converging and human judgment is needed.
- **Scope**: critic is READ-ONLY except for writing `CRITIC.json`. It does not fix issues. Fixes are the main agent's job between rounds.

## Anti-patterns

- **Do not skip Step 1**. A weak PREMORTEM produces a weak critic pass. The discovery work is yours, not the subagent's.
- **Do not invoke for trivial work**. The cost (extra context, extra agent spawn, ~Opus model time) is wasted on changes the model handles reliably solo.
- **Do not silence findings by editing them out of PREMORTEM**. Either fix in code, mark `accept_risk` with concrete justification, or accept the critic's verdict — the audit trail matters.
- **Do not run two critics in parallel** on the same deliverable. Parallel critics without shared context produce inconsistent verdicts (Cognition «don't build multi-agents»).
- **Do not stuff PREMORTEM with 4+ findings in one category** to clear the count check. The spread requirement (`≥3 distinct categories`) is enforced via jq in Step 1.
