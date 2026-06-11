---
owner: @nikitaCodeSave
last-updated: 2026-06-07
status: active
---

# Async & background workflow — Claude Code 2.1.169

> Operational layer для **non-blocking** работы: фоновые watch-процессы, scheduled tasks, inter-agent communication, recurring loops. Сюда заглядываем когда agent не должен сидеть и ждать.
>
> Companion к [workflow.md](workflow.md) spine и [builtins-inventory.md](builtins-inventory.md).

## TL;DR

5 primitives:
1. **`Monitor` tool** (v2.1.98) — event-driven background watcher. **Replaces polling/sleep loops** (dominant new primitive 2026 Q2). **Availability (2026-06-11, FP tools-reference#monitor-tool)**: недоступен на Bedrock/Vertex/Foundry и при `DISABLE_TELEMETRY` / `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` — на этой машине отсутствует именно поэтому (`DISABLE_TELEMETRY=1` в `~/.claude/settings.json`); fallback — background Bash (output-file path + `<task-notification>` по завершении).
2. **`Task*` tools** — structured task list (L0 memory layer)
3. **`Cron*` / `ScheduleWakeup`** — time-based wake
4. **`SendMessage`** — agent-to-agent mid-flight communication
5. **`Routines`** — Anthropic web «higher-order prompts that wake up to merged PRs» (Cherny, Code w/ Claude 2026)

Anti-pattern: `bash sleep` loops для wait. Всегда Monitor.

## Decision tree

```
Нужно дождаться output фонового процесса?
  └─ Yes → Monitor tool (event-driven)
        Bash sleep loop = ANTI-PATTERN (per Anthropic w15)

Нужно run-later (specific time)?
  └─ Yes → ScheduleWakeup + Cron* if recurring
        Routines if cloud + event-triggered (см. workflow-cloud-offload.md)

Нужно tracked multi-step progress в сессии?
  └─ Yes → Task* tools (L0)

Нужно message running sub-agent mid-flight?
  └─ Yes → SendMessage({to: <agentId>})

Нужен recurring task с adaptive cadence?
  └─ Yes → /loop self-pacing

Нужен handoff между сессиями?
  └─ Yes → progress.md (L3) + --resume / --continue
```

## When async needed

| Situation | Primitive | Why |
|-----------|-----------|-----|
| Long-running build/test, нужен output как готов | `Monitor` | Event-driven, 200ms batching |
| Multiple parallel checks (lint+test+typecheck) | parallel `Agent` calls + main thread integrate | Standard fan-out — см. [multi-agent.md](multi-agent.md) §7.1. **С 2.1.161 упавший Bash в parallel tool-batch не отменяет siblings** — каждый tool возвращает результат независимо |
| «Wake up tomorrow at 9am и check X» | `ScheduleWakeup` или `Routines` (cloud) | Schedule-driven |
| Recurring task («каждые 10мин check PR status») | `/loop` self-pacing | Adaptive interval |
| Inter-agent коммуникация мид-task | `SendMessage(to: agentId)` | Mid-flight handoff |
| CI auto-fix loop | `/autofix-pr` toggle | Cloud-side, см. [workflow-cloud-offload.md](workflow-cloud-offload.md) |
| Cross-session continuation | `progress.md` (L3) + `--resume` | State on disk, не in context |

---

## Monitor tool (event-driven background)

The **dominant primitive of 2026 Q2**. Pattern:

```
1. Spawn background script (build / test / watch / log-tail)
2. Stdout lines stream into conversation как typed events
3. Agent sees events asynchronously, может реагировать, может остановить, может работать дальше
```

### Configuration

- **`persistent: true`** — survives across turns
- **`timeout_ms`** — auto-stop
- **200ms batching** — мелкие lines аггрегируются для context-efficiency
- Filter aggressively at source: `grep --line-buffered "PATTERN"` to avoid noise

### Pairs with `/loop`

`/loop` adds adaptive interval — Claude picks next-tick automatically based on what Monitor is reporting. Лучше manual cron когда cadence is data-dependent.

### Community convergence

Hermes Agent v0.9 (2026-04-13) шипанул near-identical `watch_patterns` — convergence community → first-party как validation of pattern. Не «another framework idea» — это **canonical primitive**.

### Anti-pattern: bash sleep

```bash
# DON'T
sleep 30 && check_build_status

# DO
Monitor({command: "watch_build.sh", persistent: true})
```

Now explicit anti-pattern per [code.claude.com/docs/en/whats-new/2026-w15](https://code.claude.com/docs/en/whats-new/2026-w15).

---

## Task* tools (structured task list, L0 memory)

L0 in-session scratchpad — **session-scoped**, not persisted между сессиями (per [memory-layers.md](memory-layers.md)).

| Tool | Use |
|------|-----|
| `TaskCreate({subject, description, activeForm?})` | Create new task (status `pending`) |
| `TaskList()` | Show all tasks с status/owner/blockedBy |
| `TaskGet({taskId})` | Full details |
| `TaskUpdate({taskId, status})` | `pending → in_progress → completed` (или `deleted`) |
| `TaskOutput({taskId})` | Read sub-agent task output |
| `TaskStop({taskId})` | Stop running task |

### Triggers (per CLAUDE.md)

- Multi-step task (>3 substantive steps)
- Сложная задача с distinct decision points
- Several teammates / parallel work assignment
- User explicitly запросил todo list

Не использовать для тривиальных линейных задач. **Mark completed немедленно**, не батчем.

### Cross-session — что делать?

`TaskCreate` state NOT персистится между сессиями (L0 by design). Для cross-session goals → `.claude/progress/<slug>.md` (L3 — durable artefact, docs-discipline rule 7).

---

## Cron* / ScheduleWakeup (time-based)

- `CronCreate({...})` / `CronList` / `CronDelete` — scheduled task lifecycle
- `ScheduleWakeup({...})` — future-time session wake

### Use cases (CLI-local)

- Daily PR digest at 09:00 локально
- Build trigger каждый pull
- Weekly maintenance task

### Cron vs Routines

**Cron* tools** — local CLI scheduler. State в `~/.claude/jobs/`.
**Routines** ([workflow-cloud-offload.md](workflow-cloud-offload.md)) — Anthropic web, cloud-side, triggered by cron OR GitHub event OR API.

Cron-локально хорош когда нужно on-machine state (file changes, local DB); Routines — когда trigger external (PR opened, issue commented).

---

## SendMessage (inter-agent mid-flight)

- `SendMessage({to: <agentId or name>, message})` — continue running sub-agent with full context

### When to use vs new `Agent` call

| Need | Use |
|------|-----|
| Continue existing agent thread (full memory) | `SendMessage` |
| Fresh agent without prior context | new `Agent({...})` call |
| Mid-task pivot («also check Y while at it») | `SendMessage` |
| Course-correct без full restart | `SendMessage` |

### Don't overuse

Most sub-agents fire-and-forget (single Agent call → result back). **SendMessage только когда need mid-flight handoff** — most spawn lifecycles линейные.

### Security (2.1.166)

Cross-session `SendMessage` relays **больше не несут user-authority**: receiver отклоняет relayed permission requests, auto mode их блокирует. Не закладывайся на то, что message от другой сессии может авторизовать привилегированное действие.

---

## /loop self-pacing

Week 15 (2026-04-06) addition. Claude picks next-tick interval automatically based on observed activity — лучше fixed cron когда cadence data-dependent.

Pattern:
```
/loop /babysit-prs
```

`/babysit-prs` — это skill определяющий что делать; `/loop` paces it.

Replaces manual `while true; do ...; sleep 600; done` patterns.

---

## Routines (Anthropic web)

Cherny, Code w/ Claude 2026: «Routines are **higher-order prompts** — setup async automations и wake up to PRs that are ready to merge.»

Triggered by:
- **Cron** (time-based)
- **GitHub event** (issue/PR open/comment)
- **API call**

Run on Anthropic's CCR (Cloud Container Runtime). **Subscription-only** — Bedrock/Vertex/Foundry use their own credentials, не compatible.

Full details — [workflow-cloud-offload.md](workflow-cloud-offload.md).

---

## Anti-patterns

| Anti-pattern | Source | Replacement |
|--------------|--------|-------------|
| `sleep 30 && check_status` Bash polling | Anthropic w15 release notes | `Monitor` tool |
| Manual `while true; do ... done` for watching | community 2026 explicit | `Monitor` + `persistent: true` |
| Sleep-based delay для CI status poll | Anthropic | `/autofix-pr` + Monitor |
| `Agent` spawn для one-shot tool call | Anthropic Multi-Agent Research | Direct tool call в main thread |
| `Task*` персистится между сессиями | L0 by design | `progress.md` (L3) для cross-session |
| Fixed cron когда cadence data-dependent | community 2026 | `/loop` self-pacing |
| `SendMessage` спам без mid-flight need | spawn overhead | Single Agent fire-and-forget |

---

## Sources

- [code.claude.com/docs/en/whats-new/2026-w15](https://code.claude.com/docs/en/whats-new/2026-w15) — Monitor tool, `/loop`, `/autofix-pr`, `/team-onboarding`
- [Monitor tool deep-dive (MindStudio)](https://www.mindstudio.ai/blog/claude-code-monitor-tool-background-processes)
- [Boris Cherny — Code w/ Claude 2026 keynote (Simon Willison live-blog)](https://simonwillison.net/2026/May/6/code-w-claude-2026/) — Routines paradigm, «wake up to merged PRs»
- [TechCrunch — Cat Wu interview (2026-05-13)](https://techcrunch.com/2026/05/13/anthropics-cat-wu-says-that-in-the-future-ai-will-anticipate-your-needs-before-you-know-what-they-are/) — proactivity thesis
- [Hermes Agent v0.9 — watch_patterns convergence (Apr 13)](https://github.com/NousResearch/hermes-agent/releases) — community parallel validating pattern
- arXiv [2604.20133 EvoAgent](https://arxiv.org/abs/2604.20133) — skill triggering metadata pattern (multi-stage matching)
- [memory-layers.md](memory-layers.md) — L0/L3 reference для task lifecycle decisions
