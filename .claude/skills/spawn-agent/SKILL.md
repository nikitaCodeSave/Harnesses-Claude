---
name: spawn-agent
description: Create a new project-level subagent via meta-creator. Use when a recurring task needs an isolated context or a specialised tool whitelist. Skip when a built-in (Explore, Plan, general-purpose, statusline-setup) covers the need.
disable-model-invocation: true
context: fork
agent: meta-creator
---

Agent name and role от пользователя: $ARGUMENTS.

Workflow для meta-creator:
1. Перед созданием — проверь built-ins через `claude agents`. Если built-in покрывает задачу (Explore, Plan, general-purpose, statusline-setup) — отказать с пояснением.
2. Если задача требует кастомного агента — создай `.claude/agents/<name>.md` с frontmatter:
   - `name`, `description` (action-oriented "use when …" + явное skip-условие)
   - `tools` (whitelist; не "*")
   - `model` (sonnet / opus / haiku / inherit)
3. Body — короткий imperative workflow без воды.

Запрещено: создавать дубликат built-in или существующего custom-агента (deliverable-planner, code-reviewer, debug-loop, onboarding-agent, meta-creator).
