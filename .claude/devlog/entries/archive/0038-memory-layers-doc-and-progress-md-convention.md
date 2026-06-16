---
id: 38
date: 2026-05-12
title: "Memory layers doc and progress.md convention"
tags: [memory, docs, harness, conventions]
status: complete
---

# Memory layers doc and progress.md convention

## Контекст

Запрос от оператора: «как должна реализовываться внутренняя память между сессиями и между агентами? Что советуют Boris Cherny / Matt Pocock / industry?». Triggered by предыдущий research-pass про `/goal` + agent view (devlog #37), где обнаружилось что чужие тексты приносят ложные предпосылки если не сверять с первичными источниками.

Research pass через general-purpose subagent с задачей вытащить **проверенные** ссылки и industry-практики, не выдумки. Результат — карта канонических 5 слоёв памяти (плюс inter-agent communication) и маппинг наших assets.

## Что обнаружено

**Boris Cherny** — реальные позиции (распределены по [howborisusesclaudecode.com](https://howborisusesclaudecode.com/), [Anthropic memory docs](https://code.claude.com/docs/en/memory), YouTube «Building Claude Code with Boris Cherny»):
- CLAUDE.md как **живой артефакт**, обновляется *из ошибок* во время code review
- Layered scopes: managed → user → project → local
- Auto-memory v2.1.59+: Claude пишет в `~/.claude/projects/<hash>/<session-id>/session-memory/summary.md`
- **`/remember` skill** — promote recurring patterns из L2 в L1 с user-confirmation

**Matt Pocock** — НЕ публиковал про runtime memory architecture. Его угол: **SKILL.md как процессуальная память** + deep modules (Ousterhout). Если упоминался в контексте memory — это путаница.

**Anthropic engineering** — три канонических поста:
1. [Effective context engineering for AI agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents) — compaction, structured note-taking, multi-agent isolation, context rot, just-in-time retrieval.
2. [Effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) — cross-session bridge через durable artifacts: `claude-progress.txt`, `feature_list.json`, descriptive commits, `init.sh`.
3. [How we built our multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system) — subagents пишут прямо в filesystem, минуя «game of telephone» через main thread.

**Cognition** «[Don't Build Multi-Agents](https://cognition.ai/blog/dont-build-multi-agents)» — single-threaded writes, subagents только для read/investigation. Совпадает с нашим foundational principle.

**Lance Martin** «[Context Engineering for Agents](https://rlancemartin.github.io/2025/06/23/context_engineering/)» — три глагола: select / compress / isolate. Manus-кейс: `todo.md` переписывается через всю задачу.

**LangChain LangMem** — таксономия semantic / episodic / procedural. Vendor stores (Letta 74% LoCoMo, Mem0 68.5%, Zep 71.2% LongMemEval) overkill для CLI meta-harness.

## Маппинг на наши слои

| Layer | Где у нас | Состояние |
|---|---|---|
| L0 in-session scratchpad | TaskCreate/TaskUpdate built-in | ✓ |
| L1 procedural | `.claude/CLAUDE.md` + `.claude/rules/` + 2 action-skills | ✓ |
| L2 episodic | `~/.claude/projects/<hash>/memory/MEMORY.md` (auto-memory) | ⚠️ curation loop не используется systematically |
| L3 durable | `.claude/devlog/entries/*.md` + `index.json` | ✓ |
| L4 semantic | `.claude/docs/principles.md` + `.claude/docs/archive/` | ✓ |
| inter-agent | PREMORTEM/EVIDENCE/CRITIC через discovery-critic | ✓ (filesystem-blackboard per Anthropic) |

**Единственный реальный пробел**: L2 curation loop — `/remember` skill уже доступен но не интегрирован в operational practice.

## Изменения

- **Создан** `.claude/docs/memory-layers.md` — reference doc (5-layer mapping + curation rituals + anti-patterns + inter-agent pattern documentation). 47 строк.
- **Расширен** `.claude/hooks/session-context.sh` — добавлена detection `.claude/progress/*.md` в additionalContext (existing devlog + loop STATE сохранены).
- **Расширен** `.claude/rules/docs-discipline.md` — добавлено rule 7 «Progress journal для long-running task» (>1ч wall-clock или ≥3 decision points → `.claude/progress/<slug>.md`).
- **Обновлён** `.claude/CLAUDE.md` — ссылка на memory-layers.md в reference materials.
- **Создан** `.claude/progress/` + `.gitkeep` — пустая директория под convention.

## Чего НЕ сделано (и почему)

- **Vendor stores** (Letta/Mem0/Zep) — overkill, premature.
- **Persistence TaskCreate/TaskUpdate** между сессиями — by-design L0 (session-scoped); cross-session goals переходят в L3 (devlog) или progress.md.
- **Авто-hook на progress.md write** — decision point остаётся у разработчика (single-incident в invariant не превращается).
- **Отдельный `init.sh`** — расширил существующий `session-context.sh`, не плодя компоненты.
- **Custom `remember-harness-specific` skill** — built-in `/remember` уже доступен.
- **Static check на размер `.claude/progress/`** — отложен до эмпирики (≥2 случаев применения convention).

## Валидация

- Layer A static checks: 14/14 ✓
- `session-context.sh` syntax: `bash -n` clean
- devlog index: 38 entries, valid
- CLAUDE.md ≤200 строк: 114 строк (113 + 1 новая)
- memory-layers.md links: все relative paths существуют

## Связь с harness

- `.claude/docs/memory-layers.md` — основной артефакт этой записи
- `.claude/hooks/session-context.sh` — extended SessionStart preload
- `.claude/rules/docs-discipline.md` rule 7 — progress journal convention
- `.claude/progress/` — operational directory под convention
- `~/.claude/projects/.../memory/reference_goal_agentview_empirical.md` — предыдущий empirical pass (devlog #37) использовал тот же подход «verify first-party, then implement»
