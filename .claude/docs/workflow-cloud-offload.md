---
owner: nikitaCodeSave
last-updated: 2026-08-07
status: active
---

# Cloud-offload workflow

> Operational layer для **cloud-side execution** heavy phases: `/code-review ultra`, Routines,
> Claude Code on the web. Local CLI становится **coordination layer**; cloud runs the fleet.
>
> Companion к [workflow.md](workflow.md) spine, [workflow-orchestration.md](workflow-orchestration.md) (local parallel), [workflow-async.md](workflow-async.md) (`/loop`/Monitor pair).

## TL;DR

Heavy review и long-running автоматизация уезжают в Anthropic's CCR (Cloud Container Runtime).
Terminal остаётся free для координации.

Cherny (Code w/ Claude 2026 keynote, 2026-05-06): *«Routines = higher-order prompts — setup async automations и wake up to PRs that are ready to merge.»*

3 surfaces:
- **`/code-review ultra`** (алиас `/ultrareview`) — cloud bug-hunting fleet (multi-agent, ~$5-20/run via usage credits, ~5-10min)
- **`Routines`** — cron- / GitHub-event- / API-triggered cloud agents
- **Claude Code on the web** — полноценная cloud-сессия (в т.ч. plan mode); результат забирается локально через `claude --teleport <session id>`

**Reframe meta-orchestrator role**: ты больше не «configures inner executor» — ты **picks which executor (local CLI или cloud fleet)** для каждой phase.

## API constraint check

Cloud-offload features работают **только на Claude subscription**. Incompatible:
- Bedrock / Vertex / Foundry — use own credentials, нет CCR integration
- `ANTHROPIC_API_KEY`-only setups — managed-agents API path, но это другой surface (`platform.claude.com/managed-agents`, out of scope per [api-constraint.md](../rules/api-constraint.md))
- `--bare` mode — explicitly skips cloud-side

В **этом harness'е** работает (CLI subscription) → можно опт-инить. **Не invariant** — это convenience layer, не default.

## Decision tree

```
Heavy planning task (architectural design, multi-component spec)?
  └─ Локально: built-in Plan agent + xhigh/ultrathink — дефолт при 1M context
        Cloud alt: сессия на claude.ai/code в plan mode → claude --teleport <id>

High-stakes PR / bug-hunt sweep needed?
  └─ Yes → /code-review ultra (алиас /ultrareview) или `claude ultrareview` (CLI)
        Local alt: /code-review (working diff, local, free, fast)

Need scheduled / event-triggered автоматизация?
  └─ Yes → Routines (web)
        Local alt: Cron* / ScheduleWakeup (workflow-async.md)

CI auto-fix loop on PR?
  └─ Yes → /autofix-pr toggle (cloud-side)
        Local alt: GitHub Actions с `claude --print`
```

---

## Планирование: локально по умолчанию

Отдельного cloud-planning-командного surface у CLI нет — планирование живёт в локальном plan mode
(built-in `Plan` agent, Shift+Tab×2, `xhigh` + `ultrathink`), а облако подключается как обычная
сессия Claude Code on the web в plan mode, если нужно освободить терминал или уйти с машины.
План возвращается локально через `claude --teleport <session id>` (в cloud-сессии подсказка
приходит по `/teleport`).

### Когда локального Plan достаточно (почти всегда)

- Bug fix с known root cause, single-file refactor, trivial feature add
- Любая задача, где `xhigh effort + ultrathink` укладываются в 1M context — это большинство

### Когда есть смысл увести планирование в облако

- Терминал нужен свободным под параллельную работу, а планирование длинное
- Продолжение с телефона / другой машины
- Планирование по репозиторию, который не выкачан локально

---

## `/code-review ultra` — cloud bug-hunting fleet (алиас `/ultrareview`)

Multi-agent cloud review of the current branch or a PR. **~5-10 minutes wall-clock, ~$5-20 per run via usage credits**; 3 free runs on Pro/Max (one-time).

Surfaces:
- **`/code-review ultra`** slash-command in interactive session (алиас — `/ultrareview`)
- **`claude ultrareview [PR-number | base-branch]`** CLI subcommand (`--json`, `--timeout` default 30 min)

`/review` — алиас `/code-review`; без явного уровня команда переиспользует последний заданный
(`/code-review high` меняет его).

### When to use

Cost-justified when production bug «would cost more than ~$20 to fix in post-deploy».

- Security-sensitive PR
- Pre-deploy validation для public API change
- Database migration
- Payment / billing logic change
- Critical infra change

### When `/code-review` is enough

- Standard PR (most cases) — `/code-review <level> <pr#>` тоже гоняет multi-agent review локально
- Internal tool refactor
- Style / docs / typo changes
- Когда self-review + tests + lint покрывают acceptance criteria

### Severity tags

Per [code.claude.com/docs/en/code-review](https://code.claude.com/docs/en/code-review):
- 🔴 **Important** — production bugs
- 🟡 **Nit** — style / minor
- 🟣 **Pre-existing** — unrelated to PR

`REVIEW.md` в проекте настраивает **управляемый GitHub-сервис** Code Review (Team/Enterprise); локальный `/code-review` его не читает — там рычаг калибровки это уровень effort.

---

## Routines (Anthropic web)

«Higher-order prompts» (Cherny) — async automations triggered by external events.

### Triggers

- **Cron** (time)
- **GitHub event** (issue / PR open / comment / merge)
- **API call** (custom integration)

### Use cases (community-reported)

- Daily PR digest landing in Slack
- Auto-PR на dependency updates (renovate + Claude)
- Issue triage (label / route / propose fix)
- Stale-branch cleanup proposals
- Cherny: «I haven't written a line of code in 2026; ship dozens of PRs/day from phone»

### Setup

Web UI на `claude.com` → Routines section. Configures trigger + skill + repo scope.

State runs in CCR; results land as PRs / Slack messages / API responses.

### When Routines vs local Cron*

| Trigger source | Use |
|----------------|-----|
| Time only, on-machine state | Local `Cron*` ([workflow-async.md](workflow-async.md)) |
| GitHub event | **Routines** |
| External API webhook | **Routines** |
| Cross-machine recurring | **Routines** |
| Local file watching | `Monitor` tool (local) |

---

## Anti-patterns

| Anti-pattern | Why | Replacement |
|--------------|-----|-------------|
| `/code-review ultra` для every PR | $5-20 × N usage credits — drains budget | `/code-review` локально, cloud-прогон только high-stakes |
| Cloud-планирование для trivial task | Cloud roundtrip > task time | Local Plan + `xhigh` |
| Routines для one-shot automation | Cron* simpler | Local `Cron*` if applicable |
| Cloud-offload на Bedrock/Vertex | Not compatible | Use local primitives only |
| Skipping local `/code-review` because cloud will catch it | Misses fast feedback loop | Both: local first, cloud high-stakes |

---

## Re-evaluation triggers

Cloud-offload landscape moves быстро (research-preview features живут и умирают — `/ultraplan`
был удалён из CLI). Re-check этот doc когда:

- New cloud feature releases (new Routines triggers, изменения teleport-канала)
- Pricing changes (`/ultrareview` cost shifts)
- API surface stabilizes (research preview → GA may change defaults)
- Cloud-команда исчезает из `/help` — сверить с `native-capabilities.md`

---

## Sources

- [Boris Cherny — Code w/ Claude 2026 keynote (Simon Willison live-blog)](https://simonwillison.net/2026/May/6/code-w-claude-2026/) — Routines paradigm, planning-as-printing-press
- [TechCrunch — Cat Wu interview](https://techcrunch.com/2026/05/13/anthropics-cat-wu-says-that-in-the-future-ai-will-anticipate-your-needs-before-you-know-what-they-are/) — proactivity thesis, Routines as on-ramp
- [code.claude.com/docs/en/ultraplan](https://code.claude.com/docs/en/ultraplan) (first-party) — фиксирует удаление `/ultraplan` и рекомендованные замены (plan mode + Claude Code on the web)
- [code.claude.com/docs/en/ultrareview](https://code.claude.com/docs/en/ultrareview) (first-party) — timing / cost / free-run economics
- [code.claude.com/docs/en/code-review](https://code.claude.com/docs/en/code-review) — `/code-review` surfaces, severity tags + REVIEW.md customization
- [api-constraint.md](../rules/api-constraint.md) — what's in/out of scope on subscription
