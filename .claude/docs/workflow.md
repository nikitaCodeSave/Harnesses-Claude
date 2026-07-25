---
owner: nikitaCodeSave
last-updated: 2026-07-22
status: active
supersedes: archive/workflow-2026-05-10.md
---

# Development workflow (frontier-model baseline)

> **«Harness matters more than the model — review your configuration every 3-6 months because instructions tuned for older models constrain newer ones.»** — [claude.com/blog/how-claude-code-works-in-large-codebases](https://www.claude.com/blog/how-claude-code-works-in-large-codebases-best-practices-and-where-to-start) (2026-05-14, first-party).
>
> Этот doc — **тонкий spine**: decision tree поверх built-ins, не дублирующий их описание. Slice-docs см. в [§ Routing](#routing).
>
> Plan→Work→Review здесь — **execution-ядро**. Полный human-facing lifecycle (старт/контракт → требования/PRD → дизайн/ADR → Plan→Work→Review → continuity/guardrails) — [../../WORKFLOW.md](../../WORKFLOW.md).

## Spine: Plan → Work → Review

```
[ weight-class ↓ · Discovery(Explore, brownfield) · PRD-lite+NON-GOALS+инварианты[hard/soft] · design-lite→(large)грилл→ADR ]   ← upstream (WORKFLOW.md §1-3)
       ↓
PLAN     →  WORK              →  REVIEW
понять   →  implement         →  verify vs criteria
+ страт. →  test-driven cycle →  /code-review (+ /code-review ultra для high-stakes)
```

Default для **нетривиальной** задачи. Trivial (typo / formatting / one-liner) — пропускает Plan, идёт Work → Review. **Cold start (новый проект):** `/init` (repo-state → CLAUDE.md) + bootstrap canonical docs (ARCHITECTURE/CODE-MAP/GLOSSARY/CONVENTIONS/ADR/RUNBOOKS — нативно, read-before-write, per `docs-discipline.md`) + контракт (стек / mode / acceptance / verification / DENY) — детали в [../../WORKFLOW.md](../../WORKFLOW.md) §1-3.

### Plan
- Acceptance criteria explicit (что = «done»)
- Спека/план фиксирует *что* и *зачем*; чистая реализация (имена, пути, схема таблиц, библиотека) — не фиксируется, это решение исполнителя. Ограничения = инварианты с `[hard]`/`[soft]` — [WORKFLOW.md](../../WORKFLOW.md) §2
- Critical files identified
- Альтернативы рассмотрены если non-trivial choice
- ADR если объяснение решения >5 мин ([docs-discipline](../rules/docs-discipline.md) rule 6)
- Tools: built-in `Plan` agent via Task tool, Plan mode (Shift+Tab×2), `/goal` (shipped, completion conditions), `ultrathink` trigger, `high` (default) / `xhigh` effort

### Work
- 1 main thread на топовой модели (1M context = весь feature lifecycle помещается без handoff)
- Sequential: read → write test (RED) → implement → run test (GREEN) → refactor — [testing rules](../rules/testing.md)
- `TaskCreate`/`TaskUpdate` для multi-step (>3 substantive steps)
- Subagents on demand only — дисциплина в [multi-agent.md](multi-agent.md)

### Review
- Self-review + tests/lint always
- `/code-review` built-in — дефолтная ступень для substantive change (working diff, local, free, codebase-aware); `/review` — только GitHub PR
- `/code-review ultra` (алиас `/ultrareview`, CLI `claude ultrareview`) — high-stakes (cloud multi-agent, ~5-10min, ~$5-20 via usage credits)
- Doc-with-code rule: PR обновляет doc в том же PR ([docs-discipline](../rules/docs-discipline.md) rule 1)
- Devlog entry через `devlog` skill после significant change

## Routing — which built-in for what

| Задача | Что использовать | Где детали |
|--------|------------------|------------|
| Structured feature workflow (7-phase) | `/feature-dev` plugin (anthropics/claude-plugins-official) | `native-capabilities.md` (kit) |
| Long-running iterative refinement | `/ralph-loop` plugin (canonical Ralph pattern) | [workflow-async.md](workflow-async.md) |
| Async / background watch | `Monitor` tool (v2.1.98+) | [workflow-async.md](workflow-async.md) |
| Parallel feature branches | `-w` worktree + `claude agents` dispatch flags | [workflow-orchestration.md](workflow-orchestration.md) |
| Codebase-scale sweep / migration / multi-angle convergence (local) | **dynamic workflow** (keyword `ultracode`); find→refute→converge | [multi-agent.md](multi-agent.md) |
| Heavy planning | `/ultraplan` (cloud, 3 A/B variants) | [workflow-cloud-offload.md](workflow-cloud-offload.md) |
| Bug-hunt sweep (cloud fleet) | `/ultrareview` (cloud multi-agent fleet) | [workflow-cloud-offload.md](workflow-cloud-offload.md) |
| Scheduled / event-triggered | `Routines` (Anthropic web) | [workflow-cloud-offload.md](workflow-cloud-offload.md) |
| Independent verifications | parallel subagents (built-in `general-purpose`) | [multi-agent.md](multi-agent.md) |
| Commit / PR plumbing | `/commit` / `/commit-push-pr` plugin | `native-capabilities.md` (kit) |
| Старт нового проекта / scaffolding canonical docs | `/init` + bootstrap canonical docs (нативно, `docs-discipline.md`) | [../../WORKFLOW.md](../../WORKFLOW.md) §1-3 |
| Harness self-improvement | measurement loop + retire ritual | [workflow-evolution.md](workflow-evolution.md) |

## When workflow.md alone не покрывает

| Question | Read |
|----------|------|
| «Какой slash-command / flag / tool существует прямо сейчас?» | `~/.claude/skills/claude-code-harness/references/native-capabilities.md` — единственный canonical срез и единственное место, где допустим версионный пин |
| «Watch-process / scheduled task / handoff между сессиями» | [workflow-async.md](workflow-async.md) |
| «Параллельные сессии, worktree, dispatch flags для `claude agents`» | [workflow-orchestration.md](workflow-orchestration.md) |
| «Offload heavy phase в cloud (ultraplan/ultrareview/routines)» | [workflow-cloud-offload.md](workflow-cloud-offload.md) |
| «Когда переучить harness под новую модель» | [workflow-evolution.md](workflow-evolution.md) |
| «Subagent дисциплина: когда spawn, когда нет» | [multi-agent.md](multi-agent.md) |
| «Что взять из community и arXiv, не дублируя» | [external-sources.md](external-sources.md) |
| «Полный lifecycle от старта/контракта/PRD/ADR до пайплайна (human-facing)» | [../../WORKFLOW.md](../../WORKFLOW.md) |

## Default effort

- **`high`** — Anthropic default на agentic coding для текущего поколения (исторически: на Opus 4.7 дефолтом был `xhigh`). Стартуй отсюда.
- **Свипай вниз, а не только вверх.** На новых моделях `low`/`medium` заметно сильнее, чем на прежних, — прогоняй свип по своим задачам вместо того, чтобы держать высокий effort «на всякий случай». Понижение оправдывается замером, а не ощущением.
- **`xhigh`** — для трудных и long-running async задач; **`ultracode`** — **trigger word, не отдельный режим/tier** (per [«A harness for every task»](https://claude.com/blog/a-harness-for-every-task-dynamic-workflows-in-claude-code)): shorthand-сигнал «напиши dynamic workflow», поднимает orchestration к xhigh-уровню. Голое «workflow» больше не триггерит (rename 2.1.160).
- Adaptive thinking ON by default; фиксированные thinking-бюджеты ретайрены — не пытайся управлять ими из харнеса.

## Anti-patterns (cite-anchored)

| Anti-pattern | Evidence | Replacement |
|--------------|----------|-------------|
| Bash `sleep` loops для wait | Anthropic w15 release | `Monitor` tool (event-driven) — см. [workflow-async.md](workflow-async.md) |
| Polling для CI/PR status | community 2026 | `/autofix-pr` + `Monitor` |
| Vibe coding (one-shot без Plan) | SonarSource 16.4% conceptual-bug rate | Plan → Work → Review default |
| Спека фиксирует реализацию (имена/пути/схема/библиотека) | A/B `spec-upstream-ab` 2026-07-22: 6/6 утечек в 3/3, одна подменила acceptance-критерий | детектор «что/зачем — явно, как — не пиши» (WORKFLOW.md §2) |
| Single end-session validation | blakecrosley 35% → 4% false-completion | task-gate + session-gate (two-gate) |
| Multi-agent для *most* coding | Anthropic explicit "ill-suited" (single-agent default) | Main thread; для scope>1 контекста — built-in dynamic workflow, не кастомный pipeline |
| Кастомная оркестрация там, где есть built-in dynamic workflow | built-ins-first | keyword `ultracode` |
| Sampling params (`top_p`/`temperature`/`top_k`) на текущих Opus/Sonnet | HTTP 400 from Anthropic | Omit entirely |
| Effort выставлен «на глаз» и не пересматривается | дефолт = `high`; на новых моделях `low`/`medium` сильнее прежнего | свип по своим задачам в обе стороны, а не фиксированный высокий |

## Sources

Primary first-party (retrieval **2026-05-18**):
- [claude.com/blog — large-codebases best practices](https://www.claude.com/blog/how-claude-code-works-in-large-codebases-best-practices-and-where-to-start) (2026-05-14) — harness-matters-more-than-model doctrine
- [code.claude.com/docs/en/best-practices](https://code.claude.com/docs/en/best-practices) — Cherny + team 2026
- [Boris Cherny — Code w/ Claude 2026 keynote](https://simonwillison.net/2026/May/6/code-w-claude-2026/) — Routines paradigm

Full source catalog: [external-sources.md](external-sources.md). Empirical foundation: [archive/workflow-2026-05-10.md](archive/workflow-2026-05-10.md) (frozen baseline) + [principles.md](principles.md).
