---
id: 108
date: 2026-06-17
title: "Снят устаревший Plan-Mode caveat из kit v1.9.1"
tags: [bugfix, harness]
status: complete
---

# Снят устаревший Plan-Mode caveat из kit v1.9.1

## Контекст
Kit-baseline `references/project-docs/workflow.md` нёс `*Caveat:*` (стр. 24-25):
«`ExitPlanMode` disables Auto Mode (anthropics/claude-code#49947), so if Auto Mode
is on, prefer a written plan file over entering plan mode». Этот совет уводил проекты
от нативного Plan Mode и был seed'ом редундантного skill'а `task-planning` в
`dialog_analyzer`. Эмпирическая проверка показала: баг #49947 (дубль #49653, оба
CLOSED, эра CC 2.1.112–2.1.138, Windows/macOS) на текущей версии **НЕ воспроизводится** —
Anthropic перепроектировал plan-approval flow.

## Изменения
**Эмпирика (CC 2.1.179 / Linux / Opus 4.8, живой pty-драйв TUI 2026-06-17):**
- интерактивный default-старт: `⏵⏵ auto mode on` включён по умолчанию;
- Shift+Tab цикл: auto / accept-edits / plan — все доступны;
- диалог ExitPlanMode нативно предлагает `1. Yes, clear context and use auto mode` /
  `2. Yes, and use auto mode` / `3. manually approve` / `4. tell Claude`;
- принял опцию 1 (clear-context + auto — *именно* вариант, репортнутый как триггер бага):
  auto остался **active**, агент авто-исполнил правку без permission-prompt, auto остался
  в цикле после. Headless `--permission-mode auto -p` тоже работает.
- кешированный `tengu_auto_mode_config.enabled = disabled` в `~/.claude.json` (флаг, на
  который грешил #49653) — эмпирически нерелевантен: auto on by default.

**Фикс kit'а:** устаревший caveat убран, заменён на корректную ноту «On accepting a plan,
the ExitPlanMode dialog offers to continue in Auto Mode — Auto Mode survives the plan cycle,
so plan mode and Auto Mode compose (no need for a written-plan-file workaround)». Ноту оставил
(не голое удаление) как guardrail против реинтродукции: misconception уже стоил одному проекту
редундантного skill'а — recurring real cost, проходит §2-планку.

**Версия:** bump `claude-code-harness` v1.9.0 → v1.9.1 (patch — content correction). Все три
`shipped-by:` заголовка (`workflow`/`testing`/`docs-discipline`) обновлены до v1.9.1 — единая
версия по трио требуется инвариантом re-sync (Audit сравнивает версию копии проекта против
плагина; bootstrap-checklist стр. 177-179). Файлы в `~/.claude` (плагин), **не закоммичены** —
push за оператором.

## Затронутые файлы
- `~/.claude/skills/claude-code-harness/references/project-docs/workflow.md` — caveat → корректная нота + shipped-by v1.9.1
- `~/.claude/skills/claude-code-harness/references/project-docs/testing.md` — shipped-by v1.9.1
- `~/.claude/skills/claude-code-harness/references/project-docs/docs-discipline.md` — shipped-by v1.9.1
- `~/.claude/skills/claude-code-harness/.claude-plugin/plugin.json` — version 1.9.0 → 1.9.1

## Проверка
- `grep -rn "49947|disables Auto Mode|written plan file over" references/ SKILL.md` → 0 hits (clean)
- единая версия: plugin.json `1.9.1` + три shipped-by `v1.9.1`
- pty TUI-репро (см. Изменения) — конфликт не воспроизводится; артефакт `foo.txt` создан auto-mode без prompt

## Related
- `dialog_analyzer` чистится параллельным агентом: retire skill `task-planning` + sync
  `.claude/rules/execution.md` (стр. 9-11) и root `CLAUDE.md` (стр. ~44) под нативный Plan Mode.
- Memory лаборатории: `reference_planmode_automode_conflict_resolved.md`.
