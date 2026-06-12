---
id: 102
date: 2026-06-13
title: "practice-baseline project-embed по умолчанию (two-consumer fix)"
tags: [canon, kit, harness-evolution, practice-baseline]
status: complete
---

# practice-baseline project-embed по умолчанию (two-consumer fix)

## Контекст
Фидбэк оператора: при `/claude-code-harness` в проектах появляется недостаточно файлов, чтобы
агенты знали best-practices (рекомендации Anthropic/Boris). Диагноз: §1–8 (think-before-coding,
simplicity, surgical, goal-driven, tests-you-run, continuity, guardrails, fresh-context verify) —
это и есть та выжимка — жили ТОЛЬКО в operator-global `~/.claude/CLAUDE.md`. В сессиях оператора
агенты их знали (battle-test'ы подтвердили), но в проектах их не было как файлов → не видны, не
едут к коллеге/на сервер/в клон, не аудируются. Отсюда «файлов мало».

## D-cycle finding (слепая зона плагина)
Delivery-процедура practice-baseline оптимизировала под ОДНОГО потребителя (operator-on-this-machine:
global хватает) и прямо предписывала «skip project-embed, если global уже содержит». Но второй
потребитель — **любой, кто получает репо** (коллега/CI/деплой/клон) — operator-global не имеет,
поведение к нему не едет. Процедура реструктурирована на **two consumers**: project-embed =
ДЕФОЛТ (носитель, который едет с репо), global merge — поверх, как cross-project удобство оператора;
redundancy (~58 строк дважды) осознанна для traveling-репо. Правки: `practice-baseline.md`
(процедура), `bootstrap-checklist.md` (Phase 2b + таблица), `SKILL.md` (шаблон). Commit 26ea6f3, pushed.

## Применено к активным проектам
- AI_analyst_migration: `.claude/rules/practice-baseline.md` + индекс в CLAUDE.md (commit 1316d37, pushed feature-ветка).
- dialog_analyzer: то же (commit f6e533b, локально — без remote).
Оба теперь self-contained: §1–8 едут с репо.

## Нюанс (честно)
Для самого оператора §1–8 теперь грузятся дважды (global + project). Это осознанная цена за
self-containment/travel, помечена в заголовке файла. Не «фиксить» удалением носителя.
Backlog-пункт «practice-baseline fold» закрыт.
