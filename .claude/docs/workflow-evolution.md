---
owner: @nikitaCodeSave
last-updated: 2026-05-18
status: active
---

# Harness evolution workflow — Claude Code 2.1.143

> **«Harness matters more than the model»** — first-party doctrine, 2026-05-14. Это doc про то, **когда и как** harness переучивается под новые модели и накопленную empirics.
>
> Companion к [workflow.md](workflow.md) spine, [principles.md](principles.md) (current state), [benchmark.md](benchmark.md) (measurement methodology), [archive/decisions-2026Q2.md](archive/decisions-2026Q2.md) (frozen ADR log).

## TL;DR

3 empirical facts что переопределяют harness-engineering:

1. **First-party** (claude.com/blog 2026-05-14): *«Instructions tuned for older models constrain newer ones — review your configuration every 3-6 months.»*
2. **AHE ablation** (arXiv [2604.25850](https://arxiv.org/abs/2604.25850), 2026-04-28): harness gains localize to **tools, middleware, long-term memory** — **NOT system prompt**. «Factual harness structure transfers; prose-level strategy does not.» 84.7% pass@1 Terminal-Bench 2.
3. **AgentFlow** (arXiv [2604.20801](https://arxiv.org/abs/2604.20801), 2026-04-22): *«When the language model is held fixed, changing only the harness can still change success rates by **several-fold** on public agent benchmarks.»*

Implication: harness evolves through measurement, не intuition. Specifically — measurement against **structural components** (skills/hooks/agents/memory), не CLAUDE.md prose.

## Cadence

| Trigger | Action |
|---------|--------|
| **Major model release** (4.x → 5.x) | Full re-evaluation: principles.md + workflow.md spine + invariants |
| **Quarterly** (3-6 months per Anthropic) | Re-run benchmark, check anti-patterns list, retire stale rules |
| **First-party publishes update** к best practices | Sync within 30 days |
| **N≥3 empirical failures одного типа** | Add anti-pattern OR new rule (single-incident does NOT trigger) |
| **Community pattern достигает critical mass** (>50K stars OR Anthropic-featured) | Evaluate as opt-in extension |
| **Built-in каталог changes** (new agent/slash-command в `claude --help`) | Reconcile with custom components — delete duplicates |

## What to measure (per AHE ablation)

Tools / middleware / memory contribute; prose tunings do not transfer. Practical translation:

| Layer | Measure | Don't measure |
|-------|---------|---------------|
| **Tools** (hooks, slash-commands, skills) | Pass-rate delta on task suite | Number of lines added |
| **Middleware** (rules, validators, gates) | False-completion rate (target <5%) | Subjective "feels safer" |
| **Memory** (devlog, auto-memory, MEMORY.md curation) | Re-work rate at session start | Tokens used |
| **Subagents** (custom agents) | Spawn ROI (quality lift vs token cost) | Inventory size |
| **System prompt prose** (CLAUDE.md content) | Quality on calibration tasks | Length |

### Empirical baseline from THIS harness

- **2026-05-11, devlog #24**: ECC raw inject neutral but breaks pytest discovery (90+ parasitic tests). Our harness +24-27% cost vs no-harness baseline на T01/T02 simple tasks под Opus 4.7 при идентичном quality. **ROI ∝ ambient exploration cost** — see [benchmark.md](benchmark.md).
- **2026-05-11, devlog #26/27**: Ralph-loop self-improvement infrastructure validated через variance-checked fitness function + retire-bias=3 + protected-files guard. Cost envelope per iter: $1.30-2.50 benchmark-dominated.

## Retire ritual (current gap)

**SLIM** (arXiv [2605.10923](https://arxiv.org/abs/2605.10923), 2026-05-11) formalizes skill lifecycle: **retain / retire / expand** based on leave-one-skill-out marginal contribution. +7.1pp over baselines на ALFWorld and SearchQA.

Method requires RL (out of scope per CLI constraint), но **principle** портируется:

### What's missing у нас

Сейчас в harness'е:
- ✅ Skills add through `meta-creator` agent + manual review
- ✅ Anti-patterns retire через ADR (decisions-2026Q2.md)
- ❌ **No measurement-driven retire ritual** — skills удаляются по интуиции, не по data

### Proposed retire criteria (when adding)

Per skill / hook / agent / rule, track:
1. **Last invocation date** (через telemetry / hook event logs)
2. **Contribution to task pass-rate** (leave-one-out на calibration suite)
3. **Token cost when active**

Retire when:
- Last invocation >90 days
- Leave-one-out delta < +0.5pp (within variance)
- Token cost > value-added (negative ROI)

**Implementation pending** — это identified gap, не active mechanism. См. ADR roadmap в `principles.md`.

## What we know about harness evolution under CLI constraint

Most arXiv papers describing harness self-evolution (AHE, AgentFlow, Meta-Harness, Continual Harness, The Last Harness You'll Ever Build) require **automation-heavy outer loops** — RL training, evaluator-driven prompt rewrites, fitness-function search. Под наш [api-constraint.md](../rules/api-constraint.md) (CLI subscription only) полная репликация не in scope.

Portable **principles**:

| Paper | Principle | Our application |
|-------|-----------|-----------------|
| AHE ([2604.25850](https://arxiv.org/abs/2604.25850)) | Tools/middleware/memory > prose | Invest extension effort в skills/hooks/memory, не в CLAUDE.md prose |
| AgentFlow ([2604.20801](https://arxiv.org/abs/2604.20801)) | Joint search axes (roles + prompts + tools + topology) > single-axis | Multi-axis benchmark ablations — already partially in [benchmark.md](benchmark.md) |
| Meta-Harness ([2603.28052](https://arxiv.org/abs/2603.28052)) | Discovered harness +7.7pp at −75% tokens | Aggressive retire-bias justified empirically |
| 70-project survey ([2604.18071](https://arxiv.org/abs/2604.18071)) | Multi-level recursive = 12.9% corpus | Our restraint = deliberate, not default; D-022 opt-in для high-stakes |
| SLIM ([2605.10923](https://arxiv.org/abs/2605.10923)) | Lifecycle (retain/retire/expand) > creation-only | Identified gap → retire ritual proposal above |
| TDD Governance ([2604.26615](https://arxiv.org/abs/2604.26615)) | Bounded repair loops + atomic mutation control | `.claude/rules/testing.md` aligns; bound enforcement через `Stop` hook |

## Loop pattern under CLI constraint

`.claude/loop/` infrastructure (devlog #26-29, #41) — local adaptation of Anthropic's Ralph loop (Mishra-Sharma 2026, scientific computing) и Huntley's ralph-wiggum. Key elements:

- **Variance-checked fitness function** — n=3 multiplier per [benchmark.md](benchmark.md) Layer D
- **Retire-bias=3** — eliminate underperforming additions aggressively
- **Protected-files guard** — recursive modifications routed через proposal-only mode (avoid recursive failure)
- **Smoke validation** (per Bug 3 fix) pending — external fixtures + worktrees

Reference impl: `/ralph-loop` plugin in [anthropics/claude-plugins-official](https://github.com/anthropics/claude-plugins-official). Не enabled by default — see [builtins-inventory.md](builtins-inventory.md).

## Hermes-DIY cleavage

Community 2026 разделилась:

- **Hermes Agent v0.12** (NousResearch, 2026-04-30): out-of-the-box auto-curated MEMORY.md/USER.md/SOUL.md + rubric-based self-improvement loop. «Claude Code requires you to hand-craft the harness» framing.
- **Claude Code DIY** (наша позиция): explicit `.claude/` structure, manual evolution, measurement-driven.

Strategic position для этого harness: **DIY с empirical guard-rails**. Не копируем Hermes auto-curation wholesale (single-incident в invariant не превращается), но adopt portable patterns когда multi-source evidence (e.g., Monitor tool convergence).

## Anti-patterns (evolution-specific)

| Anti-pattern | Evidence | Replacement |
|--------------|----------|-------------|
| Adding skill/hook без measurement plan | AHE — gains ablation-dependent | Define metric до add |
| Retire-by-intuition | SLIM — leave-one-out empirical | Calibration suite + lifecycle check |
| CLAUDE.md prose tuning | AHE — prose doesn't transfer | Invest в tools/middleware/memory |
| Single-axis benchmark | AgentFlow — joint search wins | Multi-axis ablation (Layer B+C [benchmark.md](benchmark.md)) |
| Wholesale community framework adoption | feedback_no_external_tools_when_inline_suffices | Adopt patterns, not packages |
| One-shot benchmark run | benchmark.md Layer D — variance | n=3 multiplier |
| Re-evaluating only when broken | First-party 3-6 month cadence | Calendar-driven review |

## Sources

### First-party
- [claude.com/blog/how-claude-code-works-in-large-codebases-best-practices-and-where-to-start](https://www.claude.com/blog/how-claude-code-works-in-large-codebases-best-practices-and-where-to-start) (2026-05-14) — «harness matters more than model», 3-6 month review cadence
- [anthropic.com/engineering/harness-design-long-running-apps](https://www.anthropic.com/engineering/harness-design-long-running-apps) — Rajasekaran Mar 24 2026, «strip away unnecessary scaffolding»
- [anthropic.com/engineering/managed-agents](https://www.anthropic.com/engineering/managed-agents) — Apr 8 2026, «harnesses encode assumptions that go stale»

### Academic (2026 Q2)
- arXiv [2604.25850 — Agentic Harness Engineering](https://arxiv.org/abs/2604.25850) — Lin et al., 2026-04-28; AHE ablation (tools/middleware/memory > prompt)
- arXiv [2604.20801 — AgentFlow](https://arxiv.org/abs/2604.20801) — Liu et al., 2026-04-22; «changing only harness → several-fold delta»
- arXiv [2603.28052 — Meta-Harness](https://arxiv.org/abs/2603.28052) — Lee et al., Mar 2026; 76.4% TerminalBench-2 with discovered harness
- arXiv [2604.18071 — Architectural Design Decisions in AI Agent Harnesses](https://arxiv.org/abs/2604.18071) — Hu Wei, 2026-04-20; 70-project survey
- arXiv [2605.10923 — SLIM: Dynamic Skill Lifecycle Management](https://arxiv.org/abs/2605.10923) — 2026-05-11; retain/retire/expand pattern
- arXiv [2604.26615 — TDD Governance for Multi-Agent Code Generation](https://arxiv.org/abs/2604.26615) — Hasanli et al., 2026-04-29; bounded repair loops

### Reference harness
- [anthropics/claude-plugins-official → ralph-wiggum](https://github.com/anthropics/claude-plugins-official) — canonical Ralph loop plugin
- [github.com/china-qijizhifeng/agentic-harness-engineering](https://github.com/china-qijizhifeng/agentic-harness-engineering) — AHE paper official code

### Related docs
- [benchmark.md](benchmark.md) — 4-layer methodology + variance-checked fitness
- [principles.md](principles.md) — D-022 opt-in subagent isolation rationale
- [archive/decisions-2026Q2.md](archive/decisions-2026Q2.md) — frozen ADR log (ADR-002 TDD-triad ban, ADR-007 built-ins-first revisited, ADR-011 retire code-reviewer)
