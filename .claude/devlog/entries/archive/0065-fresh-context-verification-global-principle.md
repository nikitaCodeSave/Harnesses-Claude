---
id: 65
date: 2026-06-01
title: "Fresh-context verification global principle"
tags: [harness, principle, critique, verification]
status: complete
---

# Fresh-context verification global principle (CLAUDE.md §8)

## Контекст
Оператор: вывод #62 (ценность critique — в свежем неякорённом контексте, не в premortem-
ритуале) — это ключевой workflow-point работы с Claude Code, **не менее важный, чем
структурно зафиксированный подход к разработке** (TDD/BDD/DDD/…). Проверка глобального слоя
выявила реальный пробел: `~/.claude/CLAUDE.md` кодировал верификацию только **author-side**
(§4 loop-until-verified, §5 tests-you-run), а evaluator-side (judge≠author, fresh context)
жил **только в лаборатории** (`discovery-critic`, `/critique`) и в другие проекты не ехал.

## Решение
Добавлен глобальный принцип `~/.claude/CLAUDE.md §8 "Independent Verification — Fresh Context,
Not Self-Recheck"`. Ключевые тезисы: рычаг high-stakes проверки — независимый свежий контекст
(отдельная сессия / subagent, судящий результат), НЕ второй проход в том же контексте
(in-context self-recheck под 4.8 = ~0, автор якорится). Ортогонально подходу к разработке:
TDD/BDD/… = author-side «как строить», §8 = evaluator-side «кто судит»; дополняют, не заменяют.
Opt-in (high-stakes/необратимое/«выглядит готовым»). Механизм нативный: spawn fresh reviewer,
prompt «опровергни», не «подтверди».

## Почему это не нарушает «single-incident в invariant не превращается»
Порог взят за счёт **совпадения двух источников**: (1) наша эмпирика #62 (fresh-context критик
поймал реальный баг мимо всех нативных проходов; in-context премортем = 0 лифта); (2) внешний
канон judge≠author / Planner→Generator→Evaluator (multi-source). Именно это сочетание —
условие появления компонента по foundational principle, в отличие от опоры на один замер.

## Объём (по выбору оператора): principle-only
Только принцип в traveling-слое; механизм остаётся нативным. Глобальный `discovery-critic`
агент / `/critique` команда **НЕ** переносились в `~/.claude/` — минимализм, и согласуется с #63
(аппарат, полагающийся на само-включение, слаб; принцип в CLAUDE.md переживает потерю контекста
надёжнее). Полный `discovery-critic` остаётся в лаборатории для R&D.

## Затронутые файлы
- `~/.claude/CLAUDE.md` (+§8; вне git-репо — фиксация здесь)
- memory: `reference_critique_fresh_context_lever.md` (+ структурная фиксация), `MEMORY.md` (индекс)

## Related
- #62 (эмпирика fresh-context-рычага), #63 (правило/привычка > сырой аппарат — та же линия).
- [[reference_critique_fresh_context_lever]]; foundational principle (минимум обвязки, multi-source порог).
