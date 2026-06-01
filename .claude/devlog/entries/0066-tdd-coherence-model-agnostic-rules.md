---
id: 66
date: 2026-06-01
title: "tdd coherence model-agnostic rules"
tags: [harness, tdd, testing, principle, coherence]
status: complete
---

# tdd-flow coherence: de-dogmatize, de-version, bridge to §8

## Контекст
Аудит согласованности: как глобальный `tdd` skill ложится во flow и используются ли
результативные практики. Вердикт — в основном когерентно: `tdd` = глубокое разворачивание
§5 (принцип в CLAUDE.md дёшево-всегда, методология в skill on-demand), evidence-grounded
(`references/agent-test-evidence.md`, T1–T5, 13/15 verified), де-догматизирован (red-first
optional), opt-in. Нашлись 3 трения; оператор уточнил ключевой принцип.

## Принцип (оператор, durable)
**Skills/rules не привязывать к конкретной версии модели** — модель обновляется, version-binding
делает практику устаревающей и мешающей. Формулировать поведение model-agnostic; skill должен
**помогать корректно писать код, а не ограничивать**. Исключение — датированный evidence-провенанс
(честный источник «когда/против чего проверено»). Зафиксировано: [[feedback_model_agnostic_skills]].

## Правки (3, хирургические)
1. **`.claude/rules/testing.md` rule #2 — де-догматизирован.** Было: «Тест ДОЛЖЕН сначала упасть
   (RED)» как инвариант ordering'а. Стало: «Тест проверяет поведение и способен упасть; увидь
   реальный failure прежде чем считать рабочим; порядок red→green — дефолт, не догма; рычаг —
   runnable-оракул + assert через публичный интерфейс, не очерёдность». Согласовано с §5 / tdd /
   evidence / ADR-003. Rule #5 (RED перед багфиксом) не тронут — там RED-first каузально обоснован.
2. **`.claude/rules/testing.md` rule #1 — де-версионирован.** «Opus 4.7 предложит тесты сам» →
   «предложи и запусти их сам в той же сессии». Поведение без привязки к версии.
3. **`~/.claude/skills/tdd/SKILL.md` — мост на §8.** Добавлен шаг «5. Independent Review
   (high-stakes)»: green+refactor = author-side, necessary-not-sufficient; для high-stakes —
   independent fresh-context review (отдельная сессия/subagent, prompt «опровергни»), ось
   evaluator-side ⊥ методологии. Закрывает петлю author→evaluator (§5→§8).

## Затронутые файлы
- `.claude/rules/testing.md` (rule #1 де-версия, rule #2 де-догма)
- `~/.claude/skills/tdd/SKILL.md` (+шаг 5 → §8; вне git-репо)
- memory: `feedback_model_agnostic_skills.md` (new), `MEMORY.md` (индекс)

## Related
- #65 (§8 fresh-context principle) — мост из tdd ведёт сюда.
- [[feedback_model_agnostic_skills]], [[feedback_empirical_over_theoretical_dismiss]];
  ADR-003 (TDD не зашит как мета-обвязка). foundational principle (минимум обвязки).
- TODO-cleanup (не блокер): индексный заголовок `feedback_no_upfront_contract_interview`
  всё ещё содержит «under Opus 4.7» — кандидат на де-версию по этому же принципу.
