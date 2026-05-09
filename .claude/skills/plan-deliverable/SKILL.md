---
name: plan-deliverable
description: Convert a stated goal into a 1-page deliverable spec with acceptance criteria and verification mechanism, NOT a task breakdown. Use when developer states a goal without explicit acceptance criteria. Skip when goal already has clear acceptance criteria.
disable-model-invocation: true
allowed-tools: Read, Glob, Grep, AskUserQuestion
---

Выполняется **в main thread** (не через `context: fork`), потому что для
неоднозначных целей нужен `AskUserQuestion`, недоступный в forked
subagent'ах (ADR-007).

Goal от пользователя: $ARGUMENTS.

Алгоритм:
1. Если goal неоднозначен (нет ясного scope, нет очевидных acceptance
   criteria, не указан verification mechanism) — задать ≤3 вопросов через
   ОДИН вызов `AskUserQuestion`. Иначе — переходить к шагу 2.
2. Произвести 1-страничную spec (вернуть пользователю как сообщение, не
   как файл, если пользователь явно не попросил persistence):

   - **Goal**: одно предложение
   - **Acceptance criteria**: 3-7 пунктов, каждый верифицируемый
   - **Verification**: команда / lint / manual checklist
   - **Out of scope**: явный список того, что НЕ входит

НЕ декомпозировать на микро-задачи. Под Opus 4.7 декомпозиция мешает
course-correct (см. ADR-002 в `docs/HARNESS-DECISIONS.md`).
