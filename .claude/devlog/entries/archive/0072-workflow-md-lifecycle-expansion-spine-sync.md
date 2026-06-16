---
id: 72
date: 2026-06-09
title: "WORKFLOW.md lifecycle expansion + spine sync"
tags: [docs, workflow, lifecycle, sync]
status: complete
---

# WORKFLOW.md расширен до полного lifecycle + синхронизация с machine spine

## Контекст
После актуализации #71 оператор попросил сводный плейбук «разработки проекта с Claude Code с
самого начала»: как обсуждать проект, фиксировать требования, решать проектные задачи, переходить
к разработке, PRD, тестирование, общий пайплайн. Затем — «расширить WORKFLOW.md» и «синхронизировать»
machine routing-spine. Акцент оператора: **актуальность**.

## Дизайн
`WORKFLOW.md` (root, human-facing) был execution-центричным (Plan→Work→Review). Не хватало фронта
жизненного цикла. `.claude/docs/workflow.md` (machine spine) — тонкое routing-дерево; синхронизация
= **cross-ref, не дубль** (spine остаётся тонким, lifecycle-фронт референсится).

## Сделано
**WORKFLOW.md (root) — расширен фронтом lifecycle:**
- **§1 Старт проекта** — первая сессия как конфигурация + контракт (не upfront-анкета): `/init`,
  greenfield vs existing, 5 пунктов контракта, guardrails сразу и реактивно (deny-правила переживают
  потерю контекста).
- **§2 Требования и PRD** — «думай вслух, не предполагай», контекст-слой = версионируемый артефакт,
  шаблон PRD-lite (Проблема/Пользователь/Success/Out-of-scope/Открытое), acceptance criteria =
  наблюдаемое поведение = оракул, GLOSSARY first-use.
- **§3 Дизайн и решения до кода** — Plan-агент/`/ultraplan`, ADR-порог >5 мин, docs-bootstrap
  (read-before-write), built-ins-first против PM→Architect→Dev→QA.
- **Пайплайн одним взглядом** — ASCII-схема КОНТРАКТ→ТРЕБОВАНИЯ→ДИЗАЙН→WORK→REVIEW→СЛЕД + правило
  выбора режима (single thread / `ultracode` / fresh-context критик).
- **Тестирование** — компактный блок 5 тест-инвариантов в WORK.
- «Спина» → «ядро execution»; подсекции PLAN/WORK/REVIEW без номеров (чтобы не клэшить с §1-3).
- Источники +[8] Sandboxing/Settings (guardrails), +[9] Onboarding/MacLean (контекст-слой). 143 строки.

**`.claude/docs/workflow.md` (machine spine) — синхронизирован:**
- Intro: Plan→Work→Review = execution-ядро; полный human-facing lifecycle → `../../WORKFLOW.md`.
- ASCII-spine: добавлен upstream `[контракт · PRD-lite · ADR]` + Cold-start строка (`/init` +
  `project-docs-bootstrap` + контракт) с детализацией в WORKFLOW.md §1-3.
- Routing-таблица: новая строка «Старт нового проекта / scaffolding docs» → `/init` +
  `project-docs-bootstrap`. «When not covered»: строка на полный lifecycle → WORKFLOW.md.

## Результат
Двунаправленные cross-ссылки workflow.md ↔ WORKFLOW.md, путь `../../WORKFLOW.md` резолвится. Все
9 сносок WORKFLOW.md резолвятся. Spine остался тонким (routing, не дубль PRD/контракта). Никаких
новых инвариантов — only doc-structure. WORKFLOW.md остаётся untracked (как был).
