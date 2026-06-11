---
id: 97
date: 2026-06-11
title: "Kit v1.8.0: production-grade default + отгружаемая выжимка"
tags: [canon, kit, bootstrap, docs, workflow]
status: complete
---

# Kit v1.8.0: production-grade default + отгружаемая выжимка

## Контекст
Продолжение #96. Две директивы оператора: (1) kit отгружает самую ценную
выжимку workflow файлами в `.claude/docs/` проекта — push-канал, доступный
каждой сессии без вызова скилла, обновляемый через плагин; (2) дефолтная
посадка — production-grade независимо от размера проекта («пишу проекты
с нуля сразу с расчётом на продакшен-релизы»); MVH — только по явной
просьбе. Зафиксировано memory `production-grade-default`.

## Изменения (канон `~/.claude`, commit f6fa4d3, tag v1.8.0)
- **НОВОЕ** `references/project-docs/{workflow,testing,docs-discipline}.md` —
  отгружаемая выжимка: полный flow (session-ритуал → план → red→green →
  верификационная лестница → continuity → production posture), 5
  testing-инвариантов, doc-with-code mapping-таблица. Заголовок
  `shipped-by: claude-code-harness vX.Y.Z` = канал обновления.
- `bootstrap-checklist.md`: дефолт перевёрнут (production-grade shape:
  CLAUDE.md + settings + offered baseline + `.claude/docs/` + root
  docs/ARCHITECTURE+CODE-MAP); новая Phase 2c — verbatim-копирование выжимки
  (project-факты не вписывать — re-sync должен оставаться тривиальным diff'ом);
  Phase 7 + ls-проверка пяти файлов.
- `audit-checklist.md`: re-sync по версии (diff оператору до перезаписи —
  hand-edits/переводы не уничтожаются молча; «header новее плагина → обнови
  плагин»; отсутствие выжимки на non-MVH проекте = finding).
- `SKILL.md`/`operator-playbook.md`: handoff footer и карта слоёв обновлены;
  явная фраза «set up a minimal harness» для MVH.

## Верификация
- Fresh-context refuter #2: 14 находок, 2 HIGH (правка проглотила заголовок
  Phase 3 — MVH остался бы без settings.json; Phase 0 routing противоречил
  новому дефолту) — все 14 закрыты до коммита; структура фаз перепроверена
  grep'ом заголовков.
- Выжимка отгружена в живой проект 11062026 (commits ded0a6a + re-sync,
  devlog #12 там) — первый потребитель Phase 2c.

## Решения
- Posture-flip — осознанная директива владельца, не вывод из единичного
  кейса; headline-принцип не нарушен: «production-grade» = документы +
  конвенции, машинерии по-прежнему ноль (custom agents/hooks — только по
  триггерам).
