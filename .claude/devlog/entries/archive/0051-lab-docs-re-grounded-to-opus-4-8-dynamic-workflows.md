---
id: 51
date: 2026-05-29
title: "Lab docs re-grounded to Opus 4.8 + dynamic workflows"
tags: [docs, harness]
status: complete
---

# Lab docs re-grounded to Opus 4.8 + dynamic workflows

## Контекст
Продолжение devlog #50 (то записало «остаётся глубокий re-ground lab-доков»). Четыре
on-demand reference-дока были приколочены к Opus 4.7 / CC 2.1.143 и пропускали главный
новый workflow-примитив — dynamic workflows. Harness'а собственная доктрина
(`workflow-evolution.md`) трактует major-релиз модели как триггер полного re-ground'а.
Помимо version-пинов разведка вскрыла **фактические ошибки**: `principles.md` и
`multi-agent.md` перечисляли несуществующие компоненты.

## Изменения
- **`principles.md`** (9 правок): foundational 4.7→4.8; «spawn fewer» переформулирован в
  single-agent-first + dynamic-workflows escape hatch; effort `xhigh`→`high`; context-rot
  порог ~256–400K помечен pending re-measurement (GraphWalks 1M F1 ~40→68% на 4.8);
  **секция «Components inventory» исправлена по реальному состоянию** (была: `deliverable-planner`,
  `secret-scan`, `dangerous-cmd-block`, `auto-format` — все несуществующие; стала: реальные
  agents/hooks/skills, built-ins 5); security boundary → `system-guard.sh` + нативный 4.8;
  cost-envelope помечен 4.7-era re-measure-due.
- **`workflow.md`** (7 правок): title 4.8; effort default `high` + `ultracode`; в routing-таблицу
  добавлен ряд dynamic workflows (codebase-scale / миграция / convergence); anti-patterns
  переформулированы (multi-agent nuance + «не переизобретать оркестрацию»).
- **`multi-agent.md`** (14 правок): title + model-таблица 4.8; **фикс «custom = 2 deliverable-planner»**
  → 3 реальных (meta-creator / security-reviewer / discovery-critic); +90.2% помечен 4.7-era;
  Teams-слой → `TeamCreate` experimental; **ключевой reframe §7.2**: P/G/E и adversarial-convergence
  теперь нативны на CLI-подписке через dynamic workflows — managed-agents API больше не нужно
  портировать вручную; Driver-Navigator → Opus 4.8.
- **`builtins-inventory.md`** (4 правки): ⚠️-баннер «2.1.143-era, каноничный срез — native-capabilities.md»;
  built-ins 5 (+claude-code-guide); effort default `high`; `/fast` = ускорение не downgrade.

Принцип минимализма: `builtins-inventory.md` НЕ переписан целиком (дублировал бы каноничный
глобальный `native-capabilities.md`) — баннер + точечные фиксы.

## Затронутые файлы
- `.claude/docs/principles.md`, `.claude/docs/workflow.md`, `.claude/docs/multi-agent.md`,
  `.claude/docs/builtins-inventory.md`

## Проверка
- `grep "4\.7"` по активному слою — оставшиеся вхождения верифицированы как легитимные
  (исторические сравнения «на 4.7 было xhigh», dated citations, добавленные мной caveat'ы).
- `grep "deliverable-planner|secret-scan|dangerous-cmd-block|auto-format"` по активному слою → none (clean).

## Related
- #50 — структурная консолидация стартера (ретайр harness-setup, промоут claude-code-harness global).
- Pending (требует явного greenlight, $/время): re-measure cost-envelope под 4.8 через `benchmark/`
  rig; пересмотр `.claude/loop/` как retire-candidate (dynamic workflows — нативный преемник).
