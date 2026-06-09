---
owner: @nikitaCodeSave
last-updated: 2026-05-14
status: snapshot
---

# Component audit — 2026-05-14

Point-in-time snapshot harness'а с применением рамки из
`harness-architecture.md`. Это не evergreen — описывает state на дату
выше. Следующий snapshot создаётся при значимой смене состояния
(новый компонент, retirement, structural migration).

## Метод

Каждый компонент классифицирован по:
- **Layer** (1-6, см. evergreen рамку): always-on / session-start /
  event-triggered / content-triggered / invocation-triggered / on-demand.
- **Boundary**: trust / info / containment. Один компонент может закрывать
  несколько.
- **Budget impact**: token (T) / time (Tm) / ops-complexity (O). Шкала
  low/med/high относительно остальных компонентов harness'а.
- **Universality**: универсален (подходит для basic-module) или
  project-specific (только для этого репо).
- **Retire trigger**: что — наблюдаемое — отметит, что компонент перестал
  окупаться.

## Inventory

### Layer 1 — Always-on (CLAUDE.md + rules)

| Component | Lines | Boundary | Budget (T/Tm/O) | Universal | Notes |
|---|---|---|---|---|---|
| `.claude/CLAUDE.md` | 114 | info | high / — / med | ✅ | Meta-orchestrator policy. Под 200-line cap. |
| `rules/api-constraint.md` | 30 | info | low / — / low | ✅ | CLI-only invariant. Harness-specific (но переносим в любой harness через CLI-subscription). |
| `rules/docs-discipline.md` | 50 | info | low / — / low | ✅ | 7 doc invariants. |
| `rules/testing.md` | 25 | info | low / — / low | ✅ | 5 test invariants. |

**Sub-total token cost layer 1**: ~7.5K tokens (CLAUDE.md ~3K + rules ~4.5K) — каждый turn.

### Layer 2 — Session-start hooks

| Component | Boundary | Budget (T/Tm/O) | Universal | Notes |
|---|---|---|---|---|
| `hooks/session-context.sh` | info | low / low / low | ✅ | Inject last devlog entry + loop STATE summary + active progress journal pointer. Loop STATE-секция — project-specific, нужно extract при basic-module. |

### Layer 3 — Event-triggered hooks

| Component | Event | Boundary | Budget (T/Tm/O) | Universal | Activation |
|---|---|---|---|---|---|
| `hooks/loop-protected-guard.sh` | `PreToolUse` Edit\|Write\|MultiEdit | trust | — / low / low | ❌ project-specific | Только когда `LOOP_MODE=1`. Защищает protected files в self-improvement loop. |
| `hooks/stop-validation.sh` | `Stop` | info (advisory) | — / med / med | ✅ | Phantom-completion check: pytest/ruff/mypy/eslint/tsc + regression test-count drop. Universal для Python/JS. |
| `hooks/discovery-gate.sh` | `Stop` | info (advisory) | — / low / low | ⚠️ opt-in | Pre-`/critique` reminder. Активен только под `EVALUATOR_GATE_ACTIVE=1` или `.claude/.evaluator-active` marker. |
| `hooks/cost-warn.sh` | `UserPromptSubmit` (планировался) | info | — / — / low | ❌ orphan | **НЕ подключен в `settings.json`** — кандидат на retire (см. ниже). |

### Layer 4 — Content-triggered (skills)

| Component | Boundary | Budget (T/Tm/O) | Universal | Notes |
|---|---|---|---|---|
| `skills/devlog/SKILL.md` | info | — / — / low | ✅ | Workflow-template для создания devlog entry. |
| `skills/project-docs-bootstrap/SKILL.md` | info | — / — / low | ✅ | Bootstrap canonical project docs layout. One-shot per project. |

### Layer 5 — Invocation-triggered (agents + commands)

| Component | Trigger | Boundary | Budget (T/Tm/O) | Universal | Notes |
|---|---|---|---|---|---|
| `commands/critique.md` | `/critique` slash | info + containment | med / high / med | ✅ | Evaluator workflow — spawns `discovery-critic` + parses CRITIC.json. Heavy doc (~290 lines). |
| `commands/loop-status.md` | `/loop-status` slash | info | low / low / low | ❌ project-specific | Reporter для self-improvement loop. |
| `agents/discovery-critic.md` | Spawn via Task | containment + trust + info | med / high / med | ✅ | Fresh-context Evaluator. Heavy frontmatter + schema enforcement (~250 lines). |
| `agents/security-reviewer.md` | Spawn via Task | containment + info | low / med / low | ✅ | Diff-level security review. |
| `agents/meta-creator.md` | Spawn via Task | containment | low / low / low | ⚠️ trivial | Workflow тривиален (16 lines body). См. retire-кандидат ниже. |

### Layer 6 — On-demand reference (docs)

| Component | Lines | Universal | Notes |
|---|---|---|---|
| `docs/principles.md` | 130 | ✅ | Active principles. **STALE inventory** (lines 19-26) — см. doc-drift finding. |
| `docs/workflow.md` | n/a | ✅ | Plan→Work→Review canonical baseline. |
| `docs/multi-agent.md` | n/a | ✅ | Subagent дисциплина. |
| `docs/benchmark.md` | n/a | ⚠️ harness-specific | 3-tier methodology, привязан к self-improvement loop. |
| `docs/memory-layers.md` | 54 | ✅ | 5-layer memory reference. |
| `docs/external-sources.md` | n/a | ✅ | Каталог внешних источников. |
| `docs/harness-architecture.md` | 250 | ✅ | **Создан 2026-05-14** — evergreen рамка (этот audit её применяет). |
| `docs/retrospective-2026-05-12-builtins-and-memory.md` | n/a | ❌ point-in-time | Кандидат на archive (см. ниже). |
| `docs/archive/decisions-2026Q2.md` | n/a | ❌ frozen | Historical ADR log. |

### Top-level подкаталоги (контекст)

| Dir | Назначение | Universal | Notes |
|---|---|---|---|
| `benchmark/` | Fixtures + reports для 3-tier benchmark methodology | ❌ project-specific | Self-improvement evaluation infrastructure. |
| `loop/` | Self-improvement loop scaffolding (Ralph-loop pattern) | ❌ project-specific | STATE.md / journal.md / backlog.md / proposals/. |
| `progress/` | Active progress journals для long-running tasks | ⚠️ runtime | Создаётся per task per docs-discipline rule 7. |
| `memory/` | JSONL logs (`secret-scan.jsonl`, `stop-validation.jsonl`, и др.) | ⚠️ runtime | Создаётся hooks. |
| `output-styles/` | (пусто) | ❌ retire | Пустая директория, не несёт content. Удалить или оставить как scaffolding на будущее (low ops cost). |
| `plans/` | 2 stale draft plans (2026-05-08/09) | ⚠️ stale | Auto-named ExitPlanMode artefacts (`docs-harnesses-gude-md-replicated-backus.md`, `radiant-jingling-frost.md`). Кандидаты на удаление если plans не нужны. |
| `devlog/` | Journal entries + index | ✅ | Universal pattern. |

## Distribution по слоям

Численно текущее состояние:

```
Layer 1 (always-on):           4 components, ~7.5K tokens/turn baseline
Layer 2 (session-start):       1 component, lightweight
Layer 3 (event-triggered):     4 components (3 wired + 1 orphan)
Layer 4 (content-triggered):   2 skills
Layer 5 (invocation):          5 components (2 commands + 3 agents)
Layer 6 (on-demand):           9 docs (включая archive и retro)
```

Соотношение здоровое: load на layer 1 разумный (CLAUDE.md ≤200 строк
guideline соблюдён); большинство компонентов в trigger-loaded слоях 3-5,
не always-on.

## Doc-drift findings (STALE inventory)

Эти findings не блокируют basic-module работу, но требуют исправления
для consistency. Не правлю в этой сессии — separate task.

### Finding 1: `principles.md` inventory секция устарела

`docs/principles.md` lines 19-26 «Components inventory (current state)»:

| Утверждение | Реальность |
|---|---|
| **Custom agents**: `deliverable-planner`, `meta-creator` | `deliverable-planner` retired (commit 733f1d3, 2026-05-11). Реально: `discovery-critic`, `meta-creator`, `security-reviewer`. |
| **Hooks**: `secret-scan` (PreToolUse Edit\|Write\|MultiEdit), `dangerous-cmd-block` (PreToolUse Bash), `auto-format` (PostToolUse), `session-context` (SessionStart) | `secret-scan` / `dangerous-cmd-block` / `auto-format` — **retired** (per `principles.md` Anti-patterns секция упоминает «ADR-010 удалено 5 observability/anti-pattern hooks»). Реально в `settings.json`: `session-context`, `loop-protected-guard`, `discovery-gate`, `stop-validation`. |
| **Reference docs**: `workflow.md`, `multi-agent.md`, `benchmark.md` | Также existing: `memory-layers.md`, `external-sources.md`, `harness-architecture.md` (новый), `retrospective-*.md`. |

### Finding 2: `hooks/README.md` целиком описывает retired hooks

`hooks/README.md` (193 строки) детально документирует:
- `secret-scan.sh` (retired)
- `dangerous-cmd-block.sh` (retired)
- `auto-format.sh` (retired)
- `session-context.sh` (старая 1-line версия, не текущая loop-aware)

Реальные hooks (`loop-protected-guard.sh`, `discovery-gate.sh`,
`stop-validation.sh`) — **не описаны вообще**. README устарел целиком.

### Finding 3: `memory-layers.md` ссылается на `.md` artefacts

Lines 21, 38-46: `PREMORTEM.md` / `EVIDENCE.md` / `CRITIC.md`. Реально —
`.json` (per `discovery-critic.md` schema). Minor.

### Finding 4: `principles.md` упоминает старую spawn policy ADR

Line 33-35 не упоминает `security-reviewer` среди допустимых custom agents.
Reasonable доп.

## Retire candidates

Применение `retire_bias`. Каждый кандидат с обоснованием.

### Retire #1: `agents/meta-creator.md`

**Текущее состояние**: 1236 bytes (16 строк body) — тривиальный workflow:
«уточнить через AskUserQuestion, делегировать в /skill-creator для skills,
создать `.claude/agents/<name>.md` для агентов, добавить в settings.json
для hooks».

**Почему retire**:
1. Encodes assumption «main thread не умеет создать agent/hook/command».
   Под Opus 4.7 main thread уже знает: формат frontmatter описан в
   built-in docs, structure of settings.json — стандартная, hook scripts
   — обычный bash.
2. Anthropic explicit: «do not spawn a subagent for work you can complete
   directly in a single response». Этот workflow — single-response work.
3. CLAUDE.md «Self-evolution» секция уже содержит ту же information
   (skill-creator через marketplace, action-skills only, anti-patterns).
4. Дублирование built-in capability (создание агентов через text-editor)
   — anti-pattern из foundational principle.

**Retire action**: удалить `agents/meta-creator.md`. Обновить CLAUDE.md
self-evolution секцию: убрать упоминание `meta-creator`, оставить guidance
напрямую («main thread создаёт agents/hooks при необходимости; skill-creator
для skills через marketplace; ограничения такие-то»).

### Retire #2: `hooks/cost-warn.sh`

**Текущее состояние**: 1727 bytes. Не подключен в `settings.json`. Header
comment: «Wiring (not done by this iter — settings.json is protected,
requires proposal): hooks.UserPromptSubmit += [{type: command, ...}]».

**Почему retire**:
1. Orphan: код на диске, не вызывается ни одним event. Token cost нулевой,
   ops cost +1 (мейнтейнер должен помнить что это здесь).
2. Self-improvement loop cost — project-specific. Если кому-то нужен
   cost-cap warning — это специфично для loop scenarios, не для basic-module.
3. Не сработал ни разу (по definition, hook не подключен). Retire trigger
   уже сработал.

**Retire action**: удалить `hooks/cost-warn.sh`. Если loop scenario
вернётся к этому — пере-создать через proposal flow.

### Retire #3: `docs/retrospective-2026-05-12-builtins-and-memory.md`

**Текущее состояние**: point-in-time retrospective document.

**Почему retire (relocate)**: snapshot-документы не должны жить в active
docs layer (`docs/`). Active layer per `docs-discipline.md` rule 3 —
для live evolution. Retrospective — frozen snapshot → должно быть в
`archive/`.

**Retire action**: переместить в `docs/archive/retrospective-2026-05-12-builtins-and-memory.md`.

### Keep with note: `commands/loop-status.md`

**Текущее состояние**: project-specific (self-improvement loop reporter).

**Решение**: keep в текущем repo. Exclude из basic-module — это работает
только когда `loop/` scaffolding существует.

### Keep with note: `hooks/loop-protected-guard.sh`

**Текущее состояние**: project-specific (LOOP_MODE=1 gate).

**Решение**: keep в текущем repo. Exclude из basic-module — не applicable
без `loop/` scaffolding.

### Retire #4: `output-styles/` (пустая директория) + `plans/` (stale)

**Текущее состояние**:
- `output-styles/` — пустая директория (создана 2026-05-08, ни одного файла).
- `plans/` — 2 draft plan'а от 2026-05-08/09 с auto-generated именами
  (`docs-harnesses-gude-md-replicated-backus.md`,
  `radiant-jingling-frost.md`) — типичные ExitPlanMode artefacts.

**Почему retire**:
- `output-styles/` — пустой scaffolding без consumer'а. +1 ops cost.
- `plans/` — старые drafts >5 дней без обновлений. Если они не trash,
  должны быть либо incorporated в active docs, либо archived.

**Retire action**:
- `rmdir .claude/output-styles/` (если правда никогда не понадобится).
- Review `plans/*.md` с пользователем: incorporate или удалить.

### Keep with note: `hooks/discovery-gate.sh`

**Текущее состояние**: opt-in pre-`/critique` reminder.

**Решение**: keep + universal. Если basic-module включает Evaluator pattern
(`/critique` + `discovery-critic`), discovery-gate идёт с ним как опциональный
reminder. Если не включает — skip.

## Composition assessment по boundaries

Распределение компонентов по типу границ (после применения retire-кандидатов):

| Boundary | Components | Density |
|---|---|---|
| **Trust gate** | `settings.json` permissions, `loop-protected-guard.sh` | sparse — основная масса в permissions |
| **Information gate** | CLAUDE.md, rules (4), session-context.sh, stop-validation.sh, discovery-gate.sh, skills (2), commands (2), agents (3), docs (8+) | dense — большинство |
| **Containment** | `discovery-critic` agent, `security-reviewer` agent, built-in subagents | thin — три кастомных + built-ins |

**Observation**: information gate несёт основной operational cost
(token + ops complexity). Это normal — большинство harness'ового value
в правильном context loading. Но это же зона риска context rot — нужно
agresively retire stale info-gate компоненты.

**Observation**: trust gate почти полностью на permissions (declarative,
zero token cost). Это оптимально. Дополнительный PreToolUse-block hook
оправдан только когда permissions недостаточно гранулярны (как у
`loop-protected-guard` — он различает context, чего permissions не могут).

## Basic-module recommendation (для отдельного этапа)

После применения retire-кандидатов и исключения project-specific
компонентов — это **универсальное ядро для копирования в новые проекты**.

```
.claude/
├── CLAUDE.md                          # meta-orchestrator (clean inventory)
├── settings.json                      # permissions + hooks wiring
├── rules/
│   ├── api-constraint.md
│   ├── docs-discipline.md
│   └── testing.md
├── docs/
│   ├── harness-architecture.md        # evergreen рамка (этот документ ссылается)
│   ├── principles.md                  # active principles (с обновлённым inventory)
│   ├── workflow.md
│   ├── multi-agent.md
│   └── memory-layers.md
├── hooks/
│   ├── session-context.sh             # без loop STATE branch
│   ├── stop-validation.sh
│   └── discovery-gate.sh              # opt-in: с /critique workflow
├── skills/
│   ├── devlog/
│   └── project-docs-bootstrap/
├── commands/
│   └── critique.md                    # opt-in evaluator
├── agents/
│   ├── discovery-critic.md            # for /critique
│   └── security-reviewer.md
└── devlog/
    ├── entries/                       # пустая, ready to fill
    └── rebuild-index.py
```

**Не входит в basic-module** (project-specific to этого harness):

| Excluded | Reason |
|---|---|
| `loop/` | Self-improvement scaffolding специфичен для этого репо |
| `benchmark/` | Evaluation infrastructure для self-improvement |
| `commands/loop-status.md` | Loop reporter |
| `hooks/loop-protected-guard.sh` | LOOP_MODE-gated |
| `docs/benchmark.md` | Привязан к loop evaluation |
| `docs/external-sources.md` | Каталог research для harness evolution (project-internal) |
| `docs/archive/` | Historical ADRs текущего репо |
| `docs/retrospective-*.md` | Point-in-time snapshots |
| `progress/`, `memory/` | Runtime-created, не template |

**После retire**:
- ❌ `agents/meta-creator.md`
- ❌ `hooks/cost-warn.sh`
- ❌ `output-styles/` (пустая)
- ⚠️ `plans/*.md` (review с пользователем)
- ↪️ `docs/retrospective-*.md` → archive

**Conditional inclusion** (depends on project intent):
- Evaluator pattern (`/critique` + `discovery-critic` + `discovery-gate.sh`) —
  включать если проект high-stakes (security, migrations, untrusted-input
  parsing). Иначе — overkill.
- `project-docs-bootstrap` skill — включать если проект новый (без `docs/`).

## Next steps

1. **Принять** этот audit (или скорректировать findings).
2. **Закрыть doc-drift** (отдельная небольшая задача):
   - Обновить `principles.md` inventory секцию.
   - Переписать `hooks/README.md` под актуальные hooks.
   - Поправить minor refs в `memory-layers.md`.
3. **Применить retire-кандидаты** (отдельная задача):
   - Удалить `agents/meta-creator.md`, обновить CLAUDE.md self-evolution.
   - Удалить `hooks/cost-warn.sh`.
   - Переместить `docs/retrospective-*.md` в archive.
4. **Создать basic-module** (отдельный этап per user direction): script
   или директория `.claude-template/` с copy-ready ядром по рекомендации
   выше.

## Notes по methodology

Этот audit — **первый snapshot** под рамкой
`docs/harness-architecture.md`. Следующий snapshot создаётся при:
- значимом изменении состояния (new component, retirement, structural migration);
- через ~3 месяца, если evolution темп низкий (catch silent doc drift);
- перед major reorganization (e.g., basic-module extraction).

Сравнение между snapshots показывает evolution: какие компоненты
появились, какие retired, как менялась composition по boundaries.
