---
id: 20
date: 2026-05-10
title: "principles.md rewrite evidence-based"
tags: [docs, harness, refactor, research]
status: complete
---

# principles.md rewrite as evidence-based self-contained doc

## Контекст

Пользователь дал директиву (2026-05-10): «`.claude/docs/principles.md` отсылки к ADR — этого быть не должно, отсылки к архивной информации, ознакомься с документацией Anthropic, Claude code и полностью перепиши документ согласно лучшим рекомендациям вспомогательным докам для Claude code. Используй Интернет как источник верефицированной информации и достоверных источников».

Прежняя версия principles.md (~97 строк) содержала:
- Decision log section с D-021 / D-022 ссылающимися на ADR-002 / ADR-007 / etc.
- Архивные refs «Полный исторический rationale — archive/decisions-2026Q2.md»
- Anti-patterns с inline references на retired ADRs
- Process discipline с «ADR id'ы из archive (002-020) канонические»

Эти отсылки создавали зависимость от archive layer и frozen historical context, противоречя цели self-contained current-state doc'а.

## Research

Запущен claude-code-guide subagent для targeted research свежей Anthropic Claude Code documentation 2026. Опрошены canonical sources:

- docs.claude.com: overview / best-practices / sub-agents / skills / hooks / memory / settings / common-workflows / code-review
- anthropic.com/engineering: effective-harnesses-for-long-running-agents / harness-design-long-running-apps (Rajasekaran Mar 2026) / multi-agent-research-system
- claude.com/blog: best-practices-for-using-claude-opus-4-7-with-claude-code
- github.com/anthropics/skills

Извлечены canonical Anthropic principles per category (foundational philosophy, skills, subagents, hooks, memory, settings, testing, documentation, anti-patterns) с direct quotes + URL citations.

## Изменения

### `.claude/docs/principles.md` (полная перезапись, 97 → 123 строки)

Структурно:

1. **Foundational** — 6 принципов (minimal scaffolding, fewer subagents, adaptive thinking + xhigh, 1M context constraint, verification highest-leverage, CLI subscription boundary). Каждый — с direct quote из Anthropic source + URL.

2. **Components inventory** — current state harness'а (skills/agents/hooks/rules/reference docs).

3. **Subagents** — built-ins first, spawn justified (a/b/c), multi-agent ill-suited (Anthropic explicit), opt-in subagent isolation для high-stakes с cost-threshold цитатой Rajasekaran, model assignment matrix.

4. **Skills** — action-only, frontmatter required, SKILL.md ≤500 строк, skill-creator через marketplace.

5. **Hooks** — block-at-decision (не block-at-write), event types в harness'е, handler types.

6. **Memory** — CLAUDE.md hierarchy + ≤200 lines, @file import syntax, auto-memory layout, curate-and-delete, state on disk.

7. **Settings & permissions** — 3-layer model, defaultMode options, security boundary этого harness'а.

8. **Testing & verification** — 2026 reframe (verification universal, TDD opt-in), 5 invariants reference, root causes.

9. **Documentation** — CLAUDE.md as indexer, project docs layout, live vs archive, 6 invariants reference.

10. **Process** — Plan→Work→Review reference на workflow.md, `/review` vs `ultrareview`, auto-mode caveat, single-incident not invariant, Tier 0/1/2 validation.

11. **Anti-patterns** — 9 items: multi-agent for most coding, mandatory pipelines, built-in duplication, self-describing skills, CLAUDE.md >200 lines, trust-then-verify gap, block-at-write hooks, fixed thinking budgets, vague instructions.

12. **Sources** — 13 canonical Anthropic URLs с retrieval date.

**Удалены полностью**:
- Decision log section (D-021 / D-022)
- Все ADR-NNN references (ADR-002, ADR-007, ADR-011, ADR-014, ADR-017, ADR-019)
- Cross-refs на archive layer как primary reference
- Cross-refs на retired ADRs в anti-patterns formulation

**Сохранены концептуально** (но без ADR labels):
- Subagent isolation opt-in для high-stakes (D-022 content → Subagents section)
- Two-tier docs live vs archive (D-021 content → Documentation section)

### `.claude/CLAUDE.md` (1 line)

Reference materials description: «active decisions (live, editable)» → «harness principles (Anthropic-canonical evidence-based)».

### `.claude/skills/devlog/SKILL.md` (2 lines)

Stale refs к Decision log section:
- Tags table `adr` row: убран «(см. также principles.md Decision log)» → «(контекст / motivation / consequences / alternatives)»
- Связь с другими артефактами: убран «archive/decisions-2026Q2.md (frozen ADR-002…020). D-NNN refs.» → «principles.md ссылается на принципы по name».

## Принципиальный сдвиг

- **Old**: principles.md = decision-log style document с ADR-NNN cross-refs к archive. Self-referential historical chain.
- **New**: principles.md = current-state principles document с direct Anthropic citations. Self-contained, evidence-based, не требует archive context.

Archive layer (`.claude/docs/archive/decisions-2026Q2.md`) остаётся frozen historical snapshot, но больше не primary reference для active principles. Future contributors / Claude sessions могут понять harness principles полностью из principles.md + Anthropic source URLs без consulting archive.

## Затронутые файлы

- `.claude/docs/principles.md` — полная перезапись (97 → 123 строки)
- `.claude/CLAUDE.md` — 1 line update (Reference materials description)
- `.claude/skills/devlog/SKILL.md` — 2 lines (stale Decision log refs убраны)
- `.claude/devlog/entries/0020-...` — эта запись

## Проверка

```bash
$ wc -l .claude/docs/principles.md
123 .claude/docs/principles.md

$ grep -c "ADR-\|D-021\|D-022\|Decision log" .claude/docs/principles.md
0

$ python3 .claude/devlog/rebuild-index.py
index.json updated: 20 entries

$ bash .claude/benchmark/static-checks.sh
=== ALL AUTOMATED CHECKS PASSED (12/12) ===
```

Static-checks Check 3 inner loop (D-### tight format) корректно skip'ает — dynamic enumeration возвращает empty list (нет D-NNN headers в principles.md больше). Это expected behavior после shift с decision-log на flat principles structure.

## Related

- #19 — D-022 subagent isolation opt-in (content инкорпорирован в Subagents section без ADR labels)
- #18 — workflow.md Plan→Work→Review canonical spine (referenced from Process section)
- memory `feedback_grow_with_community.md` — applied: research-first против Anthropic canonical docs ДО опоры на внутренние артефакты

## Stale refs остающиеся в harness'е (для следующей итерации, не в scope текущего запроса)

Эти места всё ещё содержат archive refs (pre-existing, not introduced by current rewrite):

- `.claude/rules/testing.md:11` — «См. также archive/decisions-2026Q2.md ADR-003»
- `.claude/rules/docs-discipline.md:19` — «См. также principles.md + archive/decisions-2026Q2.md ADR-017»
- `.claude/docs/multi-agent.md:222` — ADR-002 / ADR-007 / ADR-011 refs
- `.claude/docs/benchmark.md` (footer) — ADR-019 ref
- `.claude/skills/project-docs-bootstrap/SKILL.md:118` + `references/CONTRACT.md:312` — ADR-017 refs
- `.claude/CLAUDE.md` Reference materials — explicit pointer на archive (conditional, не proactive)

Эти ссылки valid (archive exists, refs точны), но создают archive-dependency которая может быть removed в next pass если пользователь захочет broader cleanup.
