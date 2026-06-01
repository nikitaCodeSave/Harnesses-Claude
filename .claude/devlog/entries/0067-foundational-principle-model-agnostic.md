---
id: 67
date: 2026-06-01
title: "Foundational principle model-agnostic"
tags: [harness, principle, coherence, docs]
status: complete
---

# Foundational principle model-agnostic

## Контекст
Продолжение #66 / [[feedback_model_agnostic_skills]]: harness-практики не привязывать к
версии модели. Sweep по live-guidance выявил **stale + version-bound foundational principle**:
в одних live-доках он был «под Opus 4.7» (устарел), в других «под Opus 4.8» — рассогласование,
и сама форма «под версией X» обречена устаревать каждый релиз.

## Триаж (что правил / что намеренно НЕ трогал)
**De-versioned (foundational principle → «под способной моделью», с сохранением grounding-провенанса):**
- `.claude/CLAUDE.md` (центральный foundational principle + «модель не делает X нативно»)
- `.claude/docs/principles.md` (минимум обвязки + single-agent first)
- `.claude/docs/harness-architecture.md` (evergreen frame-doc; был stale «4.7»)

**Намеренно сохранено (по самому принципу — это НЕ поведенческая привязка):**
- **Провенанс/dated findings**: principles.md «4.7-era — re-measure due под 4.8», cost-envelope
  (devlog #24), discovery-critic.md / multi-agent.md «4.7-era eval, не перемерено», builtins
  «2.1.143-era snapshot» — честный источник «когда/против чего проверено».
- **Конфиг-факты**: effort default `high` на 4.8 (был `xhigh` на 4.7), model-assignment
  (lead Opus / sub Sonnet / grunt Haiku) — реальное поведение тулинга/конкретные model-id.
- **Историческое/frozen**: «переход 4.7→4.8» (что пережило апгрейд), dated-retrospective,
  `plans/*` (синтез «на дату»), devlog/archive — не переписываются.
- **Citations**: ссылка «Best practices for Opus 4.7» — заголовок реального источника.
- **Дословная реплика пользователя** в memory `feedback_no_upfront_contract_interview` Why
  («…на Opus 4.7») — исторический факт, что было сказано.

## Также
- memory `feedback_no_upfront_contract_interview`: de-versioned `name:` + body-принцип
  (вербатим-цитата сохранена); MEMORY.md индекс обновлён.

## Затронутые файлы
- `.claude/CLAUDE.md`, `.claude/docs/principles.md`, `.claude/docs/harness-architecture.md`
- memory: `feedback_no_upfront_contract_interview.md`, `MEMORY.md` (вне git)

## Related
- #66 ([[feedback_model_agnostic_skills]]) — принцип, который это применяет.
- Граница «behavioral binding → de-version; provenance/config/historical → keep» — operational rule.
