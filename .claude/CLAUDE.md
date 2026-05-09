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

## Effort & sandbox defaults
- **Effort level**: `xhigh` — default для всей agentic-работы (per Anthropic
  Best Practices Opus 4.7). `max` использовать редко: даёт diminishing
  returns и склонен к overthinking. `low`/`medium` — только при cost
  constraints или tightly scoped tasks. `high` — для concurrent сессий.
- **Sandbox**: включён в `.claude/settings.json` (`sandbox.enabled: true`,
  `autoAllowBashIfSandboxed: true`). Per Anthropic — sandboxing «safely
  reduces permission prompts by 84%». Bash-команды в sandbox auto-allow,
  filesystem read-deny на секреты (`~/.aws`, `~/.ssh`, etc.), network
  allowlist на стандартные dev domains. Deny-rules из `permissions.deny`
  остаются как defense-in-depth.

## Foundational principle
**Под Opus 4.7 минимум обвязки даёт максимум продуктивности.** Симптом
«трудности в росте harness'а» — почти всегда признак того, что обвязка
переросла полезность модели. Если предлагаемый компонент кодирует
assumption «модель не умеет X», и Opus 4.7 уже умеет X нативно —
компонент не добавляется.

## Built-in onboarding & quality flow (используем, не дублируем)

Harness целенаправленно НЕ имеет собственных onboard/review/debug skills —
они дублировали бы built-ins (см. ADR-007).

| Сценарий | Built-in / bundled |
|---|---|
| Bootstrap CLAUDE.md в новом репо | `/init` (built-in skill) |
| Доработать существующий CLAUDE.md | `/memory` |
| Ramp-up нового teammate в зрелом репо | `/team-onboarding` (v2.1.101+) |
| Diff-review последних изменений | `/review` (built-in) |
| Глубокий security-review | `/security-review` |
| Отладка нетривиального бага | `/debug` (bundled skill) |
| Quality+efficiency cleanup | `/simplify` (bundled) |
| Cloud-hosted multi-agent review | shell `claude ultrareview` |
| Plan-mode для нетривиального дизайна | `/plan` или Shift+Tab×2 |

Если язык общения важен — он подхватывается из языка первого запроса
пользователя (Opus 4.7 нативно). При желании зафиксировать durably —
строкой `Working language: <язык>` в проектном `CLAUDE.md`.

## Self-evolution
- skill-creator не форкается локально. Подключается через marketplace:
  `claude plugin marketplace add anthropics/skills`,
  `claude plugin install skill-creator@anthropics-skills` — на user-level
  (`~/.claude/`), не project-level.
- Для расширения harness'а используется `meta-creator` агент (создаёт
  agents/hooks) и canonical skill-creator (создаёт skills через
  marketplace).
- Каталог `.claude/skills/` содержит ТОЛЬКО уникальное, не покрытое
  built-ins: `devlog` (наш schema + index), `plan-deliverable`
  (deliverable-driven contract без декомпозиции). Всё остальное — через
  built-ins выше.

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
- `.claude/agents/` — 3 custom subagents (deliverable-planner,
  code-reviewer, meta-creator). onboarding-agent и debug-loop удалены
  per ADR-007 как дубликаты built-ins (`/init`+`/team-onboarding` и
  `/debug` соответственно).
- `.claude/hooks/` — safety + observability layer; smoke-tested.
