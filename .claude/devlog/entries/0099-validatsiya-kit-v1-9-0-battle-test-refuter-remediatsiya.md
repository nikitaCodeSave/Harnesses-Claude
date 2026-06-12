---
id: 99
date: 2026-06-12
title: "Валидация kit v1.9.0: battle-test + refuter-ремедиация"
tags: [canon, kit, harness-evolution, benchmark, validation]
status: complete
---

# Валидация kit v1.9.0: battle-test + refuter-ремедиация

## Контекст
Фидбэк оператора: «claude-code-harness ни разу не удалось успешно применить на моих
проектах — всегда потеря знаний и низкое качество». Решено проверить обновлённый harness
dialog_analyzer (v1.9.0, devlog #98/#26) не самоотчётом, а тремя свежими контекстами:
gap → battle-test → adversarial judge. Методология — lab A/B-дисциплина (worktree-изоляция,
fresh-context judge ≠ author, §8).

## Три прохода (background agents, fresh context)
1. **refresh-refuter** (read-only, опровергал «refresh сохранил всё знание») — вердикт
   **REFUTED узко**: fold A1/A2/A3 fidelity STANDS, версии чистые; но 3 MED-находки —
   (a) выпала инструкция read-before-edit/recon-дисциплина (нет ни в slim'е execution.md,
   ни в baseline); (b) plan-mode противоречие: baseline «switch to plan mode yourself» vs
   проектный `/task-planning` «по умолчанию НЕ входить» (#49947 footgun); (c) LOW —
   empirical-first в трёх местах.
2. **cold-implementer** (ветка `experiment/rerun-protection`, минимальный промпт) реализовал
   queued-фичу `rerun_protection` из одного только harness'а: сам нашёл рекомендацию B+A,
   отзеркалил паттерн `_checkpoint_corrupted`, red-check по testing-#2, настоящий
   empirical-first e2e на живом Ollama (0 LLM-вызовов на rerun). 39 passed (+2), ruff clean.
3. **feature-judge** (исполнением, опровергал корректность) — **CONFIRMED, mergeable**:
   независимо воспроизвёл red-check (сломал триггер `main.py:242` → тест упал `assert 2==1`
   → восстановил), протрассировал края (пустой вход защищён `len>0`-гардом; partial —
   задокументированное наследуемое поведение; mixed — агрегация корректно идёт), отчёт честен.

## Вывод
Гипотеза «harness всегда теряет знание + низкое качество» на этом кейсе **опровергнута двумя
независимыми fresh-context'ами**: знание передалось холодному агенту, качество подтверждено
исполнением. Реальные дыры refresh'а (refuter) под способной моделью оказались малоимпактными
(implementer в них не провалился — читал перед правкой, делал recon, не входил в Plan Mode) —
кроме plan-mode footgun'а, который пофикшен.

## Ремедиация (долита в незакоммиченный v1.9.0, без бампа)
- kit `project-docs/workflow.md` «Plan before code»: «switch to plan mode» теперь **уступает
  проектному ритуалу планирования** («unless the project defines its own planning ritual —
  follow that»); возвращена recon-строка (grep аналогичного паттерна + зависимостей перед
  кодом, чтобы расширять, а не дублировать). Read-before-edit как голую прозу НЕ возвращал —
  механически гарантирован Edit-tool'ом (read-before-write), принцип 5.
- dialog_analyzer: baseline re-synced verbatim (IDENTICAL ✓); в `execution.md` добавлен
  **директивный** override — «планирование через `/task-planning`, НЕ Plan Mode (#49947)».
- Verify: 39 passed; project `.claude/docs/workflow.md` == kit canon; версии 1.9.0 везде.

## Открыто (решение оператора)
- Фича `rerun_protection` (ветка `experiment/rerun-protection`, uncommitted, CONFIRMED
  mergeable) — была носителем теста; оставить/влить или сбросить.
- Коммит kit v1.9.0 + refresh dialog_analyzer — за оператором (harness-changes uncommitted в
  обоих репо; опционально `/external-audit` перед коммитом kit, хотя 3 fresh-context'а уже прошли).
