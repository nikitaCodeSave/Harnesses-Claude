---
id: 18
date: 2026-05-10
title: "workflow.md Plan→Work→Review canonical spine"
tags: [docs, harness, workflow, research]
status: complete
---

# workflow.md: Plan→Work→Review canonical spine (Anthropic + Boris)

## Контекст

Пользователь дал critical feedback: harness слишком опирался на свои же ранее зафиксированные ADR'ы как ground truth, не консультируясь с первоисточниками (Anthropic engineering blog, claude.com docs, GitHub репозитории, community 2026 essays). Это приводило к stale решениям и пропуску новых practices.

Зафиксировано в memory: `feedback_grow_with_community.md` — при значимых решениях опрашивать first-party и community sources, **before** опоры на внутренние ADR'ы.

Также пользователь указал canonical spine для нового workflow doc'а: **Plan → Work → Review** — основной подход Anthropic, рекомендованный Boris Cherny (создатель Claude Code).

## Изменения

Создан `.claude/docs/workflow.md` (~330 строк) как canonical development workflow для harness'а. Структура:

1. **Core spine** — Plan → Work → Review three-phase, single main thread Opus 4.7, subagents on demand
2. **Phase 1 Plan** — когда / инструменты (Plan mode, ultrathink, xhigh effort, deliverable-planner) / outputs / evidence
3. **Phase 2 Work** — single-thread default, testing.md инварианты, TodoWrite tracking, subagent spawn policy (a)(b)(c) triggers, model assignment matrix, опциональное расширение subagent TDD isolation для high-stakes
4. **Phase 3 Review** — layered (self / `/review` / code-reviewer / ultrareview / human), two-gate validation, feature-specific reviewer agents, doc + devlog updates
5. **Extensions** — для refactor / security / high-stakes / quick-fix scenarios
6. **Anti-patterns 2026** — empirical evidence (yunbow CLAUDE.md experiment, SonarSource 16.4%, false-completion 35%→4%, etc.)
7. **What's NEW in 2026** — adaptive thinking, xhigh effort, @docs imports, paths:-scoped rules, skill auto-discovery в subagents
8. **What's RETIRED** — fixed thinking budgets, monolithic CLAUDE.md, generic personas, vibe coding, etc.
9. **API constraint** — CLI subscription only
10. **Notable community references** — Superpowers (124K+ stars), ECC, claude-code-workflows, Karpathy template, devlog-mcp
11. **Re-evaluation triggers** — when to update doc
12. **Sources** — 17+ first-party + 13+ community с retrieval date

`.claude/CLAUDE.md` Reference materials section дополнен ссылкой на `workflow.md`.

## Research methodology

Перед написанием spawn'нул 2 параллельных subagent'ов (auto mode parallel research per multi-agent baseline §2.1 trigger «a + b»):

- **Agent 1 (claude-code-guide)**: Anthropic first-party — claude.com/blog, anthropic.com/engineering, docs.claude.com, anthropics/skills GitHub
- **Agent 2 (general-purpose)**: community 2026 — ofox.ai, boringbot, blakecrosley, mcp.directory, developersdigest, dev.to, community GitHub repos

Каждый агент вернул structured summary (~2500-3500 words) с per-stage evidence + citations. Main thread synthesize'нул в canonical workflow.md frame Plan→Work→Review per директива пользователя.

## Принцип

Workflow.md — **active layer reference**, on-demand reading (не auto-loaded). Точка для main thread'а при работе над фичей: вспомнить current best practices, sync с community pulse, avoid drift в self-referential ADR loop.

Key insights, которые требуют переоценки old internal ADR'ов:

- **ADR-002 (запрет TDD-тройки)** — community evidence показывает что subagent TDD isolation работает для high-stakes features (AgentCoder 87.8% vs 61%). В workflow.md формулировано как **опциональное расширение**, не default. ADR-002 запрещал **обязательный** pipeline; opt-in для подходящих задач не запрещён.
- **CLAUDE.md ≤200 lines** — empirical evidence от yunbow (79%→96.9% quality) подтверждает existing rule 2.
- **Plan mode + ultrathink combo** — explicit Anthropic recommendation, добавлено в Plan phase.

## Затронутые файлы

- `.claude/docs/workflow.md` — новый, ~330 строк canonical
- `.claude/CLAUDE.md` — Reference materials расширен ссылкой на workflow.md
- `.claude/devlog/entries/0018-workflow-md-plan-work-review-canonical-spine.md` — эта запись

Plus раньше в сессии (entry #17): миграция `docs/` → `.claude/docs/` (self-contained harness).
Plus раньше в сессии: memory `feedback_grow_with_community.md` зафиксирован.

## Проверка

```bash
$ wc -l .claude/docs/workflow.md
~330 .claude/docs/workflow.md

$ python3 .claude/devlog/rebuild-index.py
index.json updated: 18 entries

$ bash .claude/benchmark/static-checks.sh
=== ALL AUTOMATED CHECKS PASSED ===
```

## Related

- #17 — harness self-contained: docs moved to .claude/docs/ (предусловие для workflow.md size без budget'а)
- memory `feedback_grow_with_community.md` — закрепляет принцип research-first, не зацикливаться на внутренних ADR
- ADR-002 в archive (запрет TDD-тройки) — workflow.md reconcile'ит с community evidence как opt-in extension
- docs-discipline.md rule 2 (CLAUDE.md ≤200 lines) — подтверждён community empirical evidence

## Open questions для пользователя

1. ~~**ADR-002 reconcile**~~ — **resolved by #19** (D-022 формализован 2026-05-10).
2. ~~**AGENTS.md cross-vendor standard**~~ — **resolved 2026-05-10**: skipped per user directive, фокус только на Claude Code.
3. **@docs/file.md import syntax**: новая 2026 фича для CLAUDE.md modular loading. Использовать ли в проектном CLAUDE.md template? Open.
