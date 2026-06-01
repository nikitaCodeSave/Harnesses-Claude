---
id: 64
date: 2026-06-01
title: "sync-docs retired into docs-discipline rule"
tags: [harness, docs, skills, retire]
status: complete
---

# sync-docs retired into docs-discipline rule

## Контекст
Аудит глобальных `~/.claude/skills/` на предмет неактуальных под Opus 4.8 / расходящихся
с выводами исследований. 7 скиллов; разбор по ролям.

## Вердикт по скиллам
**Оставлены** (по ролям, не дублируют built-in/native): `claude-code-harness` (канон дизайна,
re-ground 4.8), `devlog` (живой action-skill), `tdd` (столб #1), `project-docs-bootstrap`
(разовая настройка doc-контракта; окупается на large/non-obvious кодбейсе), `grill`
(opt-in `disable-model-invocation`; ценен при прототипировании/формулировании целей — по
решению оператора оставлен, «no upfront interview» относится к *авто-навязанному* интервью,
явный `/grill` ему не противоречит).

**Ретайрнут** (→ `~/.claude/_archived-skills/sync-docs/`): `sync-docs`. Скилл держал docs в
синхроне с кодом, но его собственное ядро дублировало `docs-discipline.md` rule #1
(doc-with-code). research-архив (`practices-from-projects.md`) уже выносил вердикт **«0 —
не добавляем: синхронизация docs делается из main thread нативно, без skill/agent-spawn»**.
Под Opus 4.8 классификация git diff → какие разделы править — нативная работа; отдельный
сырой skill поверх правила ценности не добавлял. Живых рефов не было (только ретайрнутый
`harness-setup` + auto-history).

## Что сделано
- Полезное ядро `sync-docs` (таблица «категория diff → документ» + эскалация-триггеры)
  перенесено в `.claude/rules/docs-discipline.md` rule #1 как компактный reference — намерение
  (docs остаются актуальными) живёт теперь как **правило**, надёжнее переживающее потерю
  контекста, чем раздельный skill. Глобального `~/.claude/rules/` не существует — канон правила
  авторится в этой лаборатории.
- `sync-docs` перемещён в `~/.claude/_archived-skills/` (тот же паттерн, что retired
  `harness-setup`; `~/.claude` не под git → перенос = единственная форма обратимости, не `rm`).

## Затронутые файлы
- `.claude/rules/docs-discipline.md` (rule #1 + mapping-таблица + эскалация)
- `~/.claude/skills/sync-docs/` → `~/.claude/_archived-skills/sync-docs/` (перенос, вне git-репо)

## Related
- foundational principle (минимум обвязки; native takes precedence) — [[feedback_native_capabilities_take_precedence]].
- #50/#51 (ретайр `harness-setup`, тот же archive-паттерн).
- #63 (continuity-аппарат обходится) — та же линия: правило/привычка > сырой аппарат.
