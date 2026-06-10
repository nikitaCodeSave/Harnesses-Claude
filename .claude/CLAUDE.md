# Meta-orchestrator instructions for Claude Code

Этот файл — мета-уровневый. Он НЕ описывает проект; проектный CLAUDE.md
создаётся в первой сессии через built-in `/init` или `/team-onboarding`.

**Этот репозиторий — лаборатория harness'а, не шаблон.** `.claude/` здесь
содержит R&D-машинерию (`loop/`, `benchmark/`, discovery-критиков), которую
НЕЛЬЗЯ копировать целиком в целевой проект. Каноничное, отгружаемое знание о
дизайне harness'а живёт в глобальном скилле `~/.claude/skills/claude-code-harness/`;
минимальный стартовый harness для нового проекта — его **Bootstrap-режим**, а
не копия этого репо.

## Foundational principle (центральный)

**Под способной моделью минимум обвязки даёт максимум продуктивности**
(re-grounded на Opus 4.8; принцип model-agnostic — не пере-привязывай его
к конкретной версии при апгрейде). Симптом «трудности в росте harness'а» —
почти всегда признак того, что обвязка переросла полезность модели. Если
предлагаемый компонент кодирует assumption «модель не умеет X», а модель
уже умеет X нативно — компонент не добавляется.

**Уточнение про мета-уровень (higher-order orchestration)**: main
thread = meta-orchestrator. Его задача — не писать код напрямую, а
**конфигурировать окружение Claude Code** (preload context, выставить
constraints, recognize паттерны делегирования) перед тем как «попросить»
inner executor писать код. Skill / agent / hook как **environment
configurator** — допустимы; как **duplicate of built-in capability**
или **self-description main thread'а** — anti-pattern.

Когда компонент *должен* появиться: эмпирическое доказательство, что
модель не делает X нативно, X не покрывается проектным CLAUDE.md или
built-in'ами, и потребность повторяется. **Single-incident в invariant
не превращается** — pattern требует multi-source-evidence или
повторяющейся эмпирики.

## API constraint (КРИТИЧНО)

Harness строго на CLI-подписке Claude Code. Anthropic API, managed-agents,
beta headers, `--bare`, `--max-budget-usd` — **out of scope**. Полные
invariants и допустимые переносы концепций — `.claude/rules/api-constraint.md`.

## Built-ins first (КРИТИЧНО)

Перед созданием любого custom subagent'а: `claude agents`. Built-ins
(Explore, Plan, general-purpose, statusline-setup, claude-code-guide)
дублировать ЗАПРЕЩЕНО. Orchestrator-роль исполняется самим main thread,
не отдельным subagent'ом. Для делегирования глубоких задач — built-in
`general-purpose` через Task tool.

## Sub-agent spawn policy

Main thread = meta-orchestrator (это я, кто общается с пользователем).
Owns задачу end-to-end до verification и финального ответа. Делегирование
в subagent — инструмент для inner executors, не передача ownership'а.

Под Opus 4.8 single-agent остаётся дефолтом для most coding (это пережило
переход 4.7→4.8). Spawn subagent'а оправдан ТОЛЬКО:
- (а) **изоляция контекста** — search-heavy работа, чей вывод
  загрязнит main thread (file scans, broad codebase research);
- (б) **параллельность** — независимые поиски/проверки, сходящиеся
  в main thread;
- (в) **auto-compact rescue** — редко при 1M context window.

В остальном — main thread сам, даже если описание агента подходит «по
ассоциации». Single-agent — дефолт для most coding; bounded fan-out
оправдан, когда scope **превышает один контекст** (codebase-scale sweep,
миграция, trust-critical верификация find→refute→converge). Для такого —
**built-in dynamic workflows** (`/workflow`, ключевое слово `ultracode`,
или `/effort ultracode`), НЕ кастомный subagent-pipeline (built-ins-first;
стоит заметно больше токенов — не дефолт). Полный baseline (pre-spawn
checklist, brief contract, model assignment, anti-patterns, evidence-based
числа) — читать on-demand из `.claude/docs/multi-agent.md`.

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

Это **soft guidance**, не invariant. Под Opus 4.8 в agentic workflow
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
  `update-plan-progress` (см. ADR-017). `project-docs-bootstrap`
  ретайрнут (staleness A/B n=2 на Opus 4.8: нет материального лифта над
  native + WORKFLOW.md §3 + docs-discipline — см. devlog + benchmark report).
  Self-описывающие skills (повторяют CLAUDE.md о роли main thread'а)
  — anti-pattern, не создаются.
- Каноничное знание о дизайне harness'а (bootstrap / audit / extend /
  explain) — **глобальный** скилл `~/.claude/skills/claude-code-harness/`
  (re-grounded на Opus 4.8 / CC v2.1.154+). Предыдущий Python-only
  `harness-setup` hard-deleted 2026-06 (overloaded prescriptive preset;
  знание поглощено `claude-code-harness` — см. devlog).

## Reference materials

**Workflow (Plan→Work→Review spine + slice docs)** — читать при работе над фичей:
- `.claude/docs/workflow.md` — тонкий spine (decision tree, routing к slice docs)
- `.claude/docs/builtins-inventory.md` — lab-inventory (2.1.143-era, pending re-ground). Актуальный срез built-ins → `~/.claude/skills/claude-code-harness/references/native-capabilities.md` (v2.1.154+ / Opus 4.8, 5 built-in субагентов, dynamic workflows, effort default `high`)
- `.claude/docs/workflow-async.md` — Monitor tool / Task* / Cron* / SendMessage / `/loop` / Routines reference
- `.claude/docs/workflow-orchestration.md` — worktree / `claude agents` dispatch / session lifecycle / agent-view
- `.claude/docs/workflow-cloud-offload.md` — `/ultraplan` / `/ultrareview` / Routines (cloud-side)
- `.claude/docs/workflow-evolution.md` — measurement-driven harness evolution (AHE/AgentFlow/SLIM-grounded)

**Harness foundation** — читать перед расширением:
- `.claude/docs/principles.md` — harness principles (Anthropic-canonical evidence-based)
- `.claude/docs/harness-architecture.md` — evergreen reference: слои компонентов, context-бюджеты, границы
- `.claude/docs/external-sources.md` — каталог внешних источников (T1-T7 rubric) для research-pass
- `.claude/docs/multi-agent.md` — multi-agent дисциплина, on-demand при делегировании
- `.claude/docs/benchmark.md` — 4-layer benchmark methodology
- `.claude/docs/memory-layers.md` — 5-layer memory reference + curation rituals
- `.claude/docs/archive/decisions-2026Q2.md` — frozen ADR log (для «почему так» вопросов)
- `.claude/docs/archive/workflow-2026-05-10.md` — frozen pre-split workflow doc (empirical baseline)
- `.claude/rules/api-constraint.md` — API/CLI constraint invariants (no Anthropic API).
- `.claude/rules/testing.md` — testing invariants.
- `.claude/rules/docs-discipline.md` — documentation invariants.
- `.claude/skills/update-plan-progress/` — action-skill для progress-журнала multi-session задачи (rule #7 docs-discipline).
- `.claude/devlog/entries/` — recent entries (live); архив `entries/archive/`. Index via `python3 .claude/devlog/rebuild-index.py`.
- `.claude/agents/` — `meta-creator`, `security-reviewer`.
- `.claude/hooks/` — `session-context`, `stop-validation`, `loop-protected-guard`, `cost-warn`.
