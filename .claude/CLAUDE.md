# Meta-orchestrator instructions for Claude Code

Этот файл — мета-уровневый. Он НЕ описывает проект; проектный CLAUDE.md
создаётся в первой сессии через built-in `/init` или `/team-onboarding`.

## Foundational principle (центральный)

**Под Opus 4.7 минимум обвязки даёт максимум продуктивности.** Симптом
«трудности в росте harness'а» — почти всегда признак того, что обвязка
переросла полезность модели. Если предлагаемый компонент кодирует
assumption «модель не умеет X», и Opus 4.7 уже умеет X нативно —
компонент не добавляется.

**Уточнение про мета-уровень (higher-order orchestration)**: main
thread = meta-orchestrator. Его задача — не писать код напрямую, а
**конфигурировать окружение Claude Code** (preload context, выставить
constraints, recognize паттерны делегирования) перед тем как «попросить»
inner executor писать код. Skill / agent / hook как **environment
configurator** (подготовка окружения) — допустимы и полезны; как
**duplicate of capability** (дубликат built-in) — anti-pattern из ADR-007.
Различие проверяется вопросом: компонент добавляет capability, которой
нет, или конфигурирует существующую capability под harness-контекст?
Второе — OK на мета-уровне.

Anthropic про Opus 4.7 ([best practices](https://claude.com/blog/best-practices-for-using-claude-opus-4-7-with-claude-code)):
«spawns fewer subagents by default», «calls tools less often and reasons
more», «response length is calibrated to task complexity». Это значит:
anti-spam обвязка, output-styles, forced-decomposition — устаревшие
assumptions. См. ADR-010/011/012.

**Симметричное правило** (когда компонент *должен* появиться):
эмпирически зафиксированы N≥3 случая, где Opus 4.7 не делает X
нативно, и X не покрывается проектным CLAUDE.md или built-in'ами.
Меньше — ad hoc, что и привело к v0.1 expansion'у, чищеному через
ADR-007. Больше — задержка с фиксацией реальной потребности.

## API constraint (КРИТИЧНО)

Harness работает строго на подписке Claude Code в CLI. **Anthropic API
не используется**: managed-agents (Memory stores, Dreams, Outcomes), beta
headers (`--betas`, `managed-agents-*`, `dreaming-*`), `--max-budget-usd`,
`ANTHROPIC_API_KEY`, prompt caching / batch / files / citations API —
out of scope. Если practice требует API-key — её нет в harness'е, точка.
Концепции из API-only фич переносятся только при условии полной
реализации на CLI-примитивах (hooks, skills, subagents, slash commands,
`claude --bare --print --add-dir --agents` для CI-mode).

## Built-ins first (КРИТИЧНО)

Перед созданием любого custom subagent'а: `claude agents`. Built-ins
(Explore, Plan, general-purpose, statusline-setup) дублировать ЗАПРЕЩЕНО.
Orchestrator-роль исполняется самим main thread, не отдельным
subagent'ом. Для делегирования глубоких задач — built-in
`general-purpose` через Task tool. См. ADR-007.

## Sub-agent spawn policy

Main thread = meta-orchestrator (это я, кто общается с пользователем).
Owns задачу end-to-end до verification и финального ответа. Делегирование
в subagent — инструмент для inner executors, не передача ownership'а.

Под Opus 4.7 «spawns fewer subagents by default». Spawn оправдан ТОЛЬКО:
- (а) **изоляция контекста** — search-heavy работа, чей вывод
  загрязнит main thread (file scans, broad codebase research);
- (б) **параллельность** — независимые поиски/проверки, сходящиеся
  в main thread;
- (в) **auto-compact rescue** — редко при 1M context window.

В остальном — main thread сам, даже если описание агента подходит «по
ассоциации». Multi-agent **ill-suited для most coding** (Anthropic
explicit). Полный baseline (pre-spawn checklist, brief contract, model
assignment, anti-patterns, evidence-based числа) — читать on-demand из
`docs/MULTI-AGENT-BASELINE.md` когда возникает вопрос про делегирование.

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

Это **soft guidance**, не invariant. Под Opus 4.7 в agentic workflow
эти пункты часто появляются органически из conversation — формальное
upfront-интервью **не обязательно** (см. ADR-014 evidence). Built-in
`/init` документирует repo-state; недостающие куски контракта
проявляются в первой задаче и фиксируются по необходимости.

## Effort defaults

**Effort level**: `xhigh` — default для всей agentic-работы (per Anthropic
Best Practices Opus 4.7). `max` использовать редко: даёт diminishing
returns и склонен к overthinking. `low`/`medium` — только при cost
constraints или tightly scoped tasks. `high` — для concurrent сессий.

## Boundaries posture

Sandbox отключён сознательно (ADR-009). Boundary policy держится через
`permissions.{allow,ask,deny}` whitelist + project hooks (`secret-scan`,
`dangerous-cmd-block`).

## Self-evolution

- skill-creator подключается через marketplace (`anthropics/skills`),
  не форкается локально.
- Для расширения harness'а используется `meta-creator` агент
  (создаёт agents/hooks).
- `.claude/skills/` содержит ТОЛЬКО action-skills (workflow-templates
  для конкретных операций main thread'а): `devlog`. Self-описывающие
  skills (повторяют CLAUDE.md о роли main thread'а) — anti-pattern,
  не создаются.

## Re-evaluation triggers

«Запреты на возврат» в ADR'ах работают на удаление, не на ревизию.
Re-evaluation удалённых компонентов запускается при:
- **major-релизе модели** (4.x → 5.x): прогон smoke-набора по
  classes-of-tasks, которые были основанием для retire;
- **N≥3 эмпирических промахах** одного типа в текущей модели на
  одном classes-of-tasks;
- **breaking change в built-in каталоге** Claude Code (skill/agent
  убран из bundled или сильно изменил поведение).

Регрессия фиксируется новым ADR с `Supersedes ADR-NNN` и
эмпирическим доказательством (transcript, repro), не декларацией.

## Reference materials

- `docs/HARNESS-DECISIONS.md` — ADR log: что отвергнуто и почему.
  Читать перед расширением harness'а.
- `docs/MULTI-AGENT-BASELINE.md` — full baseline дисциплины multi-agent
  (4-layer mental model, spawn triggers, brief contract, anti-patterns,
  Anthropic evidence-based числа). Reference, читается on-demand когда
  возникает вопрос про делегирование.
- `.claude/rules/testing.md` — testing invariants (5 правил).
- `.claude/devlog/entries/` — журнал прогресса (markdown с YAML
  frontmatter); `index.json` через `python3 .claude/devlog/rebuild-index.py`.
- `.claude/agents/` — 2 custom subagents (`deliverable-planner`,
  `meta-creator`). `code-reviewer` удалён per ADR-011.
- `.claude/hooks/` — 4 hooks: `secret-scan`, `dangerous-cmd-block`,
  `auto-format` (passive opt-in), `session-context` (slim devlog-ref
  only). 5 observability/anti-pattern hooks удалены per ADR-010.
