---
id: 98
date: 2026-06-12
title: "Kit v1.9.0: fold практик dialog_analyzer (D-cycle)"
tags: [canon, kit, harness-evolution, workflow]
status: complete
---

# Kit v1.9.0: fold практик dialog_analyzer (D-cycle)

## Контекст
Директива оператора: довести плагин `claude-code-harness` до уровня, на котором он
переносит наработки «фабрики» в др. проекты. Мишень — реальный аудит harness'а
dialog_analyzer (`/home/nikita/Документы/dialog_analyzer`): pre-v1.8 родословная, местами
**богаче** kit'а. Аудит (Mode 2) выявил три практики, которые проект доказал, а плагин НЕ
транслировал — это D-cycle harvest (project → kit), а не refresh.

## Изменения (канон `~/.claude`, kit v1.8.0 → v1.9.0)
- **A1 empirical-first** → `references/project-docs/workflow.md` «Work»: для вероятностных /
  IO-тяжёлых / data-shape-зависимых путей (LLM, пайплайны, агрегация, парсеры) — прогон на
  реальном представительном входе ДО фиксации дизайна; зелёный тест на моках не покрывает
  real-corpus edge cases. Stack-agnostic; конкретную команду даёт проектный CLAUDE.md.
  Источник: dialog_analyzer `execution.md` + его evidence «5 из 23 devlog'ов — re-work».
- **A2 anti-thrash** → та же секция: 2–3 неудачных итерации → стоп и эскалация, а не
  бесконечный патчинг; «ломает многое» = сигнал неверного подхода.
- **A3 plan-mode caveat** → `workflow.md` «Plan before code»: совет «switch to plan mode
  yourself» получил оговорку — при включённом Auto Mode `ExitPlanMode` его выключает
  (anthropics/claude-code#49947); предпочесть read-only recon + written plan file.
- **Version bump** 1.8.0→1.9.0: `.claude-plugin/plugin.json` + три `shipped-by`-заголовка
  (`workflow/testing/docs-discipline.md`) — re-sync на audit'е keys на них (SKILL.md
  maintenance rule). testing/docs-discipline контент не менялся — заголовки бампнуты для
  консистентности (иначе audit пометит stale).

## Верификация
- grep: остатков `v1.8.0` в kit нет, кроме провенанса (`pre-v1.8` в audit-checklist,
  last-updated стамп operator-playbook) — оба намеренно сохранены (§1: provenance ≠ behavior).
- Отгружено в dialog_analyzer тем же циклом (devlog #26 там): 3 дока verbatim, pytest 37
  passed, execution.md ужат 81→48 строк до addendum'а.

## Решения
- Folded в shipped `workflow.md` (канал распространения по решению B1 «baseline+addendum»), не
  в `practice-baseline.md` — чтобы практика ехала в каждый проект, а не только в global merge.
  practice-baseline как дом для A1/A2 — возможный follow-up, не в этом цикле (surgical scope).
