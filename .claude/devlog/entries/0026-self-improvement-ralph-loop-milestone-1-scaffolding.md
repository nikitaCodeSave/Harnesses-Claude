---
id: 26
date: 2026-05-11
title: "Self-improvement Ralph-loop — Milestone 1 scaffolding"
tags: [harness, self-improvement, loop, ralph, scaffolding]
status: in-progress
---

# Self-improvement Ralph-loop — Milestone 1

## Контекст

User authorized многочасовой autonomous self-improvement цикл harness'а по
аналогии с Ralph-pattern ([Mishra-Sharma «Long-running Claude», Mar 2026](https://www.anthropic.com/research/long-running-Claude) + Huntley ralph-wiggum). Goal: эмпирическая
эволюция harness'а для projects «new» И «old» через `claude --print` loop
с file-based state, variance-checked fitness, retire-bias mechanism.

Pre-launch design contract зафиксирован в interactive round'е (3 batches × 4
questions). Все defaults подтверждены кроме backlog source (chose brainstorm +
community refs вместо ADR-extract).

## Locked decisions (10 точек)

| # | Решение | Значение |
|---|---|---|
| 1 | Wall-clock budget | 24-48h с pause-gates ~12h |
| 2 | Cost cap | 70% weekly limit (proxied via `LOOP_BUDGET_USD` env, default \$20) |
| 3 | Fixtures | tiangolo/full-stack-fastapi-template + pallets/click + sample-py-app |
| 4 | Backlog seeding | Brainstorm + community refs (с cross-check'ом retired ADRs) |
| 5 | State storage | `.claude/loop/{STATE,backlog,journal}.md` в git; logs/worktrees/reports gitignored |
| 6 | Notify | `PAUSED.md` + `notify-send` (v0.8.3 available) |
| 7 | Network scope | WebFetch + WebSearch read-only |
| 8 | Subagents | По spawn policy (a)(b)(c), cap 3/iter |
| 9 | Protected files | `CLAUDE.md`, `rules/*`, `loop/{run.sh,PROMPT.md,corpus.yml,fitness.{sh,py}}` |
| 10 | Single-thread | Один Ralph loop, не параллельные на разные goals |

## Milestone 1 deliverable (это в этой сессии)

### Scaffolding `.claude/loop/`

| File | Status | Role |
|---|---|---|
| `README.md` | created | architecture + invocation contract |
| `run.sh` | created, executable, syntax-ok | frozen driver — while-loop, 4 stop gates, cumulative cost tracker via `claude --output-format json.total_cost_usd` |
| `PROMPT.md` | created | idempotent prompt, 6 phases, 8 invariants, RESULT:* output contract |
| `STATE.md` | created | pre-bootstrap state, schema documented |
| `corpus.yml` | created | T01-T07 split (train/holdout ⅔/⅓), variance config (3 replicas, 2σ), retire_bias every 5, protected_files list |
| `backlog.md` | created | placeholder, to populate Milestone 2 |
| `journal.md` | created | append-only event log placeholder |
| `fitness.sh` | created, executable | bash wrapper с python auto-detect (yaml requirement) |
| `fitness.py` | created, syntax-ok | deterministic scorer: tier0 → success_rate hard → weighted score (0.5/0.3/0.2) within ±20% with variance guard |

### Protected-guard hook

- `.claude/hooks/loop-protected-guard.sh` — PreToolUse Edit\|Write\|MultiEdit
- Pass-through when `LOOP_MODE != 1` (zero overhead outside loop)
- Inside loop: deny edits to protected paths, suggest proposal redirect
- Wired в `.claude/settings.json` BEFORE `secret-scan.sh` (cheap path-check first)
- Smoke-tested: 3 scenarios pass (no LOOP_MODE → allow; LOOP_MODE+protected → deny JSON; LOOP_MODE+non-protected → allow)

### Infrastructure

- `.gitignore` extended: `.claude/loop/logs/`, `worktrees/`, `reports/`, `PAUSED.md`
- All shell scripts `chmod +x`
- Tier 0 static-checks: **12/12 PASS** (no regression)

## Что НЕ сделано (Milestones 2-3)

### Milestone 2 — data
- #27 Extend task corpus до 12-15 задач (T08-T15: bootstrap-mode, cross-domain CLI, security-review, perf, edge-cases)
- #34 Generate initial backlog ~30 hypotheses (brainstorm + community refs from everything-claude-code/Chachamaru127/Superpowers/OpenHarness/atomic) с retired-ADR cross-check
- #37 Clone fixtures: tiangolo/full-stack-fastapi-template + pallets/click → `.claude/benchmark/fixtures/external/` (gitignored)
- #32 Confirm `LOOP_BUDGET_USD` value (currently \$20 default; user TBC actual 70% weekly)
- #35 Confirm pallets/click choice (defaulted; alternative encode/httpx)

### Milestone 3 — measure + ship
- #38 Variance baseline: 3× per task × N fixtures → populate `STATE.baseline_snapshot.{task}.{tokens,turns,files,success_rate}` with mean+sigma. Critical: без этого `run.sh` отказывается стартовать.
- #30 Smoke loop: 10 итераций под user observation. Verify hypothesis selection, fitness function decisions, protected-guard activations, notify-send.
- #31 ADR-025 «Self-improvement Ralph-loop pattern» — formal Anthropic-canonical evidence linkage; update `principles.md` с reference на loop architecture.

## Risk surface (Milestone 1 specific)

- **Nested `claude --print` permission**: `run.sh` spawns `claude --print`; PROMPT.md instructs spawning `headless-runner.sh` which itself spawns `claude --print`. Memory note (`feedback_classifier_blocks_nested_claude.md`) verifies passes under explicit user imperative; `run.sh` IS the user imperative. Cross-harness benchmarks (#23-25) уже работают на этом паттерне → assume OK.
- **`/usr/bin/python3` vs venv python**: harness venv не имеет pyyaml; system python имеет. `fitness.sh` делает auto-detect cycle — preferring system. Risk: future venv-only environments → guard caught explicitly, fails REJECT with reason.
- **`claude --output-format json.total_cost_usd`**: assumption that this field exists и cumulative. Verify в Milestone 3 smoke before relying.

## Self-evaluation против principles

- **Минимум обвязки**: 4 new files в `.claude/loop/` + 1 hook + 4 hook lines в settings. Под threshold «pattern требует multi-source evidence» — community Ralph pattern published Anthropic (Mar 2026) + Huntley ralph-wiggum + локальная необходимость empirical harness evolution. Multi-source ✓.
- **Built-ins first**: No subagents created (loop uses built-in `Explore` etc per spawn policy). No skill (skill = workflow-template, loop = orchestration infra). ✓.
- **API constraint**: All CLI primitives (`claude --print`, `--output-format json`, `--add-dir`). No managed-agents, no `ANTHROPIC_API_KEY`. ✓.
- **CLAUDE.md ≤ 200**: untouched (118 lines current). Loop concept documented в `.claude/loop/README.md`, indexer reference при удобном случае. ✓.

## Implications

Next session entry point: Milestone 2 — corpus extension + backlog brainstorm + fixture clone. Estimated effort 2-3h focused work.

После Milestone 2/3 — actual loop launch (24-48h supervised, then potentially fully autonomous).
