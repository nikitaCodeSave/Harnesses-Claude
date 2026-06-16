---
id: 105
date: 2026-06-16
title: "Гигиена harness: frontmatter, CLAUDE.md-сверка, devlog-архив"
tags: [cleanup, docs, harness]
status: complete
---

# Гигиена harness: frontmatter, CLAUDE.md-сверка, devlog-архив

## Контекст
Архитектурный аудит лаборатории (после чистки #104) показал: реструктуризация
в модули НЕ требуется — проект уже декомпозирован по ответственности, `.claude/CLAUDE.md`
в бюджете (≤200 строк), 0 dangling-ссылок, 0 противоречий слоёв. Независимый
fresh-context skeptic (прайм «опровергни») подтвердил — нашёл только мелкую гигиену.
Эта запись закрывает те 4 пункта; крупный рефактор сознательно не делался
(нарушил бы foundational-принцип «минимум обвязки»).

## Изменения
- **Frontmatter (rule #4)**: `docs/benchmark.md` и `docs/multi-agent.md` не имели
  `owner`/`last-updated` — добавлены. `last-updated` выставлен честно по дате
  последнего content-изменения (git log): benchmark → 2026-06-09, multi-agent →
  2026-06-11 (не «сегодня» — менялся только frontmatter, не содержание).
- **CLAUDE.md сверка**: строка про `builtins-inventory.md` маркировала его как
  «2.1.143-era, pending re-ground», но файл `last-updated: 2026-06-10` со свёрнутыми
  дельтами до 2.1.170 → метка приведена в соответствие («core-таблицы =
  2.1.143-snapshot, дельты до 2.1.170, pending consolidation»). `.claude/agents/`
  описан как «пусто», хотя каталог отсутствует вовсе → формулировка исправлена.
  Добавлен индекс `.claude/audits/` в Reference materials (был не проиндексирован).
- **devlog live/archive (rule #3, структурная миграция)**: 74 записи (#0011–0084)
  перенесены `git mv` в `entries/archive/` (history сохранён как renames). Live
  сжат с 94 до 20 (#0085–0104), archive вырос с 10 до 84. **Индекс не пострадал**:
  `rebuild-index.py` использует `rglob` → все 104 записи остаются в
  `index.json`/`tldr.md`. Граница — id-cut (084/085 оба 06-10, дата не разделяет).

## Затронутые файлы
- `.claude/docs/benchmark.md`, `.claude/docs/multi-agent.md` — добавлен frontmatter
- `.claude/CLAUDE.md` — сверка builtins-label + agents-формулировка + индекс audits/
- `.claude/devlog/entries/0011..0084-*.md` → `entries/archive/` (74 renames)
- `.claude/devlog/{index.json,tldr.md}` — регенерированы

## Проверка
- Checksum индекса до/после: `entry_count=104`, id-set 1..104, sum=5460 — **идентичен**.
- Все flow-consumers проверены на симуляции после переноса:
  global SessionStart hook (`ls entries/[0-9]*.md|tail -3`) → 0102/0103/0104;
  devlog-skill next-id (top-level `tail -1`) → 0105; 84 archived записей
  проиндексированы с `archive/`-путём.
- `wc -l .claude/CLAUDE.md` = 148 (в бюджете ≤200). Все доки в `docs/` имеют frontmatter.

## Related
- #104 — предыдущий шаг того же аудита (worktree GC + ретайр progress-журналов)
- #54 — дизайн continuity-слоёв (devlog/progress/auto-memory), SessionStart hook
