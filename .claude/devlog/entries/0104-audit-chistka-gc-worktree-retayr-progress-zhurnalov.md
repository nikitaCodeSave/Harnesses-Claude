---
id: 104
date: 2026-06-16
title: "Аудит-чистка: GC worktree + ретайр progress-журналов"
tags: [cleanup, harness]
status: complete
---

# Аудит-чистка: GC worktree + ретайр progress-журналов

## Контекст
Аудит актуального состояния лаборатории выявил накопленный процессный мусор:
13 осиротевших agent-worktree от battle-test прогонов, три отработанных
progress-журнала (нарушение rule #7 docs-discipline — завершённые задачи не
закрыты) и research-артефакт в корне. Сам код/devlog консистентны (`main` ≡
`origin/main`, index до #103) — чистились только хвосты прошлых задач, ничего
«в полёте» не оборвано.

## Изменения
- **Worktree GC**: удалены все 13 `.claude/worktrees/agent-*` (+ одноимённые
  orphan-ветки). 7 висели под stale-локами от мёртвых PID (309758/405898/37270 —
  проверены `ps`, мертвы) → сняты через `worktree remove -f -f`. Также удалена
  ff-merged ветка `harness/docs-bootstrap-retire-prune`. Осталась одна ветка `main`.
- **Ретайр progress-журналов** (rule #7 — конверсия завершённой задачи):
  `dogfood-sgr-kit.md` (`status: completed`, арка покрыта devlog #78–82, kit
  упакован в plugin v1.0.0) и `harness-practice-layer.md` (трек закрыт, арка
  покрыта #50–63) — оба явно ссылались на уже существующие devlog-записи, поэтому
  отдельные дублирующие записи не создавались (rule #2). `operator-review.md`
  закрыт: его хвосты либо протухли (упоминал kit v1.4.0 при текущем v1.9.0), либо
  относятся к репо `AI_analyst_migration`, не к этой лаборатории.
- **Корневой мусор**: `files.zip` (дубликат уже распакованного research-набора)
  перемещён в `.scratch/research-pamyat/`; `.scratch/` добавлен в `.gitignore`
  (R&D-машинерия постоянно светилась как `??` в `git status`).

## Затронутые файлы
- `.gitignore` — добавлено правило `.scratch/`
- `.claude/progress/{dogfood-sgr-kit,harness-practice-layer,operator-review}.md` — удалены
- `.claude/worktrees/` — очищен (git-метаданные worktree снесены)
- `files.zip` → `.scratch/research-pamyat/files.zip` (untracked move)

## Проверка
- `git worktree list` → только `main`; `git branch` → только `main`.
- `git status` после правок → чисто, `.scratch/` больше не отображается.
- PID-локи проверены `ps -p` перед force-remove (все мертвы — данных живых агентов не потеряно).

## Related
- #103 — предыдущая запись (откат #102, global как единый источник §1–8)
- #82 — упаковка kit в plugin v1.0.0 (арка dogfood-журнала)
- #63 — multi-session A/B (закрытие practice-layer трека)
