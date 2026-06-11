---
id: 96
date: 2026-06-11
title: "Kit v1.7.0: write-through практик в проекты"
tags: [canon, kit, bootstrap, workflow, docs]
status: complete
---

# Kit v1.7.0: write-through практик в проекты

## Контекст
Battle-test плагина на реальном проекте (11062026/granola, 6 сессий, 8 фич)
показал разрыв: артефактные практики с механическим каналом доставки
(features.json, progress, devlog, red→green из глобального baseline)
исполнялись образцово, а практики, жившие текстом в референсах kit'а,
не проявились ни разу — 0 предложений ступеней верификационной лестницы,
интеграционная сессия без плана, `docs/` не появился за 8 фич (условие
«if the project keeps docs/» инвертировало причинность). Оператор
сформулировал исходную задачу плагина: передавать **весь** опыт фабрики,
включая ценность глобального `~/.claude/CLAUDE.md`, который plugin-установка
не везёт.

## Изменения (канон `~/.claude`, commit 38d6fbb)
- **НОВОЕ** `references/practice-baseline.md` — transmittable поведенческий
  baseline §1–8 (self-sufficient: вычищены ссылки на личные хуки/скиллы) +
  delivery-процедура: detect → global merge (с approve) → project-embed
  `.claude/rules/` → headless-правило.
- `bootstrap-checklist.md`: Phase 2b (доставка baseline, dedupe против Working
  style, retire-триггеры); Working style → proposal duties (plan-mode
  self-entry; лестница `/review` сам → fresh-context → external-audit —
  предлагать оператору следующую ступень); Phase 5 item 6 — docs/
  ARCHITECTURE.md + CODE-MAP.md создаются на bootstrap'е (для sustained build
  безусловно); Phase 7 — механический write-through check (grep вместо
  `--print`: поведенческий probe контаминирован глобальным слоем); Phase 4 —
  санкционированное исключение для 60-строчного embed'а.
- `SKILL.md` / `operator-playbook.md` / `audit-checklist.md` синхронизированы;
  audit-режим больше не флагует deliverables bootstrap'а как cruft.
- Версия 1.6.1 → 1.7.0 (plugin.json + marketplace.json).

## Верификация
- Fresh-context refuter (§8): 14 находок, из них 2 HIGH (контаминация Phase 7
  check'а глобальным слоем; противоречие Phase 4 cap ↔ Phase 2b embed) — все
  закрыты до коммита; «Stands»: self-sufficiency baseline, semver, Phase 5
  item 6, размер Working style.
- Ретрофит применён к живому проекту 11062026 (commit 541cf62, devlog #11 там):
  CLAUDE.md → indexer 120 строк, docs/ создан, факты сверены после
  параллельной правки другой сессией.

## Открыто
- Single-source evidence: паттерн подтверждён одним проектом (но консистентно
  по всем его сессиям). Следующий bootstrap нового проекта на v1.7.0 —
  естественная проверка write-through (Phase 7 check + наблюдение, предлагает
  ли сессия лестницу).
