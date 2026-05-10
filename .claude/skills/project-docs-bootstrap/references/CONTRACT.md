# Project Documentation Contract

Per-doc charter и опорные skeletons для skill `project-docs-bootstrap`. Этот файл — **reference**, читается on-demand в Phase 3 (generate). Не auto-loaded в системный prompt.

---

## 1. Canonical layout

```
<project-root>/
├── CLAUDE.md                  # meta-entry: стек, hard rules, ссылки на docs/
├── README.md                  # human-first; Claude тоже читает
├── AGENTS.md                  # (опц.) symlink → CLAUDE.md для cross-tool (Cursor/Copilot)
├── docs/
│   ├── ARCHITECTURE.md        # System map: компоненты, data flow, deployment
│   ├── CODE-MAP.md            # Top-level dir annotations + entry points
│   ├── GLOSSARY.md            # Domain language: акронимы, бизнес-термины
│   ├── CONVENTIONS.md         # Team-specific divergence от industry default
│   ├── ROADMAP.md             # Active initiatives, не backlog
│   ├── ADR/                   # Architectural Decision Records (append-only)
│   │   └── 0001-*.md
│   └── RUNBOOKS/              # Tested операционные процедуры
│       └── deploy.md
└── .github/
    └── pull_request_template.md  # doc-check checklist
```

---

## 2. Per-doc charter

### `CLAUDE.md` (root)
- **Назначение**: meta-entry point. Стек, hard rules, sensitive paths, ссылки на остальные docs.
- **Update trigger**: смена стека / новая convention / новая sensitive cmd / появление нового doc'а в `docs/`.
- **Authority**: dev + Claude (с approval).
- **Размер**: ≤ 200 строк. Длиннее — split в paths-scoped rules.
- **Drift detection**: quarterly review; cold-start test.

### `docs/ARCHITECTURE.md`
- **Назначение**: system map — компоненты, data flow, external services, deployment topology.
- **Update trigger**: новый/удалённый сервис, integration change, major refactor.
- **Authority**: architect / senior dev; Claude — draft.
- **Drift detection**: PR template требует update; reviewer enforce.

### `docs/CODE-MAP.md`
- **Назначение**: top-level dir annotations, entry points, where-is-X таблица.
- **Update trigger**: новый top-level dir, удаление, major reorg.
- **Authority**: anyone via PR.
- **Drift detection**: linter (agnix-style) на orphan paths; quarterly grep на удалённые dirs.

### `docs/GLOSSARY.md`
- **Назначение**: domain language — акронимы, бизнес-термины, ubiquitous language.
- **Update trigger**: первое появление термина в коде / docs / commit message.
- **Authority**: domain expert.
- **Drift detection**: grep на необъяснённые акронимы в коде.

### `docs/CONVENTIONS.md`
- **Назначение**: team-specific patterns — **где команда расходится с industry default**.
- **Не пишем**: «мы следуем PEP 8» = useless. Пишем только divergences.
- **Update trigger**: code review нашёл convention divergence третий раз.
- **Authority**: team consensus.
- **Drift detection**: linter rules где возможно.

### `docs/ROADMAP.md`
- **Назначение**: active initiatives — что делаем, owner, deadline, blockers.
- **Не пишем**: backlog (это в issue tracker), идеи без owner.
- **Update trigger**: смена приоритетов, завершение initiative.
- **Authority**: PM / lead.
- **Drift detection**: quarterly refresh; deleted-not-archived items вызывают вопрос.

### `docs/ADR/<N>-<slug>.md`
- **Назначение**: архитектурное решение — Context / Decision / Consequences / Alternatives.
- **Update trigger**: non-trivial решение (выбор lib, layout, protocol, отказ от refactor).
- **Authority**: decider.
- **Discipline**: **append-only**. Superseded ADR помечаются `status: superseded by ADR-NNN`, не удаляются.

### `docs/RUNBOOKS/<procedure>.md`
- **Назначение**: tested операционная процедура.
- **Update trigger**: каждое выполнение, расходящееся с doc.
- **Frontmatter**: `last-tested-on: <YYYY-MM-DD>`, `tested-by: @<handle>`.
- **Drift detection**: pre-deploy ритуал «runbook current?».

---

## 3. Skeletons (опорные структуры)

### `docs/ARCHITECTURE.md`

```markdown
---
owner: "@<handle>"
last-updated: <YYYY-MM-DD>
status: active
---

# Architecture

## Overview
<1 параграф: что это система делает, для кого>

## Components
| Component | Purpose | Tech | Owner |
|---|---|---|---|
| ... | ... | ... | @... |

## Data flow
<sequence или ASCII-схема: request → ... → response>

## External services
| Service | Purpose | Failure mode |
|---|---|---|
| ... | ... | ... |

## Deployment
<где живёт, как deploy'ится, environment matrix>

## Constraints
<нефункциональные: latency, throughput, compliance, etc.>
```

### `docs/CODE-MAP.md`

```markdown
---
owner: "@<handle>"
last-updated: <YYYY-MM-DD>
status: active
---

# Code Map

## Top-level layout

| Path | Purpose | Entry point |
|---|---|---|
| `src/api/` | HTTP handlers | `src/api/main.py:app` |
| `src/core/` | Business logic | — |
| `tests/` | All tests | `pytest` |

## Where to find X

| Concern | Location |
|---|---|
| Auth | `src/api/auth/` |
| DB models | `src/core/models/` |
| Config | `src/config.py` |
```

### `docs/GLOSSARY.md`

```markdown
---
owner: "@<handle>"
last-updated: <YYYY-MM-DD>
status: active
---

# Glossary

| Term | Definition | First seen |
|---|---|---|
| **TBD** | Term to be defined | — |

<Каждый акроним / domain-термин на одной строке. Definition в одном предложении. First seen — путь к первому использованию.>
```

### `docs/CONVENTIONS.md`

```markdown
---
owner: "@<handle>"
last-updated: <YYYY-MM-DD>
status: active
---

# Conventions (team-specific divergences)

> Generic best practices (PEP 8, Airbnb style) — НЕ описываются. Только то, где команда расходится.

## <Тема>
- **Default**: <industry standard>
- **Наш выбор**: <что делаем>
- **Почему**: <причина>
- **Enforcement**: <linter rule / review checklist>
```

### `docs/ADR/0001-<slug>.md`

```markdown
---
id: 1
date: <YYYY-MM-DD>
status: active
deciders: ["@<handle>"]
---

# ADR-0001: <Decision title>

## Context
<Что заставило принять решение. 2-4 предложения.>

## Decision
<Что выбрано. Императивно: «Используем X».>

## Consequences
- **Pros**: ...
- **Cons**: ...
- **Constraints introduced**: ...

## Alternatives considered
- **Option A**: <что и почему отвергнут>
- **Option B**: ...
```

### `docs/RUNBOOKS/<procedure>.md`

```markdown
---
owner: "@<handle>"
last-updated: <YYYY-MM-DD>
last-tested-on: <YYYY-MM-DD>
tested-by: "@<handle>"
status: active
---

# <Procedure name>

## When to use
<Trigger conditions.>

## Prerequisites
- <access / state / tool>

## Steps
1. <command или action>
2. ...

## Verification
<Как убедиться, что отработало.>

## Rollback
<Как откатить, если что-то пошло не так.>

## Failure modes
| Symptom | Cause | Fix |
|---|---|---|
| ... | ... | ... |
```

---

## 4. PR template (proposed для команд ≥2 dev'ов)

`.github/pull_request_template.md`:

```markdown
## Summary
<что и почему>

## Checklist
- [ ] Code changes
- [ ] Tests added/updated (см. `.claude/rules/testing.md`)
- [ ] Docs updated если применимо:
  - [ ] ARCHITECTURE.md (структурное изменение)
  - [ ] CODE-MAP.md (новый/удалённый top-level dir)
  - [ ] GLOSSARY.md (новый domain-термин)
  - [ ] CONVENTIONS.md (новый team pattern)
- [ ] ADR added если architectural decision
- [ ] Runbook updated/created если ops procedure changed
```

---

## 5. Sequencing (рекомендованный порядок bootstrap)

1. `docs/ARCHITECTURE.md` — даёт контекст для всего остального.
2. `docs/CODE-MAP.md` — навигация по коду.
3. `docs/GLOSSARY.md` — если найдены domain-термины при audit.
4. Проектный `CLAUDE.md` — обновляется ссылками на (1)-(3).
5. `docs/ADR/0001-*.md` — retroactive первое решение (опц., для mature проектов).
6. `docs/CONVENTIONS.md` — если есть divergent patterns (опц.).
7. `docs/ROADMAP.md` — если есть active initiatives (опц.).
8. `docs/RUNBOOKS/` — по запросу.
9. `.github/pull_request_template.md` — если команда ≥2 dev'ов.

---

## 6. Multi-stack / monorepo

Если проект multi-stack (Python backend + TS frontend):
- Один `docs/ARCHITECTURE.md` на проект (общая картина).
- Один `docs/CODE-MAP.md` (выделить subdirs per stack).
- `.claude/rules/<stack>.md` с `paths:` frontmatter — стек-specific invariants. Пример:
  ```yaml
  ---
  paths: ['backend/**']
  ---
  # Python backend invariants
  ...
  ```
- Один `docs/GLOSSARY.md` (domain един).
- Отдельные `docs/CONVENTIONS-<stack>.md` если convention diverges.

См. paths-scoped rules: Claude Code 2.0.64+ нативно поддерживает; bug #16853 (subdirectory rules могут не подгружаться) — мониторить.

---

## 7. Связь с harness

- `.claude/rules/docs-discipline.md` — always-loaded ongoing rules (6 invariants).
- `.claude/skills/devlog/` — после bootstrap создать devlog entry с tag `docs`.
- `.claude/docs/principles.md` ADR-017 — обоснование добавления skill + rule в harness.
