# Meta-orchestrator instructions for Claude Code

@../AGENTS.md

Этот файл — мета-уровневый. Он НЕ описывает проект; проектный CLAUDE.md
создаётся в первой сессии через built-in `/init` или `/team-onboarding`.
Операционный слой (команды, границы, неочевидные конвенции) вынесен в корневой
`AGENTS.md` — единственный источник для агентов любого вендора; здесь он
подключён импортом, а не пересказан.

**Этот репозиторий — лаборатория harness'а, не шаблон.** `.claude/` здесь
содержит R&D-машинерию (`benchmark/`, архив `docs/archive/`), которую НЕЛЬЗЯ
копировать целиком в целевой проект. Каноничное, отгружаемое знание о дизайне
harness'а живёт в глобальном скилле `~/.claude/skills/claude-code-harness/`;
минимальный стартовый harness для нового проекта — его **Bootstrap-режим**, а
не копия этого репо.

## Foundational principle

**Под способной моделью минимум обвязки даёт максимум продуктивности**
(model-agnostic; провенанс последнего re-grounding — refresh-ledger в
`harness-evolution.md` кита). Компонент не добавляется, если кодирует
assumption «модель не умеет X», а модель уже умеет X нативно. Порог появления
— повторяющаяся эмпирика или multi-source: **single-incident в invariant не
превращается**.

Main thread = meta-orchestrator: конфигурирует окружение перед тем, как inner
executor напишет код. Skill / agent / hook как environment configurator —
допустимы; как дубль built-in или самоописание main thread'а — anti-pattern.

Развёрнуто: [principles.md](docs/principles.md),
[harness-architecture.md](docs/harness-architecture.md).

## Жёсткие рамки

- **Только CLI-подписка.** Anthropic API, managed-agents, beta headers,
  `--bare`, `--max-budget-usd` — вне scope. Инварианты и допустимые переносы —
  [rules/api-constraint.md](rules/api-constraint.md) (загружен всегда, здесь не
  пересказывается).
- **Built-ins first.** Перед созданием custom subagent'а — сверься с инвентарём
  в `native-capabilities.md` кита (`claude agents` — менеджер фоновых сессий, типы
  он не перечисляет). Built-ins не дублируются; orchestrator-роль — сам main thread.
- **Spawn subagent'а оправдан только** при (а) изоляции контекста, (б)
  параллельности независимых проверок, (в) auto-compact rescue. В остальном —
  main thread сам, даже если описание агента подходит «по ассоциации».
  Scope больше одного контекста → built-in dynamic workflow (`ultracode`), НЕ
  кастомный pipeline. Дисциплина и цифры: [multi-agent.md](docs/multi-agent.md).
- **Независимый judge для silent-wrong класса** (парсеры, guards, инвариантные
  рефакторы). Что измерено (devlog #130, Opus 5): окупается сам **независимый
  свежий контекст** — вендор в том замере не варьировался, оба плеча свои.
  Кросс-вендорный ревьюер (Codex через MCP `codex_peer`, скилл `codex-mcp`) —
  отдельное усиление на другой эмпирике (#127), не подпёртое #130. Не subagent
  и не нарушение api-constraint: сторонний CLI на своей подписке.

## Anti-patterns

- Многоступенчатый PM→Architect→Dev→QA pipeline.
- Generator/Evaluator контракт под каждый sprint.
- Блокировка writes mid-thought хуками (block-at-submit, не block-at-write).
- Мегарайлзы в CLAUDE.md: контекст-бюджет — public good, а правило, которое
  устарело, ограничивает решения сильнее, чем помогает.

## First-session contract

<important if="this harness applied to a new project repo without project CLAUDE.md">
До кода зафиксировать с разработчиком: стек · project mode (new/mature) ·
acceptance criteria первого deliverable · механизм верификации · sensitive
paths для DENY. Сохранить в проектном CLAUDE.md (в корне репо, не здесь).

Это **soft guidance**, не invariant: под способной моделью пункты часто
появляются из разговора, формальное upfront-интервью не обязательно. Built-in
`/init` документирует repo-state; недостающее проявится в первой задаче.
</important>

## Self-evolution

- Расширение harness'а (agents/hooks/commands) main thread делает нативно;
  skills — через плагин skill-creator из marketplace, не форком.
- Проектных skills нет — каталога `.claude/skills/` в репо не существует.
  Devlog едет плагином `devlog@skills-dir`; в репо ничего devlog'ового не
  дублируется. Self-описывающие skills не создаются; action-skill появляется
  только под повторяющуюся операцию, которой нет built-in'а.
- Каноничное знание о дизайне harness'а — глобальный скилл
  `claude-code-harness` (он же плагин `~/PROJECTS/claude-code-harness`).

## Reference materials

**Workflow** — при работе над фичей:
- [workflow.md](docs/workflow.md) — тонкий spine, routing к slice docs
  ([async](docs/workflow-async.md) · [orchestration](docs/workflow-orchestration.md)
  · [cloud-offload](docs/workflow-cloud-offload.md) · [evolution](docs/workflow-evolution.md)).
- Built-ins current-срез — **единственный** canonical источник:
  `~/.claude/skills/claude-code-harness/references/native-capabilities.md`. Это
  единственный файл харнеса, пиннящийся к версии CC и поколению моделей; все
  остальные доки version-free и ссылаются сюда.

**Foundation** — перед расширением: [principles.md](docs/principles.md) ·
[harness-architecture.md](docs/harness-architecture.md) ·
[multi-agent.md](docs/multi-agent.md) · [benchmark.md](docs/benchmark.md) ·
[memory-layers.md](docs/memory-layers.md) ·
[external-sources.md](docs/external-sources.md) (каталог T1-T7).

**Инварианты** (загружены всегда): [testing](rules/testing.md) ·
[docs-discipline](rules/docs-discipline.md) · [api-constraint](rules/api-constraint.md).

**История и провенанс:** `.claude/devlog/entries/` (индекс — `devlog-reindex`) ·
`docs/archive/` (frozen: ADR-лог, pre-split workflow) · `.claude/audits/` ·
`.claude/benchmark/` (в т.ч. `guard-ab/` — A/B ваниль vs harness vs §8).

Каталогов `.claude/agents/` и `.claude/hooks/` нет: custom-агентов harness не
держит (audit-роли едут плагином), проектных хуков тоже — активны глобальный
SessionStart-дайджест из плагина `devlog`. Глобального `system-guard` тоже больше нет —
ретайрен 2026-08-29 в пользу нативного слоя (auto-mode классификатор + встроенный блок
деструктивных git/IaC); devlog #134.
