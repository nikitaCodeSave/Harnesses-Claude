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
configurator** — допустимы; как **duplicate of built-in capability**
или **self-description main thread'а** — anti-pattern.

Когда компонент *должен* появиться: эмпирическое доказательство, что
Opus 4.7 не делает X нативно, X не покрывается проектным CLAUDE.md или
built-in'ами, и потребность повторяется. **Single-incident в invariant
не превращается** — pattern требует multi-source-evidence или
повторяющейся эмпирики.

## API constraint (КРИТИЧНО)

Harness работает строго на подписке Claude Code в CLI. **Anthropic API
не используется**: managed-agents (Memory stores, Dreams, Outcomes), beta
headers (`--betas`, `managed-agents-*`, `dreaming-*`), `--max-budget-usd`,
`ANTHROPIC_API_KEY`, prompt caching / batch / files / citations API —
out of scope. Если practice требует API-key — её нет в harness'е, точка.
Концепции из API-only фич переносятся только при условии полной
реализации на CLI-примитивах (hooks, skills, subagents, slash commands,
`claude --print --add-dir --agents` для headless CI на OAuth-подписке).
`--bare` strictly требует `ANTHROPIC_API_KEY` (per `claude --help`) —
out of scope.

## Built-ins first (КРИТИЧНО)

Перед созданием любого custom subagent'а: `claude agents`. Built-ins
(Explore, Plan, general-purpose, statusline-setup) дублировать ЗАПРЕЩЕНО.
Orchestrator-роль исполняется самим main thread, не отдельным
subagent'ом. Для делегирования глубоких задач — built-in
`general-purpose` через Task tool.

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
`.claude/docs/multi-agent.md` когда возникает вопрос про делегирование.

## Anti-patterns

- Не создавать многоступенчатый PM→Architect→Dev→QA pipeline
- Не писать Generator/Evaluator контракт для каждого sprint'а
- Не блокировать writes mid-thought через hooks (block-at-submit, не
  block-at-write)
- Не лить мегарайлзы в CLAUDE.md (контекст-бюджет — public good)

## First-session contract

<important if="this harness applied to a new project repo without project CLAUDE.md">
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
</important>

## Self-evolution

- skill-creator подключается через marketplace (`anthropics/skills`),
  не форкается локально.
- Для расширения harness'а используется `meta-creator` агент
  (создаёт agents/hooks).
- `.claude/skills/` содержит ТОЛЬКО action-skills (workflow-templates
  для конкретных операций main thread'а): `devlog`,
  `project-docs-bootstrap` (см. ADR-017). Self-описывающие skills
  (повторяют CLAUDE.md о роли main thread'а) — anti-pattern,
  не создаются.

## Reference materials

- `.claude/docs/workflow.md` — **canonical Plan→Work→Review development workflow** (Anthropic + Boris Cherny baseline). Читать при работе над фичей.
- `.claude/docs/principles.md` — harness principles (Anthropic-canonical evidence-based). Читать перед расширением harness'а.
- `.claude/docs/archive/decisions-2026Q2.md` — full historical ADR log (frozen 2026-05-10), для контекстуальных «почему так» вопросов.
- `.claude/docs/multi-agent.md` — multi-agent дисциплина, on-demand при делегировании.
- `.claude/docs/benchmark.md` — 3-tier benchmark methodology.
- `.claude/rules/testing.md` — testing invariants.
- `.claude/rules/docs-discipline.md` — documentation invariants.
- `.claude/skills/project-docs-bootstrap/` — action-skill для bootstrap canonical project docs.
- `.claude/devlog/entries/` — recent entries (live); архив `entries/archive/`. Index via `python3 .claude/devlog/rebuild-index.py`.
- `.claude/agents/` — `deliverable-planner`, `meta-creator`.
- `.claude/hooks/` — `secret-scan`, `dangerous-cmd-block`, `auto-format`, `session-context`.
