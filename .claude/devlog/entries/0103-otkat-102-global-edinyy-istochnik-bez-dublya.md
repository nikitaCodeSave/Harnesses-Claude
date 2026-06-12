---
id: 103
date: 2026-06-13
title: "Откат #102: global — единый источник §1–8 (без дублирования)"
tags: [canon, kit, harness-evolution, practice-baseline, supersedes]
status: complete
---

# Откат #102: global — единый источник §1–8 (без дублирования)

**Supersedes #102.** Решение оператора: §1–8 best-practices живут в operator-global
`~/.claude/CLAUDE.md` как ЕДИНЫЙ источник; файл `.claude/rules/practice-baseline.md` в проекте —
это дубликат (грузится поверх global → засоряет контекст). Travel-аргумент (коллега/клон без
global) оператором отклонён в пользу no-duplication.

## Откачено
- kit: revert `26ea6f3` → `24182ee` (восстановлена исходная delivery-процедура: global preferred,
  project-embed = fallback со skip-if-global). Pushed.
- AI_analyst_migration: revert `1316d37` → `737eb60` (файл + CLAUDE.md-ссылка убраны). Pushed.
- dialog_analyzer: reset на `a3cbbfe` (файл + ссылка убраны). Локально.

## Зафиксированный инвариант
Под этого оператора (у которого есть curated global §1–8): **НЕ предлагать project-embed
practice-baseline** — дубль. Global = single source, грузится во всех сессиях на машине; модель
практики применяет нативно (battle-test'ы #99–#100 подтвердили). Project-embed уместен только для
оператора БЕЗ global (другая команда) — но это не наш случай. Memory: practice-baseline-global-only.

## Урок
Противоречие «файлы-в-проекте» vs «no-duplication» неразрешимо одновременно при наличии global —
надо было назвать развилку (единый источник: global ИЛИ project) ДО того как класть файлы, а не после.
