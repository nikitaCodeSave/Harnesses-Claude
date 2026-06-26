---
id: 112
date: 2026-06-24
title: "Анализ статьи Steering Claude Code + синк кита native-capabilities"
tags: [docs, harness]
status: complete
---

# Анализ статьи Steering Claude Code + синк кита native-capabilities

## Контекст
Research-pass по first-party статье `claude.com/blog/steering-claude-code-skills-hooks-rules-subagents-and-more`
для актуализации harness-знания. ~80% статьи — независимая валидация уже зашитого
дизайна (CLAUDE.md ≤200 indexer-not-store, path-scoped rules, skills-for-procedures,
subagents-for-isolation, hooks/managed-settings-for-absolutes) → закрывает
grow-with-community проверку. Реальная новизна — 3 дельты, которых не было в живом
ките. Перед записью в канон каждая дельта проверена против **бинаря 2.1.187** (строки
присутствуют) и официальных доков (`/en/output-styles`, `/en/memory`), а не только блога —
по требованию против «тихих ошибок».

## Изменения
**3 verified дельты, добавлены в глобальный кит:**

1. **Output styles + `keep-coding-instructions` trap.** Кастомный output-style модифицирует
   system prompt и **выкидывает built-in SWE-инструкции (scoping/comments/verify/security),
   если не выставлен `keep-coding-instructions: true`** — флаг **по умолчанию `false`**. Тихо
   стрипает дисциплины §5/§8. Секции про output-styles в живом ките не было вовсе.
2. **Context-loading & compaction model.** CLAUDE.md = user-message *после* system prompt
   (отсюда меньший вес, чем у output-style/append-system-prompt). После `/compact` **root
   CLAUDE.md перечитывается и re-injected; nested subdir CLAUDE.md — НЕТ** до следующего
   чтения файла в подкаталоге → subdir-scoped конвенция может тихо исчезнуть в длинной
   сессии. `@imports` грузятся at launch (split ≠ экономия токенов). MEMORY.md — только
   первые 200 строк / 25 KB.
3. **`claudeMdExcludes`** (settings, любой слой, abs-path globs, arrays merge) — пропуск
   ancestor-CLAUDE.md в монорепо; managed-policy CLAUDE.md исключить нельзя.

**Skipped per adopt-on-proof (§2):** managed-policy MDM-деплой + per-team subdir CLAUDE.md
(монорепо-паттерны, нет recurring need для solo-лаборатории).

**State-check проекта (чисто):** MEMORY.md 51 строк / 14.7 KB (под cap'ом), output-styles
в репо нет (нет риска тихого drop'а SWE-инструкций), 4 rule'а все always-on by design.

## Затронутые файлы
- `~/.claude/skills/claude-code-harness/references/native-capabilities.md` — новая секция
  «Output styles [FP]» + блок «What loads when — silent-error surface» в секции Memory
- `~/.claude/projects/.../memory/reference_steering_blog_2026.md` — новая reference-memory
- `~/.claude/projects/.../memory/MEMORY.md` — индекс-строка

## Проверка
- `grep -a -c` по бинарю 2.1.187: `keep-coding-instructions` (7), `claudeMdExcludes` (3),
  `output-style` (25), `PreCompact` (34), `mcp_tool` (78) — все строки присутствуют.
- WebFetch `code.claude.com/docs/en/output-styles` + `/en/memory` — семантика подтверждена
  дословно (флаг default `false`; root re-injected после compact, nested — нет).

## Related
- #70, #71 — first-party harness-design / dynamic-workflows источники (тот же T1-канон)
