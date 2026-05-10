# Tier 2: Per-Component Evals

Targeted accuracy checks для skills / agents.

## Per skill — trigger accuracy

Eval sets per skill (в `eval-sets/`):
- `<skill>-should-trigger.txt` — queries где skill SHOULD activate
- `<skill>-should-not-trigger.txt` — near-miss queries где skill MUST NOT activate (avoid false positives)

Each line — one query. Empty lines + `# comment` lines игнорируются.

Pass criteria: trigger accuracy ≥85% на held-out test split. Compute:
```
accuracy = (true_positives + true_negatives) / total
```

## Per agent — prompt corpus

Eval set: prompts that should/shouldn't spawn agent. Manual judge для invocation appropriateness (no automated metric — quality assessment requires human review).

## Per hook — N/A

Hook smoke tests covered в Tier 0 (`static-checks.sh`). Tier 2 — non-applicable.

## Runner

`run-tier2.sh`:
1. Validates eval set structure (paired should-trigger / should-not-trigger)
2. Counts entries per skill
3. Reports coverage

**Actual trigger evaluation manual** — requires Claude session с skill discovery enabled. Roadmap: automate через `claude --print "<query>" --json-schema '{...}'` parsing (OAuth-compatible; `--bare` out of scope).

## Components covered

| Component | Type | Trigger set | Negative set | Roadmap |
|-----------|------|:-----------:|:------------:|---------|
| devlog | skill | ✓ | ✓ | full auto runner |
| project-docs-bootstrap | skill | pending | pending | scaffolding |
| deliverable-planner | agent | pending | pending | corpus design |
| meta-creator | agent | pending | pending | corpus design |
