---
name: review
description: In-session diff review of recent code changes via the code-reviewer subagent. Read-only. Use after writing or modifying non-trivial code. Skip for typo/comment/formatting changes. For deep multi-agent cloud review, run `claude ultrareview` from shell instead.
disable-model-invocation: true
context: fork
agent: code-reviewer
allowed-tools: Bash(git diff:*)
---

Review the current diff. Focus area (optional): $ARGUMENTS.

Workflow:
1. `git diff` сначала; никогда не ревьюй код, который ты не прочитал.
2. Не предлагай рефакторинги вне scope diff'а.
3. Output JSON: `{ "critical": [...], "warnings": [...], "suggestions": [...] }`.

Это in-session local review. Для cloud-hosted multi-agent review (~30 минут, отдельно от сессии) пользователь запускает `claude ultrareview` из shell.
