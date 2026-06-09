---
id: 80
date: 2026-06-10
title: "Docs freshness audit: link fixes, 2.1.170 delta, archive moves"
tags: [docs, harness]
status: complete
---

# Docs freshness audit: link fixes, 2.1.170 delta, archive moves

## Контекст
Аудит актуальности `.claude/docs/` после вчерашнего re-ground на CC 2.1.169: CLI уже 2.1.170, один док пропустил актуализацию, два point-in-time дока лежали в живом слое. Сверены даты, версии, перекрёстные ссылки и упоминания ретайрнутых компонентов во всех 13 доках.

Итог аудита: документация в основном актуальна (12/13 доков re-grounded 2026-06-09). Дельта 2.1.169→2.1.170 по changelog несущественна для harness'а — релиз Fable 5 (A/B уже отработан, devlog-контекст: ничья, no blanket-switch) и фикс транскриптов VS Code. Ссылок на ретайрнутые артефакты (`harness-setup`, `sync-docs`, `project-docs-bootstrap`) без пометки «retired» не найдено.

## Изменения
- `memory-layers.md` — починена относительная ссылка на discovery-critic (`.claude/agents/...` → `../agents/...`; из `docs/` старый путь не резолвился).
- `harness-architecture.md` — frontmatter `last-updated` обновлён (отставал с 2026-05-14 при правке 2026-06-01 — нарушение docs-discipline rule #4); ссылка на component-audit перенаправлена в `archive/`. Док добавлен в Reference materials в `.claude/CLAUDE.md` (раньше единственный из активных не индексировался).
- `builtins-inventory.md` — Delta-секция расширена до 2.1.170 (Fable 5 + транскрипт-фикс; harness-relevant изменений нет, workflow-доки на 2.1.169 остаются валидными); frontmatter и заголовок подняты до 2.1.170. Консолидация ядра таблиц (2.1.143-snapshot) остаётся pending — сознательно не делалась.
- Архивация per docs-discipline rule #3 (live vs archive): `retrospective-2026-05-12-builtins-and-memory.md` и `audit/2026-05-14-component-audit.md` перенесены в `docs/archive/`; пустой каталог `docs/audit/` удалён.
- Заголовки workflow-* доков сознательно оставлены на 2.1.169 — bump без материальной дельты был бы косметическим churn'ом; факт валидности под 2.1.170 зафиксирован в Delta-секции inventory.

## Затронутые файлы
- `.claude/docs/memory-layers.md` — фикс ссылки + date bump
- `.claude/docs/harness-architecture.md` — frontmatter + archive-ссылка
- `.claude/docs/builtins-inventory.md` — delta 2.1.170, version-targeted bump
- `.claude/CLAUDE.md` — строка harness-architecture.md в Reference materials
- `.claude/docs/archive/{retrospective-2026-05-12-builtins-and-memory,2026-05-14-component-audit}.md` — git mv из live-слоя

## Проверка
- Скрипт-обход всех relative `.md`-ссылок в `docs/` и `docs/archive/` — 0 битых после правок и переносов.
- `grep` по живому дереву на старые пути (`docs/retrospective-2026-05-12`, `docs/audit/`) — 0 вхождений.
- Дельта 2.1.169→2.1.170 сверена с CHANGELOG.md anthropics/claude-code (via `gh api`).

## Related
- #74 — retire project-docs-bootstrap (тот же re-ground проход 2026-06-09, чью полноту проверял этот аудит)
