# Meta-orchestrator instructions for Claude Code

@../AGENTS.md

Этот файл — мета-уровневый. Он НЕ описывает проект; проектный CLAUDE.md
создаётся в первой сессии через built-in `/init` или `/team-onboarding`.
Операционный слой (команды, границы, неочевидные конвенции) вынесен в корневой
`AGENTS.md` — единственный источник для агентов любого вендора; здесь он
подключён импортом, а не пересказан.

**Этот репозиторий — лаборатория harness'а, не шаблон.** `.claude/` здесь
содержит R&D-машинерию (`benchmark/`, архив `docs/archive/`), которую НЕЛЬЗЯ
копировать целиком в целевой проект. Исследование и замеры живут здесь
(`.claude/docs/`, `benchmark/`); в проекты едет только измеренный минимум —
плагин `harness` из `~/PROJECTS/claude-code-harness` (скилл установки, команды потока `/harness:*` и три шаблона,
фраза «set up Claude Code harness in this project»), а не копия этого репо.

## Foundational principle

**Под способной моделью минимум обвязки даёт максимум продуктивности**
(model-agnostic). Компонент не добавляется, если кодирует
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
  в `native-capabilities.md` (`claude agents` — менеджер фоновых сессий, типы
  он не перечисляет). Built-ins не дублируются; orchestrator-роль — сам main thread.
- **Spawn subagent'а оправдан только** при (а) изоляции шумного вывода
  (широкий скан, логи), (б) параллельности независимых задач, (в) независимом
  ревью свежим контекстом. Защита контекстного окна сама по себе — не основание
  (best-practices, «What you can stop doing»). В остальном — main thread сам,
  даже если описание агента подходит «по ассоциации».
  Scope больше одного контекста → built-in dynamic workflow (`ultracode`), НЕ
  кастомный pipeline. Дисциплина и цифры: [multi-agent.md](docs/multi-agent.md).
- **Независимый judge для silent-wrong класса** (парсеры, guards, инвариантные
  рефакторы): окупается сам **независимый свежий контекст** (замер —
  `benchmark/guard-ab/RESULTS.md`). Кросс-вендорный ревьюер (Codex CLI через Bash) —
  отдельное усиление; его находки воспроизводятся тестом до фикса. Не subagent
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
  Self-описывающие skills не создаются; action-skill появляется только под
  повторяющуюся операцию, которой нет built-in'а.
- Решение, которому должна следовать будущая работа, — ADR в `docs/adr/`;
  журнала сессий нет ([ADR 0001](docs/adr/0001-devlog-zakryt-resheniya-v-adr.md)).
- Знание о дизайне harness'а — здесь, в `.claude/docs/`; вывод из замера
  попадает в проекты только через плагин `harness` (`~/PROJECTS/claude-code-harness`),
  и только когда у строки шаблона есть названное основание: замер, first-party источник,
  опубликованное исследование или устоявшаяся практика (рубрика — `external-sources.md`, блок 10;
  [ADR 0008](docs/adr/0008-osnovanie-stroki-nazvannyy-istochnik.md)).

## Reference materials

**Workflow** — при работе над фичей:
- [workflow.md](docs/workflow.md) — тонкий spine, routing к slice docs
  ([async](docs/workflow-async.md) · [orchestration](docs/workflow-orchestration.md)
  · [cloud-offload](docs/workflow-cloud-offload.md) · [evolution](docs/workflow-evolution.md)).
- Built-ins current-срез — **единственный** canonical источник:
  `.claude/docs/native-capabilities.md`. Это
  единственный файл харнеса, пиннящийся к версии CC и поколению моделей; все
  остальные доки version-free и ссылаются сюда.

**Foundation** — перед расширением: [principles.md](docs/principles.md) ·
[harness-architecture.md](docs/harness-architecture.md) ·
[multi-agent.md](docs/multi-agent.md) · [benchmark.md](docs/benchmark.md) ·
[memory-layers.md](docs/memory-layers.md) ·
[external-sources.md](docs/external-sources.md) (каталог T1-T7).

**Инварианты** (загружены всегда): [testing](rules/testing.md) ·
[docs-discipline](rules/docs-discipline.md) · [api-constraint](rules/api-constraint.md).

**Записи, не инструкции** (история и провенанс): git · `docs/adr/` (действующие решения) ·
`.claude/benchmark/*/RESULTS.md` (замеры) · `docs/native-capabilities.md` (единственный файл с
версиями) · аудиты `.claude/audits/<slug>/` (записанные не правятся) · архивы `.claude/devlog/`, `docs/archive/` (frozen).

Каталогов `.claude/agents/` и `.claude/hooks/` нет: ни custom-агентов, ни своих хуков — ни в
проекте, ни глобально. Опасные команды закрывает нативный слой: auto-mode классификатор и
встроенный блок деструктивных git/IaC.
