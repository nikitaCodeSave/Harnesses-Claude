---
id: 95
date: 2026-06-11
title: "Strip: custom-агенты и skill-дубли built-ins удалены"
tags: [canon, strip, agents, skills, hooks]
status: complete
---

# Strip: custom-агенты и skill-дубли built-ins удалены

## Контекст
По распоряжению оператора — strip-ревизия лаборатории против свеже-переземлённого
инвентаря built-ins (kit v1.6.1): удалить агентов и навыки, дублирующие встроенный
функционал. Та же операция, что делалась в dialog_analyzer (F4/F5), теперь над собой.

## Удалено (lab `.claude/`)
- **agents/meta-creator.md** — дубль нативной способности: вся эволюция канона
  2026-06-11 (5 релизов kit'а) прошла без него; skills создаёт skill-creator plugin.
- **agents/security-reviewer.md** — дубль built-in `/security-review` (bundled);
  его loop-PROPOSAL-нюанс остался только в замороженных артефактах loop'а.
- **agents/discovery-critic.md + commands/critique.md + hooks/discovery-gate.sh**
  (+ дерегистрация из settings.json Stop) — superseded ритуалом `/external-audit`
  плагина (3 роли, AUDIT-*.json blackboard); Регламент v1 выбрал его отгружаемой
  формой, боевой прогон на dialog_analyzer подтвердил. История: devlog #62/#65.
- **skills/devlog/** (lab-копия SKILL.md) — отставший форк глобального канона
  (без транслитерации и machine-local-нюанса); ровно F5-дефект dialog_analyzer.
  Project-pin скрипта `.claude/devlog/rebuild-index.py` ОСТАВЛЕН (lab — git-shared
  репо, per devlog-skill teammate/CI-правило).

## Оставлено осознанно (не дубли)
`update-plan-progress` (progress-журнал — нет built-in), `loop-status` (R&D-loop
инспектор), глобальные `grill`/`tdd`/`devlog`/`remember` (curation-ритуал поверх
auto-memory, не дубль `/memory`), хуки session-context / stop-validation /
loop-protected-guard / cost-warn.

## Обновлены доки текущего состояния
CLAUDE.md (self-evolution, агенты, skills), principles.md (components inventory,
hooks), multi-agent.md §4, memory-layers.md (inter-agent blackboard → AUDIT-*.json),
harness-architecture.md (composition-примеры), workflow-evolution.md. Замороженные
слои (loop/, benchmark/, plans/, worktrees/, archive) не тронуты — исторические
артефакты.

## Verify
grep по живым докам: упоминания удалённых компонентов остались только как записи
об удалении; сессионный список скиллов после правки — devlog один, `/critique`
исчез; Stop-hook список в settings.json = stop-validation. Итог: custom-агентов
в лаборатории 0, custom-skills 1 (update-plan-progress).
