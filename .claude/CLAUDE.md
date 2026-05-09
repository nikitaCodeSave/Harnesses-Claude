# Meta-orchestrator instructions for Claude Code

Этот файл — мета-уровневый. Он НЕ описывает проект; проектный CLAUDE.md
создаётся в первой сессии через /onboard.

## API constraint (КРИТИЧНО)
Harness работает строго на подписке Claude Code в CLI. **Anthropic API
не используется**: managed-agents (Memory stores, Dreams, Outcomes), beta
headers (`--betas`, `managed-agents-*`, `dreaming-*`), `--max-budget-usd`,
`ANTHROPIC_API_KEY`, prompt caching / batch / files / citations API —
out of scope. Если practice требует API-key — её нет в harness'е, точка.
Концепции из API-only фич можно переносить только при условии полной
реализации на CLI-примитивах (hooks, skills, subagents, slash commands,
`claude --bare --print --add-dir --agents` для CI-mode).

`claude --bare` — легитимный CI-mode флаг (sets `CLAUDE_CODE_SIMPLE`,
skips auto-discovery), НЕ ломает OAuth. Используется в `.claude/scripts/`
для headless review/check workflows.

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

## Foundational principle
**Под Opus 4.7 минимум обвязки даёт максимум продуктивности.** Симптом
«трудности в росте harness'а» — почти всегда признак того, что обвязка
переросла полезность модели. Если предлагаемый компонент кодирует
assumption «модель не умеет X», и Opus 4.7 уже умеет X нативно —
компонент не добавляется.

## Self-evolution
- skill-creator не форкается локально. Подключается через marketplace:
  `claude plugin marketplace add anthropics/skills`,
  `claude plugin install skill-creator@anthropics-skills` — на user-level
  (`~/.claude/`), не project-level.
- Для расширения harness'а используется `meta-creator` агент (создаёт
  agents/hooks) и canonical skill-creator (создаёт skills).
- Каталог `.claude/skills/` содержит project-level skills (devlog, onboard,
  plan-deliverable, review, debug-loop, refactor, create-skill, spawn-agent).
  Все user-triggered shortcut'ы помечены `disable-model-invocation: true`.

## Reference materials
- `docs/HARNESS-DECISIONS.md` — ADR log: что отвергнуто и почему.
  Читать перед любым расширением harness'а.
- `docs/Harnesses_gude.md` — research-документ v0.2 (P0 patches applied
  2026-05-09); `docs/RESEARCH-PATCHES.md` — лог патчей P1/P2/P3, ещё
  не применённых.
- `.claude/rules/testing.md` — testing invariants (5 правил), читать
  перед написанием кода с тестами.
- `.claude/devlog/entries/` — журнал прогресса (markdown с YAML
  frontmatter); `index.json` регенерируется через
  `python3 .claude/devlog/rebuild-index.py`.
- `.claude/agents/` — 5 custom subagents (deliverable-planner,
  code-reviewer, debug-loop, onboarding-agent, meta-creator).
- `.claude/hooks/` — safety + observability layer; smoke-tested.
