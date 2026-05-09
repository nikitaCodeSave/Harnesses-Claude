---
name: create-skill
description: Create a new project-level skill via meta-creator. Delegates to the canonical skill-creator from anthropics/skills marketplace if installed; otherwise meta-creator drafts SKILL.md directly. Use when a recurring procedure deserves a reusable skill.
disable-model-invocation: true
context: fork
agent: meta-creator
---

Skill name and intent от пользователя: $ARGUMENTS.

Workflow для meta-creator:
1. Проверь, установлен ли `skill-creator` из marketplace anthropics/skills:
   `claude plugin list 2>/dev/null | grep -i skill-creator || echo "not-installed"`
2. Если установлен — делегируй ему через invocation `/skill-creator $ARGUMENTS`.
3. Если не установлен — напиши `.claude/skills/<name>/SKILL.md` напрямую с минимальным frontmatter (`name`, `description`) и телом-инструкцией. Не форкай canonical skill-creator локально.

Запрещено: создавать skill, дублирующий built-in commands (/init, /review, /security-review, /simplify, /loop) или встроенные skills harness'а (devlog, onboard, plan-deliverable, review, debug-loop, create-skill, spawn-agent, refactor).
