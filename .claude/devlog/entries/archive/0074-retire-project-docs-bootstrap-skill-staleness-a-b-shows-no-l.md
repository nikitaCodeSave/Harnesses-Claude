---
id: 74
date: 2026-06-09
title: "Retire project-docs-bootstrap skill — staleness A/B shows no lift"
tags: [adr, harness, cleanup]
status: complete
---

# Retire project-docs-bootstrap skill — staleness A/B shows no lift

## Контекст
После аудита и фикса скилла `project-docs-bootstrap` (#73) встал вопрос: чинить дальше / переписать / ретайрнуть. Применён ритуал staleness (WORKFLOW.md §125) на эмпирике (не теорией — `feedback_empirical_over_theoretical_dismiss`): **даёт ли скилл воспроизводимый материальный лифт над native Opus 4.8 + WORKFLOW.md §3 + docs-discipline?** Ответ по evidence — нет → retire (foundational principle: компонент кодирует «модель не умеет X», а модель умеет нативно). Тот же паттерн, что ретайр `sync-docs` (#64) и `harness-setup`.

## Изменения
**A/B (n=2, target `full-stack-fastapi-template`, изолированные клоны `claude --print`, минимальный representative harness, единственное различие — наличие скилла):**

| Прогон | Конфиг | Skill вызван | docs | frontmatter | boilerplate | npm-галлюц. |
|---|---|---|---|---|---|---|
| A (r1) | skill ON | да (1×) | 4 | 4/4 | 0 | clean |
| B (r1) | native | — | 5 (+ADR) | 5/5 | 0 | present |
| A2 (r2) | skill доступен | **нет (0×)** | 4 | 4/4 | 0 | present |
| B2 (r2) | native | — | 4 | 4/4 | 0 | clean |
| A3 (r2) | skill ФОРСИРОВАН | да (2×) | 4 | 4/4 | 0 | present |

Три независимых слепых судьи (scrambled, reverse-scrambled r2): r1 → `equivalent` / `skill чуть лучше`; r2 → `native materially better` (зеркало). Все различия — одна variance-галлюцинация (npm-vs-bun), которая перепрыгивает arm'ы и **сохраняется даже при форсированном скилле (A3)** → ортогональна скиллу. Полная дисциплина (canonical layout, owner+last-updated, 0 boilerplate) во всех 5 прогонах независимо от скилла. Скилл не триггерится надёжно (A2). Вывод: skeletons/charter/фазы не load-bearing.

**Retire-каскад:** удалён `.claude/skills/project-docs-bootstrap/`; обновлены live capability-описания (CLAUDE.md self-evolution + reference materials; docs-discipline.md header + re-bootstrap escalation; principles.md ×3; memory-layers.md; workflow.md ×2; external-sources.md; tier2/README.md). Ценность сохранена в `WORKFLOW.md` §3 + `.claude/rules/docs-discipline.md`. git history сохраняет скилл; devlog/benchmark-reports/component-audit (иммутабельные/point-in-time) не тронуты.

## Затронутые файлы
- `.claude/skills/project-docs-bootstrap/` — удалён (git rm)
- `.claude/CLAUDE.md`, `.claude/rules/docs-discipline.md`, `.claude/docs/{principles,memory-layers,workflow,external-sources}.md`, `.claude/benchmark/tier2/README.md` — сняты live-ссылки / reframe на native
- `.claude/benchmark/reports/2026-06-09-docs-bootstrap-staleness-ab/` — A/B summary + raw docs-выводы всех 5 прогонов (аудируемость)

## Проверка
- n=2 A/B, 3 слепых fresh-context судьи (§8), объективные факты (frontmatter/boilerplate/npm) скоррелированы с судейскими.
- `grep project-docs-bootstrap` по live-доках: остаются только намеренные retire-ноты (CLAUDE.md, principles.md) + иммутабельная история.

## Related
- #73 — аудит+фикс этого скилла (фиксы не пропали зря — корректность; staleness — отдельный вопрос)
- #64 — sync-docs ретайр в docs-discipline (тот же retire-bias паттерн)
- #72 — WORKFLOW.md (носитель §3 bootstrap-рычага, поглотившего ценность скилла)
- ADR-017 (decisions-2026Q2.md) — вводил skill+rule; rule выживает, skill ретайрнут
