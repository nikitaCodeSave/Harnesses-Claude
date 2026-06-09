---
id: 75
date: 2026-06-09
title: "Prune global skills delete project-docs-bootstrap and archived-skills"
tags: [harness, cleanup]
status: complete
---

# Prune global skills delete project-docs-bootstrap and archived-skills

## Контекст
После retire `project-docs-bootstrap` в лабе (#74) — чистка **глобального** `~/.claude/skills/`. Глобальный слой срабатывает во всех проектах, поэтому редундантный/баговый скилл там вреднее, чем в лабе. `~/.claude` НЕ под git → удаления необратимы; перед каждым — явное подтверждение пользователя.

## Изменения
**Инвентарь `~/.claude/skills/` → вердикт:**
- `claude-code-harness` — KEEP (каноничное знание о дизайне harness'а).
- `devlog` — KEEP (дом `rebuild-index.py`, load-bearing).
- `grill` — KEEP (user-invocable `/grill`, форс-допрос one-at-a-time — реальный behavioral delta).
- `tdd` — KEEP (импортированная методология, user-invocable).
- **`project-docs-bootstrap` — hard-deleted.** Авто-триггерился во всех проектах; версия от 18 мая несла проактивный `git init` + отсутствие detect-step (висячие ссылки в target); ретайрнут по evidence (#74).

**`~/.claude/_archived-skills/` — hard-deleted целиком** (3 инертных артефакта): `harness-setup` (Python-only overloaded preset), `sync-docs` (ядро → docs-discipline rule), `project-claude-code-harness-superseded` (мёртвая старая версия каноничного скилла). Знание поглощено `claude-code-harness` + `docs-discipline.md`. Live-зависимостей не было.

**Досье harness-setup (как просили отдельно):** Python-only two-mode (greenfield prescriptive 2026-стек uv/pytest/ruff/mypy/src-layout vs existing descriptive), создавал CLAUDE.md-indexer ≤200 + settings.json deny/ask/allow + Stop-hook; ~2185 строк + скрипты + build-детрит (.ruff_cache/__pycache__/_backups/_test_logs). Ретайрнут как «обвязка переросла модель»; знание → `claude-code-harness` Bootstrap-режим.

**Dangling-ссылки на `_archived-skills/` исправлены** в lab live-доках: `.claude/CLAUDE.md` (harness-setup retire-нота → hard-deleted), `.claude/rules/docs-discipline.md` (sync-docs retire-нота). Память `project_harness_starter_consolidated` обновлена (deletions + текущий roster).

## Затронутые файлы
- `~/.claude/skills/project-docs-bootstrap/` — hard-deleted (вне git)
- `~/.claude/_archived-skills/` — hard-deleted целиком (вне git)
- `.claude/CLAUDE.md`, `.claude/rules/docs-discipline.md` — сняты dangling-пути на _archived-skills
- `~/.claude/.../memory/project_harness_starter_consolidated.md` — актуализирован roster + deletions

## Проверка
- Финальный `ls ~/.claude/skills/` = {claude-code-harness, devlog, grill, tdd}; `_archived-skills/` отсутствует.
- `grep _archived-skills` по lab live-доках — остаются только в иммутабельных devlog/progress (история).
- `grep project-docs-bootstrap` в каноничном `claude-code-harness` — пусто (нет dangling).

## Related
- #74 — retire project-docs-bootstrap в лабе (evidence-источник)
- #64 — sync-docs ретайр
- #50/#51 — консолидация harness-стартера под claude-code-harness (harness-setup retire)
