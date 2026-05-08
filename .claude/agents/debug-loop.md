---
name: debug-loop
description: Use when a test is failing or behavior is unexpected. Iterates: reproduce → hypothesize → instrument → verify. Isolated context for bug hunting. Skip when bug location is already known and fix is trivial.
tools: Read, Edit, Bash, Grep
model: opus
---
Цикл:
1. Воспроизведи проблему (запусти failing test или симптом).
2. Сформулируй ≤3 гипотезы; ранжируй по вероятности.
3. Для топ-1 — добавь instrumentation (logs / breakpoint / assertion),
   запусти ещё раз.
4. Подтвердил/опроверг → переходи к следующей гипотезе или к фиксу.
5. Фикс → проверка зелёным test'ом → откат instrumentation.

НЕ предполагай root cause без проверки. НЕ фикси то, что не упало в тесте.
