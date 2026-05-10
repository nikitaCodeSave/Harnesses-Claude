---
id: 19
date: 2026-05-10
title: "D-022 subagent isolation opt-in"
tags: [adr, harness, workflow, research]
status: complete
---

# D-022 subagent isolation opt-in plus Anthropic-canon patterns

## Контекст

Пользователь дал две директивы (2026-05-10):

1. «Допустимо должно быть всё что повышает качество разработки и кодинга для Claude Code DD и TDD, прочитай последние презентации и встречи Anthropic» → формализовать D-022 reconcile'ивающий ADR-002 (запрет mandatory TDD-тройки) с opt-in допуском для high-stakes features на основе Anthropic-first-party material.
2. «AGENTS.md сейчас сконцентрируйся только на Claude Code» → skip cross-vendor AGENTS.md support.

Дополнительный first-party + community корпус: Claude Agent SDK overview (v0.2.111+ для Opus 4.7), Claude Managed Agents beta (cloud-hosted Planner/Generator/Evaluator через `managed-agents-2026-04-01`, API-only), claude-code-harness (Chachamaru127 — formal Plan→Work→Review reference), everything-claude-code (Anthropic Hackathon winner, AgentShield TDD pipeline на 3 Opus агентах), OpenHarness/Ohmo (HKUDS — полная open arch), Atomic (Lavaee — portable workflow toolkit), awesome-claude-code-subagents (VoltAgent — 100+ subagents с tier'ed permissions), awesome-harness-engineering (ai-boost — meta-cheatsheet + claude-devtools), learn-claude-code (shareAI-lab — 12 reverse-engineered sessions), Inside the Agent Harness (J. Fulton — code-level разбор), и **leaked Claude Code internals March 2026** (generativeprogrammer.com — 12 architectural patterns).

## Research

Запущен 1 параллельный subagent (general-purpose) для опроса Anthropic-first-party talks/presentations/blog 2026 (Cherny, Rajasekaran, Carlini, Mishra-Sharma, Latent Space, AI Ascent, Lightcone, code.claude.com/best-practices 2026). Ключевые направления Anthropic 2026:

- **TDD positioning**: Cherny 2025 «Anthropic-favorite workflow для changes easily verifiable with tests» (opt-in) → Cherny 2026 reframe: «Give Claude a way to verify its work — single highest-leverage thing» (verification universal, TDD один из методов).
- **Planner→Generator→Evaluator**: Rajasekaran Mar 24 2026 canonical pattern для long tasks. Cost-justification: «worth когда task sits beyond what current model does reliably solo» (hard threshold).
- **Verifier near-perfect**: Carlini Feb 2026 — «task verifier nearly perfect, otherwise Claude solves wrong problem».
- **Self-praise failure mode**: Rajasekaran — «agents confidently praise obviously mediocre work» → Generator/Evaluator separation как mitigation.
- **Multi-agent ill-suited для most coding**: still canonical 2025-2026 position. Carve-out для high-stakes — explicit допустим.

## Изменения

### `.claude/docs/principles.md` (+24 lines)

- **Testing section** (line 49): уточнена formulation — `TDD/BDD как **обязательная** мета-обвязка ... — anti-pattern. **Opt-in** для high-stakes features — разрешён (см. D-022).`
- **Anti-patterns section**: PM-pipeline + Generator/Evaluator-per-sprint уточнены — запрещены только как **mandatory**, opt-in для high-stakes разрешён (см. D-022, Anthropic Harness Design Mar 2026).
- **D-022** добавлен в Decision log (tight format, ~22 строки): subagent isolation patterns (TDD triad, Driver-Navigator Opus+Sonnet, Planner→Generator→Evaluator) допустимы opt-in для high-stakes/production-critical/security-sensitive coding когда измеримо повышают quality. Counter-evidence to revise: N≥3 эмпирических кейса worse outcome. Supersedes ADR-002 + anti-patterns lines уточнениями.

### `.claude/docs/workflow.md` (+~80 lines)

- **Phase 2 «Опциональное расширение»** полностью переписана — теперь явные 3 patterns с Anthropic citations:
  - Pattern 1: Planner → Generator → Evaluator (Anthropic canonical, Rajasekaran Mar 2026 + leaked Claude Code Mar 2026)
  - Pattern 2: TDD triad (AgentCoder 87.8% vs 61% evidence + AgentShield ECC реализация)
  - Pattern 3: Driver-Navigator (Opus Navigator + Sonnet Driver)
  - Default vs opt-in criteria explicit
  - Reference implementation: claude-code-harness (Chachamaru127)
  - API constraint reminder: Managed Agents API-only, patterns переносятся на CLI primitives
- **Architectural patterns section** (новая, перед API constraint) — 6-row table с patterns из leaked Claude Code March 2026: Planner→G→E, tiered memory, progressive compaction 5 stages, tool gating <20 tools, subagent isolation, hooks pipeline 27 events. Каждый pattern — с applicability note для нашего harness'а.
- **Notable community references table** расширена: добавлены **everything-claude-code (Anthropic Hackathon winner)**, **claude-code-harness (formal Plan→Work→Review)**, OpenHarness/Ohmo, Atomic, awesome-claude-code-subagents, awesome-claude-code, awesome-harness-engineering (+ claude-devtools mention), learn-claude-code.
- **Sources section** extended: добавлены Claude Agent SDK overview, Claude Managed Agents (с API-only пометкой), Building a C compiler (Carlini Feb 2026), Long-running Claude (Mishra-Sharma Mar 2026), How Anthropic teams use Claude Code, Boris Cherny videos (AI Ascent / Lightcone / Latent Space). Notable harness repos + meta-resources section reorganized. Architectural analysis subsection (generativeprogrammer + Inside the Agent Harness).

## Принципиальные выводы

1. **D-022 reconcile**: harness phase explicit «opt-in subagent isolation для quality gain — allowed; mandatory pipeline за каждый task — by-default запрещён». Это закрывает gap между ADR-002 (запрет на mandatory) и community evidence (87.8% vs 61% AgentCoder, 90.2% Opus lead + Sonnet subagents, AgentShield production usage).

2. **Anthropic-canon Planner→Generator→Evaluator**: pattern признан Anthropic-canonical в Mar 2026 Rajasekaran post + Apr 2026 leaked source. Hard cost-threshold формулировка («worth когда beyond solo capability») — не default, но allowed opt-in. Translates на CLI primitives: Task tool spawn Planner agent → Generator main thread (или second spawn) → Evaluator spawn (read-only review).

3. **Claude Agent SDK / Managed Agents**: API-driven, **out of scope** для harness'а (CLI subscription only). Но **архитектурные паттерны** из SDK / Managed Agents translatable на CLI primitives — это и есть «концепции переносятся при условии полной реализации на CLI-примитивах» (CLAUDE.md API constraint).

4. **AGENTS.md cross-vendor**: skipped per user directive — фокус только на Claude Code.

## Затронутые файлы

- `.claude/docs/principles.md` — 3 правки (Testing line + Anti-patterns lines + D-022 append)
- `.claude/docs/workflow.md` — 4 правки (Phase 2 опц. расширение rewrite, Architectural patterns new section, Notable refs expansion, Sources expansion)
- `.claude/devlog/entries/0019-...` — эта запись

## Проверка

```bash
$ wc -l .claude/docs/principles.md .claude/docs/workflow.md
   ~108 .claude/docs/principles.md  (D-021 + D-022)
   ~450 .claude/docs/workflow.md
$ python3 .claude/devlog/rebuild-index.py
index.json updated: 19 entries
$ bash .claude/benchmark/static-checks.sh
=== ALL AUTOMATED CHECKS PASSED ===  (включая principles.md ≤200 строк + D-022 ≤30 строк)
```

## Related

- #18 — workflow.md Plan→Work→Review canonical spine (предусловие)
- ADR-002 в archive (запрет TDD-тройки) — D-022 уточняет, не отменяет
- memory `feedback_grow_with_community.md` — закрепляет research-first принцип (применён в этой итерации)
- D-021 — two-tier docs split (active layer допускает editable inline updates как этот rewrite)
