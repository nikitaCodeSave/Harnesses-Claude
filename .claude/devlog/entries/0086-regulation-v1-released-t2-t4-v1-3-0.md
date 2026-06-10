---
id: 86
date: 2026-06-10
title: "Regulation v1 released: T2-T4 v1.3.0"
tags: [harness, regulation, release, plugin, workflow]
status: complete
---

# Regulation v1 released: T2–T4 пройдены, плагин v1.3.0

## Контекст
Закрытие трека «Регламент v1» (план `.claude/plans/standard-v1-regulation.md`): после T1 (#85)
оставались T2 (легаси-аудит), T3 (n=2), T4 (внешний walkthrough) и Phase 4 (D.3 + релиз).
Выполнено за одну сессию тремя мультиагентными workflow с итерацией оркестратора между ними.

## Изменения

**T2 — AI_analyst_migration (WF1: 6 read-only аудиторов ∥ → synthesizer; WF2a: apply).**
Gap-report: 24 гэпа (5 safe-additive / 13 reversible / 6 destructive), per-component вердикты
7 agents + 13 skills — `migration/.claude/audit/gap-report-2026-06-10.md` + lab
`.claude/audits/t2-migration/`. Применена ТОЛЬКО корзина A (G1 permissions-блок с deny на
живые банковские креды, G2 init.sh-оракул, G3 features.json, G4 progress/, G5 gitignore);
без коммитов — на ревью оператора; оракул identical до/после (1397 passed + 1 pre-existing
fail на HEAD: test_settings response_temperature 0.5≠0.7 — находка оракула, не правок).
**Корзины B/C ждут операторского approve** (риск R3 соблюдён).

**T3 — prompt-regress (WF2b: bootstrap → фича → Evaluator, все fresh-context).**
Полный цикл по playbook: bootstrap+Phase 5 kit (49cefce) → F1 «promptdiff compare» строгим
TDD (RED-коммит до реализации → GREEN, 17/17, smoke на реальных прод-CSV, exit-code контракт
1/0/2) → независимый Evaluator: **confirmed_with_debt** (major: CI-gate нем на 4-колоночном
урезанном экспорте — spec-literal, долг записан «reproduce→close»). Journal: 6 наблюдений,
3 kit-gap зафолжены в канон (8b809be): canonical schema features.json, per-runner
empty-suite guard, правило «диск истиннее контракта».

**T4 — walkthrough-аудит регламента (WF3: 2 наивных исполнителя ∥ → adjudicator R2).**
Исполнением, не чтением: полный цикл нового проекта (bootstrap → Phase 5 → TDD-микрофича)
∥ легаси-путь (fabricated-репо → audit-режим → §5–§7). Вердикт: **confirmed_with_debt,
0 blockers** (оба walker'а passed_with_friction), 2 major + 10 minor, 0 dismissed —
`.claude/audits/t4-walkthrough/AUDIT-VERDICT.json`.

**Phase 4 — D.3 fold + релиз (dot-claude 5f9734e).**
- major: README получил секцию «Вход в регламент» (явная ссылка на operator-playbook +
  легаси-путь §4 — главный страх оператора подтверждён и закрыт); противоречие
  approval-гейта разрешено (headless flow: действовать + фиксировать план).
- minor (7): Phase 0 git-guard на 0-коммитном репо; Phase 7 crisp pass-критерии;
  playbook §2 «ledger засеивает сессия, ревьюит оператор»; §3 PATH-hygiene (печатать
  resolved-интерпретатор); §4 маршрут к шаблону в SKILL.md; external-audit: legacy-ветка
  Шага 0, ROLE_DIR проверяет role-файлы (не каталог), pre-flight `claude plugin list`;
  harness-evolution: триггер D-цикла для проектов без journal.
- Skipped как single-incident (watch): src-layout/conftest import mechanics.
- Strip-ревизия: всё добавленное в Phase 1 использовано — удалять нечего.
- v1.2.0→v1.3.0 синхронно, validate ✔✔, tag `claude-code-harness--v1.3.0`,
  re-smoke на чистом профиле (лог 11: Skills 2 / Agents 3).

## Затронутые файлы
- `~/.claude` (8b809be, 5f9734e): README, bootstrap-checklist, operator-playbook,
  external-audit.md, harness-evolution.md, оба манифеста
- `migration/`: 6 файлов корзины A (uncommitted, на ревью) + gap-report
- `~/PROJECTS/prompt-regress`: новый репо, 4 коммита (bootstrap → RED → GREEN → debt)
- lab: `.claude/audits/{t2-migration,t3-prompt-regress,t4-walkthrough}/`, progress

## Проверка
- Оракулы: migration pytest identical до/после; prompt-regress ./init.sh GREEN 18 passed.
- Вердикты: T3 Evaluator + T4 adjudication — оба confirmed_with_debt, долги actionable.
- Релиз: оба манифеста validate; re-smoke v1.3.0 чистый профиль — inventory полный.
- DoD: 1✅(T4 без блокеров) 2✅(T1-артефакты) 3✅(R2+T1) 4◐(корзина A; B/C за approve)
  5✅(T3) 6✅(commits+devlog+tag). Push dot-claude/lab — за оператором.

## Related
- #85 — T1 smoke + упаковка v1.2.0
- #84 — Phase 1→2 (R4/R6, v1.1.0)
- #83 — Phase 1 (playbook, /external-audit)
