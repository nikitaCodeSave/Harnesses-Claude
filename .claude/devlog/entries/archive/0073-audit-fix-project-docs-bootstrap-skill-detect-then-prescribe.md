---
id: 73
date: 2026-06-09
title: "Audit fix project-docs-bootstrap skill detect-then-prescribe regression"
tags: [docs, harness, bugfix]
status: complete
---

# Audit fix project-docs-bootstrap skill detect-then-prescribe regression

## Контекст
Скрупулёзный multi-agent аудит скилла `project-docs-bootstrap` (4 независимых аудитора по осям refs / actuality / harness-rules / coherence + fresh-context refuter на каждый finding) выявил регрессию уже однажды исправленного бага: скилл безусловно вписывал в артефакты target-проекта ссылки на harness-internal файлы без проверки их наличия — ровно инцидент 2026-05-18 из памяти `feedback_detect_then_prescribe_universal`. Из 24 сырых findings валидаторы подтвердили 19, частично 4, опровергли 1 (отсев severity-инфляции и ложных выводов).

После дедупликации — 7 уникальных подтверждённых дефектов + 3 частичных.

## Изменения

**Критичные:**
- **detect-then-prescribe регрессия (HIGH)** — Phase 4 вписывала `.claude/rules/docs-discipline.md` в CLAUDE.md target-проекта, PR-template (§4) хардкодил `.claude/rules/testing.md`, без detect-шага; язык «always-loaded invariant». Фикс: добавлен Phase 1 step 7 (`ls .claude/rules/*.md`), обе вставки сделаны conditional, «always-loaded» убран во всех точках (SKILL.md:11/116, CONTRACT §7).
- **проактивный `git init` (HIGH)** — Phase 1 шаг 4 нарушал `feedback_harness_no_git_lifecycle`. Убрано проактивное предложение; git упоминается только как опция в Done report.

**Doc-рассинхроны:**
- ADR-017 неверная локация в CONTRACT §7: `principles.md` → `archive/decisions-2026Q2.md` (выровнено с SKILL.md:118).
- Счётчик правил docs-discipline: «6 invariants» → 7 правил (добавлено rule #7 Progress journal).
- SKILL.md «Связь с артефактами» искажал содержимое docs-discipline (несуществующие «append-only history»/«cold-start test») — приведено к фактическим 7 правилам.
- ADR-skeleton frontmatter (`id/date/deciders` без `owner/last-updated`) — задокументирован как намеренный carve-out из rule #4 (append-only: `date`≈last-updated, `deciders`=owner-of-record).
- Висящий императив «мониторить #16853» → датированный provenance без action-verb.

**Частичные (косметика):** `agnix-style` атрибуция в CODE-MAP drift-detection (agnix линтит harness-config, не code-map) → нейтральное «grep/CI на orphan paths»; AGENTS.md framing (Cursor/Copilot symlink → cross-vendor стандарт + @import); GLOSSARY TBD-плейсхолдер → иллюстративный пример с пометкой.

## Затронутые файлы
- `.claude/skills/project-docs-bootstrap/SKILL.md` — detect-step (Phase 1), conditional reference (Phase 4), убран git init и always-loaded, исправлен список правил
- `.claude/skills/project-docs-bootstrap/references/CONTRACT.md` — ADR-017 локация, счётчик 6→7, #16853 reframe, agnix/AGENTS.md/GLOSSARY/PR-template conditional, ADR frontmatter carve-out

## Проверка
- Independent fresh-context refuter (general-purpose subagent, установка «опровергать»): 9/10 RESOLVED, поймал уцелевший «always-loaded» в CONTRACT §7 → дофикшен. Новых/оставшихся дефектов после дофикса не найдено.
- `grep` остатков старых формулировок (always-loaded invariant / 6 invariants / git init / agnix / мониторить / principles.md ADR-017) — пусто.

## Related
- #71 — `feedback_detect_then_prescribe_universal` / `feedback_harness_self_contained` (источник класса дефекта)
- ADR-017 (decisions-2026Q2.md) — обоснование самого скилла
