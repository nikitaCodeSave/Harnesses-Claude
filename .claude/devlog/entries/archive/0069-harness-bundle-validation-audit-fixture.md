---
id: 69
date: 2026-06-01
title: "Harness bundle validation audit fixture"
tags: [harness, measurement, validation, skills]
status: complete
---

# Harness bundle validation via seeded audit fixture

## Контекст
Оператор: провести валидацию на тестовом проекте — работает ли связка `claude-code-harness`
skill + `~/.claude/CLAUDE.md` корректно и повышает ли качество (после арка #65–#68). По нашему
правилу [[feedback_test_iterations_via_worktree]]: судить по acceptance против реального target,
не по self-confidence. Честная оговорка: #52/#61/#63 показали, что single-shot greenfield НЕ
показывает quality-lift — поэтому валидирую то, что проверяемо оракулом: корректность работы
связки, особенно новый triage-rule из #68.

## Дизайн
Seeded harness-фикстура (`.claude/benchmark/audit/harness-audit-fixture/`) с 5 посаженными
дефектами + answer key. **Свежий general-purpose агент** (fresh context = §8 judge≠author, аудитор
≠ автор правок) применил skill в Audit-режиме, READ-ONLY, выдал findings-таблицу с колонкой
version-ref class. Сверка с ключом по recall + precision.

## Результат — PASS
- **Recall:** D1 (de-version behavioral) ✅, D3 (in-context self-recheck → cut, **процитировал
  §8/#62 «in-context premortem = 0 lift» и предложил fresh-context discovery-critic**) ✅,
  D4 (built-in orchestrator дубль → remove, + поймал spawn-per-subtask over-reach) ✅. D2
  (native-redundant «verify before done») — defensible lenient KEEP, judgment difference, не ошибка.
- **Precision (главный тест — triage rule #68):** D5 разбит на 3 finding'а, **все** классифицированы
  `provenance/config` → KEEP с корректным обоснованием (grounding stamp / un-re-measured finding /
  config+historical). `prod.tfvars` guardrail сохранён И поднят до `permissions.deny` (§7). **Ноль
  false-positives** — провенанс не срезан, легитимный guardrail не принят за дефект.
- **Дискриминатор:** D1 де-версионирован, D5 сохранён — хотя оба содержат «Opus 4.x». Version-triage
  **4/4 верно** (1 behavioral→de-version, 3 provenance→keep).

## Вывод
Связка работает когерентно из холодного fresh-контекста: новый triage-rule (#68) применяется верно,
§7 (mechanical guard) и §8 (fresh-context review вместо in-context recheck) **пропагировали** в
рассуждение аудитора. «Качество работы связки» подтверждено на проверяемой оси. Это capability-check
с видимым корректным reasoning'ом (не угадайка), n=1 / single fixture — directional, не power.
Фикстура сохранена как переиспользуемый regression-артефакт для будущих правок skill'а.

## Затронутые файлы
- `.claude/benchmark/audit/harness-audit-fixture/` (new — фикстура + answer key + run-log README)

## Related
- #65 (§8), #66 (tdd/testing), #67 (lab де-версия), #68 (skill де-версия + audit triage rule) —
  этот прогон валидирует весь арк. [[feedback_test_iterations_via_worktree]], [[feedback_model_agnostic_skills]].
- Не закрывает dev-flow quality-lift (по #52/#61/#63 single-shot его зануляет); эта ось стоит на #62.
