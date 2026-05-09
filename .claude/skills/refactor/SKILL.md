---
name: refactor
description: Plan-mode refactoring strategy for a named scope, then execute. Delegates design to built-in Plan agent, returns to main thread for implementation. Use when a non-trivial refactor needs design before edits. Skip for trivial renames or single-file changes.
disable-model-invocation: true
allowed-tools: Read, Glob, Grep
---

Scope/цель рефакторинга: $ARGUMENTS.

Workflow:
1. Делегируй design в built-in `Plan` агента через Task tool. В prompt'е Plan'у — текущий код в scope, цель, ограничения (что НЕ менять), и acceptance: рабочие тесты после.
2. Получи план от Plan; рассмотри trade-offs; при необходимости — итерируй с Plan ещё раз.
3. Применяй изменения в основном потоке (main thread), НЕ через subagent. Builder работает coherently for hours — не дроби на микро-задачи.
4. После каждой логической группы изменений — запусти тесты; не накапливай красных тестов.

НЕ начинай редактировать без принятого Plan. НЕ расширяй scope в процессе — если требуется — выйди из refactor, обсуди, вернись.
