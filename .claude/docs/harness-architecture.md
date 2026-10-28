---
owner: nikitaCodeSave
---

# Harness architecture (evergreen reference)

Reference doc: что этот проект производит, где какое знание живёт и какие границы/бюджеты
компоненты тратят. Описывает **рамку**, не point-in-time state.

## Что этот проект производит (реальный deliverable)

Измеримый результат и цель — **не этот репозиторий**, а две отгружаемые вещи, которые он
выращивает. Всё в `.claude/` здесь — scaffolding для их эволюции.

| Артефакт | Где | Что | Роль |
|---|---|---|---|
| **Плагин `harness`** | marketplace `claude-code-harness` → `~/.claude/skills/harness` | один скилл (новый / существующий / уже с harness'ом проект) и три шаблона: корневой `CLAUDE.md`, `CLAUDE.md` компонента, `settings.json`. Ни агентов, ни команд, ни хуков | **канон**: как поставить harness в любой проект |
| **Глобальная обвязка** | `~/.claude/` | `CLAUDE.md` нет — строка появляется в глобальном слое, только когда её отсутствие навредило в проекте, где у неё нет другого носителя; `settings.json` — приватность и прокси, запрет `/tdd`, автообновление `mattpocock-skills`; скилл `harness` (симлинк на рабочую копию кита), плагин `mattpocock-skills`. Своих хуков нет | **окружение**, действующее во всех проектах без копирования |
| **Лаборатория** (этот репо) | `.claude/` | R&D: эволюция канона через benchmark и ADR; архив завершённых экспериментов | питает первые два, сам не отгружается |

Следствие для этого репо: hooks/commands harness **не держит** ни проектных, ни своих глобальных —
safety закрыт нативным слоем (auto-mode классификатор + встроенный блок деструктивных git/IaC),
continuity — открытой спекой и ADR, verify — блоком *How we work* кита («готово» с командой и
выводом) без хука.

## Foundational principle

**Минимум обвязки → максимум продуктивности под способной моделью.** (Model-agnostic; провенанс
последнего re-grounding — refresh ledger в `native-capabilities.md`.)

> «As models improve, developers should strip away unnecessary scaffolding rather than accumulate
> complexity» — Rajasekaran, Anthropic

Каждое расширение кодирует assumption «модель не умеет X». Если модель делает X нативно, или X
покрывается project CLAUDE.md / built-in'ами — компонент **не добавляется**. Single-incident в
invariant не превращается (нужно multi-source или N≥3 эмпирики).

**Симметричное правило: `retire_bias ≥ add_bias`.** Harness, который только растёт, деградирует
(stale-assumptions копятся, доки устаревают). Активно удалять устаревшее — сильнее, чем «не добавлять
лишнего».

## Виды компонентов (six loading layers)

У компонентов разная **механика загрузки**. Lazy-rule: клади знание в самый ленивый слой, где оно
ещё имеет смысл.

| # | Layer | Trigger | Cost per turn | Носители |
|---|---|---|---|---|
| 1 | **Always-on** | Каждый turn | payload в каждый turn | `CLAUDE.md`, `rules/*.md` |
| 2 | **Session-start** | Раз за сессию | однократный inject | `SessionStart` hooks → `additionalContext` |
| 3 | **Trigger-on-event** | На событие | execution time per event | `PreToolUse`/`PostToolUse`/`Stop`/`UserPromptSubmit` hooks |
| 4 | **Trigger-on-content** | Description матчит | payload skill'а при invocation | `skills/<name>/SKILL.md` |
| 5 | **Trigger-on-invocation** | Explicit invoke | payload при call | `agents/`, `commands/`, built-in subagents |
| 6 | **On-demand reference** | Manual Read | нулевой пока не прочитано | `docs/`, `archive/` |

### Правило выбора слоя

| Знание нужно … | Слой | Пример |
|---|---|---|
| Всегда (cross-session invariant) | 1 — CLAUDE.md / rules | «нет Anthropic API, только CLI», testing invariants |
| Раз за сессию (situational) | 2 — SessionStart hook | состояние окружения (в этом harness'е не используется) |
| При касании конкретных файлов | 1 с `paths:` glob | rules с paths-scope |
| В нужный момент (workflow trigger) | 4 — skill | установка обвязки в проект (`harness`) |
| Для одной задачи | 5 — subagent / slash | security review, evaluator pass |
| История решений | 6 — ADR / git | architectural rationale |

**Не делать**: ситуационное в CLAUDE.md (каждый turn тянет лишнее) · invariant в skill (может не
подгрузиться) · decision history в CLAUDE.md (файл разрастается, «if rules get lost in noise, file
is too long» — Anthropic).

## Три границы (trust · info · containment)

Границы — **композиция, не альтернатива**: один компонент часто закрывает несколько.

| Граница | Что решает | Носители | Failure mode | Дизайн-правило |
|---|---|---|---|---|
| **Trust gate** | пропустить/запретить/спросить tool call | `settings.json` permissions, `PreToolUse` hooks, `Stop` (advisory), subagent `tools:` whitelist, `defaultMode` | privilege escalation, irreversible action без ревью | **block-at-decision, не block-at-write** |
| **Information gate** | какие байты модель видит на turn N | CLAUDE.md/rules (always), `SessionStart`→`additionalContext`, skill `description` trigger, `Read`, `@file` import | cold-start gap ИЛИ context rot | CLAUDE.md ≤200 строк; state on disk, не в контексте; дизайн под ~256K, не под потолок |
| **Containment** | blast radius при ошибке inner-actor'а | custom/built-in subagents (fresh context), git worktrees, restricted `tools:`, process-sandbox | ошибка агента загрязнила main / порушила repo | spawn justified ТОЛЬКО при isolation / parallelism / independent review |

**Композиция в текущем harness'е** (какие границы закрывает компонент):

| Компонент | Trust | Info | Containment |
|---|---|---|---|
| `settings.json` permissions | ✅ | — | — |
| нативный auto-mode классификатор | ✅ (вероятностно) | partial (reason) | — |
| Свежая сессия, промптнутая рефьютить | partial (whitelist) | ✅ (только audited surface) | ✅ (fresh context) |
| Built-in `/code-review ultra` | — | ✅ | ✅ (изолированный флот) |
| Skill (`harness`) | — | ✅ (при триггере) | — |
| Always-loaded rule (`testing.md`) | — | ✅ | — |

## Бюджеты и retire-trigger

Любое расширение — трейдоф трёх бюджетов: **token** (что влезает), **time** (латентность),
**operational complexity** (сколько правил мейнтейнер держит в голове). Token и time — производные
ops-сложности: больше компонентов → больше context-injection и event-latency. `retire_bias`
операционализирует именно ops-бюджет.

**Чеклист расширения** (каждый пункт — явно):

1. **Configurator vs duplicate** — это environment-configurator (preload context / set constraints /
   recognize delegation)? Или duplicate built-in'а / self-description main thread'а? Если второе —
   отвергнуть.
2. **Evidence** — есть empirical evidence (N≥3 или multi-source), что модель не делает X нативно?
3. **Lazy layer** — знание в самом ленивом слое, где оно ещё имеет смысл?
4. **Boundary** — какие из trust/info/containment закрывает? Указать.
5. **Budget** — какие из token/time/ops тратит и сколько?
6. **Retire trigger** — что *наблюдаемое* отметит, что компонент перестал окупаться? Без trigger'а
   компонент паразитный по умолчанию («если за N сессий ни один advisory не сработал → retire»).

## Память — ортогональная ось

Память — не уровень стека, а измерение состояния. Детальный reference — `memory-layers.md`.

| Layer | Что | Persistence |
|---|---|---|
| **L0 in-session scratchpad** | task-list тулы, по умолчанию выключенные на текущем поколении моделей | session |
| **L1 procedural** | CLAUDE.md, rules, skills | cross-session, в git |
| **L2 episodic** | `~/.claude/projects/<hash>/memory/MEMORY.md` + topic files | cross-session, user-scoped |
| **L3 durable artifacts** | коммиты, `benchmark/*/RESULTS.md`; `.claude/devlog/` — замороженный архив | cross-session, в git |
| **L4 semantic** | `.claude/docs/adr/`, `.claude/docs/principles.md`, archive | cross-session, в git |
| **inter-agent** | filesystem blackboard (JSON-вердикт свежей сессии в `.claude/audits/<slug>/`) | per-deliverable, transient |

### Actor views — кто что видит

| Actor | Видит | Не видит |
|---|---|---|
| **main thread** | L1 (всегда), L2 (`MEMORY.md` first ~200 lines auto), L3/L4 при manual Read | inter-agent transient artefacts unless cwd-loaded |
| **subagent** (custom) | spawn prompt + tool results | `MEMORY.md`, ADR, conversation history unless explicit pass |
| **built-in subagent** (Explore/Plan/general-purpose) | spawn prompt + tool results + project CLAUDE.md | episodic memory |
| **hook** | stdin payload (JSON event) + filesystem + env vars | model conversation state |

**Дизайн-правило**: явно укажи, какой actor читает/пишет на каком слое и с каким lifetime. Durable
decision в L0 scratchpad — компонент сломан.

## Anti-patterns

Полный список — `.claude/CLAUDE.md` §Anti-patterns и `principles.md`. Специфичные для архитектуры:

- **Knowledge в неправильном слое** — invariant в skill, situational в CLAUDE.md, history в CLAUDE.md.
- **Stale компонент без retire trigger** — паразитный по умолчанию.
- **Vague always-loaded rule** («be careful», «write clean code») — empirically ignored; specific
  bans / verification criteria > vague guidance.
- **Проектная копия глобального слоя** — дублировать скилл `harness` в репо (он уже действует
  глобально).

## Sources

Полный research-индекс — `external-sources.md`.

- [Claude Code docs: Best Practices](https://docs.claude.com/en/docs/claude-code/best-practices) · [Hooks](https://docs.claude.com/en/docs/claude-code/hooks) · [Skills](https://docs.claude.com/en/docs/claude-code/skills) · [Sub-agents](https://docs.claude.com/en/docs/claude-code/sub-agents) · [Memory](https://docs.claude.com/en/docs/claude-code/memory) · [Settings](https://docs.claude.com/en/docs/claude-code/settings)
- [Anthropic: Harness Design for Long-Running Apps](https://www.anthropic.com/engineering/harness-design-long-running-apps) — Rajasekaran
- [Anthropic: Effective Harnesses for Long-Running Agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) · [Multi-Agent Research System](https://www.anthropic.com/engineering/multi-agent-research-system)
- [Chroma Research: Context Rot](https://research.trychroma.com/context-rot) · [Phil Schmid: Context Engineering Part 2](https://philschmid.de/context-engineering-part-2) (Manus operational data)
