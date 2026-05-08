# Meta-orchestrator instructions for Claude Code

Этот файл — мета-уровневый. Он НЕ описывает проект; проектный CLAUDE.md
создаётся в первой сессии через /onboard.

## Built-ins first (КРИТИЧНО)
Перед созданием любого custom subagent'а: проверить inventory через
`claude agents`. Built-ins (Explore, Plan, general-purpose, statusline-setup)
дублировать ЗАПРЕЩЕНО. Кастомный агент создаётся только когда built-ins
не покрывают задачу.

orchestrator-роль исполняется самим основным потоком сессии (main agent),
не отдельным subagent'ом. Для делегирования глубоких задач из main thread
используется built-in `general-purpose` через Task tool — это инструмент,
не оркестратор.

## Decision tree: command | skill | subagent | hook | nothing
- Новый инвариант проекта? → проектный CLAUDE.md (короткий, императивный)
- Reusable workflow с auto-invoke по контексту? → SKILL
- Explicit user-triggered shortcut? → SKILL с disable-model-invocation
- Token-heavy / context-isolation работа? → SUBAGENT (custom только если
  built-in не подходит)
- Детерминированное safety/observability правило? → HOOK
- Уже покрыто defaults Claude Code? → DO NOTHING

## Anti-patterns
- Не создавать многоступенчатый PM→Architect→Dev→QA pipeline
- Не писать Generator/Evaluator контракт для каждого sprint'а
- Не блокировать writes mid-thought через hooks (block-at-submit, не
  block-at-write)
- Не лить мегарайлзы в CLAUDE.md (контекст-бюджет — public good)

## First-session contract
Перед написанием кода зафиксировать с разработчиком:
- Стек (язык, фреймворк, package manager) — без default'ов
- Project mode (new/mature)
- Acceptance criteria первого deliverable
- Verification механизм (test command, lint, screenshot, manual)
- Sensitive paths/команды для DENY в settings.json
Сохранить в проектном CLAUDE.md (в корне репо, не здесь).
