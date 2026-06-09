# Staleness A/B — project-docs-bootstrap skill (retire evidence)

**Date:** 2026-06-09 · **Model:** Opus 4.8 · **Target:** `full-stack-fastapi-template` (tiangolo) — multi-component FastAPI+SQLAlchemy backend / React+TS+bun frontend, no canonical `docs/`.

## Question
Does `project-docs-bootstrap` (phase algorithm + per-doc charter + skeletons) add a reproducible, material quality lift over **native Opus 4.8 + WORKFLOW.md §3 + docs-discipline.md**? (WORKFLOW.md §125 staleness ritual, empirical per `feedback_empirical_over_theoretical_dismiss`.)

## Method
Isolated fixture clone per arm via `claude --print` (bypassPermissions, no-session-persistence). Minimal representative harness injected in both arms (WORKFLOW.md + docs-discipline + testing rule + neutral CLAUDE.md); **only difference = presence of the skill**. Three independent **blind** judges (scrambled set labels, reverse-scrambled in round 2) scored both outputs against the real codebase. n=2.

## Runs

| Run | Arm | Skill invoked | docs | frontmatter | boilerplate | npm-vs-bun hallucination |
|---|---|---|---|---|---|---|
| A  (r1) | skill ON          | yes (1×)        | 4 | 4/4 | 0 | clean ✓ |
| B  (r1) | native (skill OFF)| —               | 5 (+ADR) | 5/5 | 0 | **present** |
| A2 (r2) | skill available   | **no (0×)**     | 4 | 4/4 | 0 | **present** |
| B2 (r2) | native (skill OFF)| —               | 4 | 4/4 | 0 | clean ✓ |
| A3 (r2) | skill FORCED      | yes (2×)        | 4 | 4/4 | 0 | **present** |

## Blind-judge verdicts
- **Round 1, judge 1 (quality):** `equivalent, no material difference` (24:24). Native(B) bonus = accurate ADR; skill(A) bonus = caught no-`create_all`/issue-#28 + tz-aware UTC.
- **Round 1, judge 2 (accuracy skeptic):** `skill-arm slightly better` (med-high) — only because native(B) had the npm hallucination; skill(A) 0 hallucinations.
- **Round 2, judge (accuracy skeptic):** `native(B2) materially better` (high) — mirror image: this time the **skill-available** arm (A2) had the npm hallucination, native(B2) clean.

## Conclusion → RETIRE
1. **Full discipline in all 5 runs regardless of skill** — canonical layout, owner+last-updated on every doc, zero boilerplate. The discipline the skill encodes is produced natively.
2. **The npm-vs-bun hallucination flips arms across rounds** (clean: A, B2; present: B, A2, A3) and **persists even with the skill forced-invoked (A3)** → model-level fact-variance, orthogonal to the skill; the skill does not fix it.
3. **The skill does not reliably trigger** (A2: available but not invoked; output equivalent).
4. ADR appeared once (native, r1) — variance, not structural.

All inter-arm differences attributable to one variance hallucination, not the skill. **No reproducible material lift** → skill's skeletons/charter/phases are not load-bearing. Consistent with foundational principle (component encoding "model can't do X" where it now does X natively) and prior retirements (`sync-docs`, `harness-setup`). Value retained in `WORKFLOW.md §3` + `.claude/rules/docs-discipline.md`.

Raw doc outputs of all 5 runs: `outputs/run-{A,B,A2,B2,A3}/`.
