---
owner: @nikitaCodeSave
last-updated: 2026-05-18
status: active
---

# Cloud-offload workflow — Claude Code 2.1.143

> Operational layer для **cloud-side execution** heavy phases: `/ultraplan`, `/ultrareview`, `Routines`. Local CLI становится **coordination layer**; cloud runs the fleet.
>
> Companion к [workflow.md](workflow.md) spine, [workflow-orchestration.md](workflow-orchestration.md) (local parallel), [workflow-async.md](workflow-async.md) (`/loop`/Monitor pair).

## TL;DR

**Архитектурный сдвиг 2026 Q2**: planning и code-review перемещаются в Anthropic's CCR (Cloud Container Runtime). Terminal остаётся free для координации.

Cherny (Code w/ Claude 2026 keynote, 2026-05-06): *«Routines = higher-order prompts — setup async automations и wake up to PRs that are ready to merge.»*

3 surfaces:
- **`/ultraplan`** — cloud planning, **3 A/B variants** (Simple / Visual / Deep)
- **`/ultrareview`** — cloud bug-hunting fleet (multi-agent, ~$15-25/run, ~20min)
- **`Routines`** — cron- / GitHub-event- / API-triggered cloud agents

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
  └─ Yes → /ultraplan (cloud) — 3 A/B variants, picks best
        Local alt: built-in Plan agent + ultrathink

High-stakes PR / bug-hunt sweep needed?
  └─ Yes → /ultrareview или `claude ultrareview` (CLI)
        Local alt: /review (local, free, fast)

Need scheduled / event-triggered автоматизация?
  └─ Yes → Routines (web)
        Local alt: Cron* / ScheduleWakeup (workflow-async.md)

CI auto-fix loop on PR?
  └─ Yes → /autofix-pr toggle (cloud-side)
        Local alt: GitHub Actions с `claude --print`
```

---

## `/ultraplan` (cloud planning)

Three A/B-tested variants (per leaked Claude Code source, March 2026):

| Variant | Style |
|---------|-------|
| **Simple** | Direct step-list |
| **Visual** | Tree / diagram-oriented |
| **Deep** | Extended reasoning, multi-hop dependencies |

Anthropic itself doesn't yet know which planning style is best universally — A/B picks per task.

### When to use

- Architectural design touching ≥3 modules
- Multi-component spec where local Plan agent runs out of context
- High-stakes irreversible decision (data migration / payment flow / public API)
- When deliverable spec is ambiguous and you want diverse strategy proposals

### When local Plan is enough

- Bug fix с known root cause
- Single-file refactor
- Trivial feature add
- Когда `xhigh effort + ultrathink trigger` достаточны (most cases under Opus 4.7 1M context)

---

## `/ultrareview` (cloud bug-hunting fleet)

Multi-agent cloud review. **~20 minutes wall-clock, ~$15-25 cost per run.**

Two surfaces:
- **`/ultrareview`** slash-command in interactive session
- **`claude ultrareview [PR-number | base-branch]`** CLI subcommand

### When to use

Cost-justified when production bug «would cost more than $25 to fix in post-deploy».

- Security-sensitive PR
- Pre-deploy validation для public API change
- Database migration
- Payment / billing logic change
- Critical infra change

### When `/review` is enough

- Standard PR (most cases)
- Internal tool refactor
- Style / docs / typo changes
- Когда self-review + tests + lint покрывают acceptance criteria

### Severity tags

Per [code.claude.com/docs/en/code-review](https://code.claude.com/docs/en/code-review):
- 🔴 **Important** — production bugs
- 🟡 **Nit** — style / minor
- 🟣 **Pre-existing** — unrelated to PR

`REVIEW.md` в проекте customizes severity calibration.

---

## Routines (Anthropic web)

«Higher-order prompts» (Cherny) — async automations triggered by external events.

### Triggers

- **Cron** (time)
- **GitHub event** (issue / PR open / comment / merge)
- **API call** (custom integration)

### Use cases (community-reported, 2026 Q2)

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
| `/ultrareview` для every PR | $15-25 × N — drains budget | `/review` локально, `/ultrareview` только high-stakes |
| `/ultraplan` для trivial task | Cloud roundtrip > task time | Local Plan + `xhigh` |
| Routines для one-shot automation | Cron* simpler | Local `Cron*` if applicable |
| Cloud-offload на Bedrock/Vertex | Not compatible | Use local primitives only |
| Skipping local `/review` because cloud will catch it | Misses fast feedback loop | Both: local first, cloud high-stakes |

---

## Re-evaluation triggers

Cloud-offload landscape moves быстро (research-preview features). Re-check этот doc когда:

- New cloud feature releases (`/ultraplan` variant changes, new Routines triggers)
- Pricing changes (`/ultrareview` cost shifts)
- API surface stabilizes (research preview → GA may change defaults)
- Anthropic publishes empirical data on which variant wins

---

## Sources

- [Boris Cherny — Code w/ Claude 2026 keynote (Simon Willison live-blog)](https://simonwillison.net/2026/May/6/code-w-claude-2026/) — Routines paradigm, planning-as-printing-press
- [TechCrunch — Cat Wu interview](https://techcrunch.com/2026/05/13/anthropics-cat-wu-says-that-in-the-future-ai-will-anticipate-your-needs-before-you-know-what-they-are/) — proactivity thesis, Routines as on-ramp
- [/ultraplan tutorial — dev.to](https://dev.to/rams901/claude-code-ultraplan-cloud-based-ai-planning-in-2026-a-hands-on-tutorial-4id6)
- [/ultrareview research preview — explainx.ai](https://explainx.ai/blog/claude-code-ultrareview-cloud-bug-hunt-research-preview)
- [code.claude.com/docs/en/code-review](https://code.claude.com/docs/en/code-review) — severity tags + REVIEW.md customization
- [code.claude.com/docs/en/whats-new — w15-w17](https://code.claude.com/docs/en/whats-new) — release-dated feature timeline
- [api-constraint.md](../rules/api-constraint.md) — what's in/out of scope on subscription
