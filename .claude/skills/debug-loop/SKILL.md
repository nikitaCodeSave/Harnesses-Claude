---
name: debug-loop
description: Isolated reproduce-hypothesize-instrument-verify loop for a failing test or unexpected behavior. Use when bug location is unknown. Skip when the bug location is already known and the fix is trivial.
disable-model-invocation: true
context: fork
agent: debug-loop
---

Симптом / failing test от пользователя: $ARGUMENTS.

Цикл (изолированный контекст):
1. Воспроизведи проблему (запусти failing test или симптом).
2. Сформулируй ≤3 гипотезы; ранжируй по вероятности.
3. Для топ-1 — добавь instrumentation (logs / breakpoint / assertion), запусти ещё раз.
4. Подтвердил/опроверг → переходи к следующей гипотезе или к фиксу.
5. Фикс → проверка зелёным test'ом → откат instrumentation.

НЕ предполагай root cause без проверки. НЕ фикси то, что не упало в тесте.
