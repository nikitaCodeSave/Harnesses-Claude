---
owner: @nikitaCodeSave
last-updated: 2026-05-14
---

# Harness architecture (evergreen reference)

Покрывает: как устроены компоненты harness'а Claude Code, в каком слое
живёт какое знание, какие границы они защищают и какие бюджеты тратят.

Это reference doc — описывает **рамку**, не конкретный state. Для текущего
inventory компонентов и retire-рекомендаций смотри `audit/<date>-component-audit.md`.

Связанные документы:
- `principles.md` — active principles (current state).
- `memory-layers.md` — детальный memory reference.
- `multi-agent.md` — subagent дисциплина.

## Foundational principle

**Минимум обвязки → максимум продуктивности под Opus 4.7.**

> «As models improve, developers should strip away unnecessary scaffolding
> rather than accumulate complexity» — Rajasekaran, Anthropic (March 2026)

Каждое расширение harness'а кодирует assumption «модель не умеет X». Если
Opus 4.7 делает X нативно, или X покрывается project CLAUDE.md / built-in'ами,
компонент **не добавляется**. Single-incident в invariant не превращается;
pattern требует multi-source evidence или N≥3 повторяющейся эмпирики.

**Симметричное правило**: `retire_bias ≥ add_bias`. Harness, который только
растёт, деградирует: stale-assumptions накапливаются, документация
устаревает, никто не помнит зачем был добавлен hook полгода назад. Активно
удалять устаревшее сильнее, чем «не добавлять лишнего». Это
операционализация **operational-complexity** бюджета (см. ниже); token и
time — производные.

## Виды компонентов (six layers, ordered by laziness)

У компонентов разная **механика загрузки**. Lazy-rule: положить знание в
самый ленивый слой, где оно ещё имеет смысл.

| # | Layer | Trigger | Cost per turn | Носители |
|---|---|---|---|---|
| 1 | **Always-on** | Каждый turn каждой сессии | Token-heavy: payload в каждый turn | `CLAUDE.md`, `rules/*.md` (через @-import или indexer-link) |
| 2 | **Session-start** | Раз за сессию | Однократный inject в системный prompt | `SessionStart` hooks → `additionalContext` |
| 3 | **Trigger-on-event** | На конкретное событие | Execution time per event | `PreToolUse` / `PostToolUse` / `Stop` / `UserPromptSubmit` hooks |
| 4 | **Trigger-on-content** | Когда description матчит | Payload skill'а только при invocation | `skills/<name>/SKILL.md` |
| 5 | **Trigger-on-invocation** | Только при explicit invoke | Payload агента/команды только при call | `agents/<name>.md`, `commands/<name>.md`, built-in subagents |
| 6 | **On-demand reference** | Только при manual Read | Нулевой пока не прочитано | `docs/`, `archive/` |

### Правило выбора слоя

| Когда знание нужно … | Слой | Пример |
|---|---|---|
| Всегда (cross-session invariant) | 1 — CLAUDE.md / rules | «нет Anthropic API, только CLI», testing invariants |
| Раз за сессию (situational context) | 2 — SessionStart hook | last devlog entry pointer |
| При касании конкретных файлов | 1 with `paths:` glob | rules с paths-scope |
| В нужный момент (workflow trigger) | 4 — skill | devlog entry creation, project-docs bootstrap |
| Для одной задачи | 5 — subagent / slash | security review, evaluator pass |
| История решений | 6 — devlog / ADR | architectural rationale, retrospective |

**Не делать**:
- Положить ситуационное знание в CLAUDE.md → каждый turn тянет лишнее.
- Положить invariant в skill → может не подгрузиться когда критично.
- Положить decision history в CLAUDE.md → файл разрастается, контекст
  деградирует (Anthropic: «if rules get lost in noise, file is too long»).

## Три типа границ

Границы — это **композиция, не альтернатива**. Один компонент часто
закрывает несколько границ одновременно.

### 1. Trust gate — что разрешено

**Что решает**: пропустить tool call / запретить / спросить разрешения.

**Артефакт границы**: tool call либо проходит, либо нет.

**Носители**:
- `settings.json` permissions (`allow` / `ask` / `deny` rules)
- `PreToolUse` hooks (block-at-decision на основе payload)
- `Stop` hooks (advisory only — нагнетают, не блокируют)
- Subagent frontmatter `tools:` whitelist (агент не может вызвать что не whitelisted)
- `defaultMode` (plan / auto / acceptEdits / bypassPermissions)

**Failure mode**: privilege escalation, irreversible action без ревью,
exfil через незаметную команду, dangerous-cmd bypass.

**Дизайн правило**: **block-at-decision, не block-at-write**. PreToolUse
читает payload до execution; `UserPromptSubmit` инспектирует prompt content.
Не писать hooks, которые блокируют mid-thought.

### 2. Information gate — что попадает в контекст

**Что решает**: какие байты модель видит на этом turn.

**Артефакт границы**: контекст модели в момент N.

**Носители**:
- CLAUDE.md / rules (always-loaded → каждый turn)
- `SessionStart` hook → `additionalContext` injection (session-once)
- Skill frontmatter `description` → trigger-load при content match
- Slash command body → loaded при invocation
- Manual `Read` → загружает on-demand
- `@file.md` import syntax в CLAUDE.md (max depth 5)

**Failure mode**: знание не попало когда нужно (cold-start gap), или
загрязнило когда не нужно (context rot, instructions lost in noise).

**Дизайн правило**: CLAUDE.md ≤200 строк (Anthropic). State on disk (git
history, devlog, MEMORY.md), не аккумулируется в context. Pre-rot threshold
~256K для 1M-моделей — дизайн под 256K, не под потолок (Chroma «Context
Rot», operational data Manus).

### 3. Containment — где исполняется action

**Что решает**: blast radius. Что может сломаться при ошибке inner-actor'а.

**Артефакт границы**: что попадает / не попадает в main thread'овский state
при failure внутреннего исполнителя.

**Носители**:
- Custom subagents (fresh context — нет передачи conversation history)
- Built-in `Explore` / `Plan` / `general-purpose` агенты
- Git worktrees (изолированная working tree)
- Restricted `tools:` whitelist агента (нельзя выйти за пределы)
- Slash command vs прямые правки в main thread (command-bounded scope)
- Process-level sandbox (опционально, OS-уровень)

**Failure mode**: ошибка в одном агенте загрязнила main thread, или
порушила repo, или переписала protected file.

**Дизайн правило**: spawn justified ТОЛЬКО при (a) context isolation
(search-heavy / broad codebase scan), (b) parallelism (independent
verifications сходящиеся в main thread), (c) auto-compact rescue (редко
при 1M). Mandatory pipeline PM→Architect→Dev→QA — anti-pattern.

### Композиция

Один компонент может закрывать сразу несколько границ. Когда дизайните
компонент — явно проговорите, какие из трёх он закрывает.

Примеры из текущего harness'а:

| Компонент | Trust | Info | Containment |
|---|---|---|---|
| `settings.json` permissions | ✅ | — | — |
| `PreToolUse` block-hook (например `loop-protected-guard`) | ✅ | partial (выдаёт reason) | — |
| `SessionStart` hook (`session-context`) | — | ✅ | — |
| Custom subagent (`discovery-critic`) | partial (tool whitelist) | ✅ (читает только artefacts) | ✅ (fresh context) |
| Slash command (`critique`) | — | ✅ (loads workflow) | partial (bounded scope) |
| Skill (`devlog`) | — | ✅ (загружается при триггере) | — |
| Always-loaded rule (`testing.md`) | — | ✅ | — |

## Три бюджета

Любое расширение harness'а — это **трейдоф между тремя бюджетами**.

| Бюджет | Считается в | На что давит |
|---|---|---|
| **Token** | Токены контекстного окна | Сколько влезает за раз |
| **Time** | Wall-clock секунды | Латентность ответа |
| **Operational complexity** | Cognitive load на мейнтейнера | Сколько правил можно удержать в голове |

### Token budget

- Каждый @-import в CLAUDE.md → запекается в payload **каждый** turn
- `SessionStart` `additionalContext` → запекается раз за сессию (но накапливается за длинную сессию через context)
- Skill payload → загружается раз за trigger
- Subagent spawn → **отдельный** context window, но spawn-overhead в main thread (multi-agent research system: 4–15× tokens overhead)

Pre-rot threshold ~256K для 1M-моделей. «Context rot kicks in well before
the hard limit» — Anthropic. Дизайн под 256K.

### Time budget

- Hook execution time линейно добавляется к каждому matched event
- Subagent spawn = extra model invocation → extra round-trip latency
- External commands в hook (jq, grep, find) — каждый вызов добавляет ms
- Slow hook → user-visible latency на каждом инструменте

### Operational complexity

- N компонентов harness'а → N «как это работает», которые мейнтейнер должен
  помнить и обновлять
- Stale компонент (никто не помнит почему добавлен) — `+cognitive load` без
  `+ценности` → паразитный
- `retire_bias` операционализирует ops-budget: удаление снижает cost
  удерживания

Token и time — **производные операциональной сложности**: больше
компонентов → больше повсюду context-injection → больше токенов; больше
hooks → больше event-handler latency. Сократить операциональную сложность
почти всегда сокращает token и time.

### Дизайн правило

Каждое расширение проходит чеклист (см. также «Соответствие foundational
principle» ниже):

1. Какой из бюджетов я трачу?
2. Сколько вешу: всегда / per-session / per-event / per-invocation?
3. Какой trigger удалит этот компонент, когда он перестанет окупаться?
   («Если за N сессий ни один advisory не сработал → retire».)

## Память — ортогональная ось

Память — **не уровень в стеке**, а измерение состояния. У разных акторов
разный доступ к разным слоям памяти.

Канонические слои (детальный reference — `memory-layers.md`):

| Layer | Что | Persistence |
|---|---|---|
| **L0 in-session scratchpad** | `TaskCreate`/`TaskUpdate` (built-in) | session |
| **L1 procedural** | CLAUDE.md, rules, skills | cross-session, в git |
| **L2 episodic** | `~/.claude/projects/<hash>/memory/MEMORY.md` + topic files | cross-session, user-scoped |
| **L3 durable artifacts** | `.claude/devlog/entries/` + `index.json` | cross-session, в git |
| **L4 semantic** | `.claude/docs/principles.md`, archive | cross-session, в git |
| **inter-agent** | filesystem blackboard (PREMORTEM/EVIDENCE/CRITIC) | per-deliverable, transient |

### Actor views

Разные акторы видят разный subset памяти:

| Actor | Видит | Не видит |
|---|---|---|
| **main thread** | L1 (всегда), L2 (`MEMORY.md` first 200 lines auto), L3/L4 при manual Read | inter-agent transient artefacts unless cwd-loaded |
| **subagent** (custom) | spawn prompt + tool results | `MEMORY.md`, devlog, conversation history unless explicit pass |
| **built-in subagent** (Explore/Plan/general-purpose) | spawn prompt + tool results + project CLAUDE.md | episodic memory |
| **hook** | stdin payload (JSON event) + filesystem + env vars | model conversation state |

### Дизайн правило

Когда дизайните компонент: явно укажите, какой actor читает / пишет на
каком слое, и какое expected lifetime. Если slой не соответствует
expected lifetime (например, durable decision сохраняется в L0 scratchpad)
— компонент сломан.

## Соответствие foundational principle

Каждое расширение harness'а проходит чеклист:

1. **Configurator vs duplicate**: это компонент-как-environment-configurator
   (preload context, set constraints, recognize delegation patterns)?
   Или **duplicate of built-in capability** / **self-description main
   thread'а**? Если второе — отвергнуть.
2. **Evidence threshold**: есть ли empirical evidence (N≥3 incidents
   или multi-source) что Opus 4.7 не делает X нативно? Single-incident
   → недостаточно.
3. **Lazy layer**: положено ли знание в самый ленивый слой, где оно
   ещё имеет смысл?
4. **Boundary explicit**: какие из трёх границ (trust / info / containment)
   закрывает компонент? Указать.
5. **Budget explicit**: какие из трёх бюджетов (token / time / ops)
   тратит? Сколько?
6. **Retire trigger**: что — наблюдаемое — отметит, что компонент
   перестал окупаться? Без trigger'а — компонент паразитный по
   умолчанию.

## Composition matrix (визуально)

Это карта «слой × граница» как способ читать harness:

```
                  Trust gate  │  Info gate  │  Containment
                  ────────────┼─────────────┼──────────────
Layer 1 (CLAUDE.md/rules)         —        │     ✅       │      —
Layer 2 (SessionStart hooks)      —        │     ✅       │      —
Layer 3 (event hooks)             ✅       │   partial    │      —
Layer 4 (skills)                  —        │     ✅       │      —
Layer 5 (agents/commands)       partial    │     ✅       │     ✅
Layer 6 (docs reference)          —        │  on-demand   │      —
                  ────────────┼─────────────┼──────────────
permissions (settings.json)       ✅       │      —       │      —
```

Карта помогает заметить gaps и излишества:
- Trust gate почти полностью держится на permissions + PreToolUse hooks.
- Containment держится на subagents (custom + built-in) + worktrees.
- Information gate — самая населённая граница; здесь и кроется большинство
  риска «context rot».

## Anti-patterns

Корневые из foundational principle + Anthropic explicit guidance:

- **Self-описывающие компоненты** — skill/agent, повторяющий CLAUDE.md о
  роли main thread'а. Anti-pattern из ADR-017.
- **Duplicate of built-in** — кастомные `Explore` / `Plan` /
  `general-purpose` / `statusline-setup` agents.
- **Mandatory multi-agent pipelines** — PM→Architect→Dev→QA, Generator/
  Evaluator за каждый sprint. Opt-in для high-stakes допустимо.
- **Block-at-write hooks** mid-thought (vs PreToolUse block-at-decision).
- **Vague always-loaded rules** («be careful with X», «write clean code»)
  — empirically ignored. Specific bans / specific verification criteria
  > vague guidance.
- **CLAUDE.md > 200 строк** — instructions lost в noise.
- **Knowledge в неправильном слое** — invariant в skill (может не
  подгрузиться), situational в CLAUDE.md (каждый turn тянет лишнее),
  history в CLAUDE.md (файл разрастается).
- **Stale компонент без retire trigger** — паразитный по умолчанию.

## Sources

Retrieval date: **2026-05-14**.

- [Claude Code: Best Practices](https://docs.claude.com/en/docs/claude-code/best-practices)
- [Claude Code: Hooks](https://docs.claude.com/en/docs/claude-code/hooks)
- [Claude Code: Skills](https://docs.claude.com/en/docs/claude-code/skills)
- [Claude Code: Sub-agents](https://docs.claude.com/en/docs/claude-code/sub-agents)
- [Claude Code: Memory](https://docs.claude.com/en/docs/claude-code/memory)
- [Claude Code: Settings](https://docs.claude.com/en/docs/claude-code/settings)
- [Anthropic Engineering: Harness Design for Long-Running Apps](https://www.anthropic.com/engineering/harness-design-long-running-apps) — Rajasekaran, Mar 24 2026
- [Anthropic Engineering: Effective Harnesses for Long-Running Agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents)
- [Anthropic Engineering: Multi-Agent Research System](https://www.anthropic.com/engineering/multi-agent-research-system)
- [Chroma Research: Context Rot](https://research.trychroma.com/context-rot)
- [Phil Schmid: Context Engineering Part 2](https://philschmid.de/context-engineering-part-2) — Manus operational data
- [How Boris uses Claude Code](https://howborisusesclaudecode.com/)
- [Hyung Won Chung tweet](https://x.com/hwchung27/status/1943395653738287429) — structure addition/removal symmetry
