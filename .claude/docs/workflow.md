# Development workflow under Opus 4.7: Plan → Work → Review

> Canonical Claude Code development workflow. Three-phase spine рекомендованный Anthropic и Boris Cherny (создатель Claude Code) как **основной и результативный подход**. Synthesize from Anthropic engineering docs, claude.com blog, и community 2026 evidence. Compiled 2026-05-10.
>
> Этот doc — **active layer reference**, читается main thread'ом on-demand при работе над фичей. Не invariant — обновляется при появлении новых first-party/community practices.

## Core spine

**Plan → Work → Review** — три фазы, один main thread (Opus 4.7 lead), subagents on demand.

Это **default** для любой нетривиальной задачи. Тривиальные правки (typo, formatting, comment) могут пропустить Plan и идти сразу Work → Review. Bug fix с известным root cause — урезанный Plan (формулирует regression test) → Work → Review.

```
┌─────────────┐    ┌──────────────────────┐    ┌──────────────┐
│   PLAN      │───►│       WORK           │───►│   REVIEW     │
│  понять +   │    │ implement (one head) │    │ verify vs    │
│  стратегия  │    │ test-driven cycle    │    │ acceptance   │
└─────────────┘    └──────────────────────┘    └──────────────┘
      │                       │                       │
      │ ultrathink/Plan       │ Opus 4.7 main        │ /review
      │ AskUserQuestion       │ + Sub on (a)(b)(c)   │ + ultrareview
      │ deliverable-planner   │ TodoWrite/Task       │ docs + devlog
```

---

## Phase 1 — Plan

### Что

Понять задачу + сформулировать стратегию **до написания кода**. Зафиксировать acceptance criteria. Идентифицировать критические файлы. Рассмотреть альтернативы если решение non-trivial.

### Когда применять

- Acceptance criteria неявны → формализуем
- Задача затрагивает архитектуру / multi-file refactor / новый модуль / external API
- Не очевиден лучший подход (выбор lib / layout / protocol)
- Security-sensitive change

### Когда пропустить

- Typo / formatting / comment-only
- Bug fix с известным root cause (минимальный Plan: regression test + fix scope)
- Тривиальный one-liner

### Инструменты

| Tool | Когда |
|------|-------|
| Plan mode (`--permission-mode plan` / Shift+Tab×2) | архитектурное предложение для review до writes |
| Built-in `Plan` agent через Task tool | architect-level стратегия для сложной задачи |
| `ultrathink` trigger word | deep reasoning (~31,999 token budget) для race conditions, state mutations, edge cases, trade-off weighing |
| `xhigh` effort tier (April 2026) | default для agentic coding workloads; `/effort xhigh` |
| `deliverable-planner` agent | acceptance criteria fixation для unclear deliverable |
| `AskUserQuestion` | genuine user preferences (UX/deployment/бюджет); НЕ для technical decisions, которые Claude может решить сам |

### Outputs

- Step-by-step strategy (текстом, не код)
- Identified critical files и зависимости
- Acceptance criteria сформулированы explicit
- 2-3 alternatives рассмотрены если значимый выбор
- ADR создан если решение non-trivial (порог: «объяснение в Slack >5 минут»)

### Evidence

- **Anthropic Opus 4.7 best practices**: «well-specified task descriptions that incorporate intent, constraints, acceptance criteria, and relevant file locations yield substantially better results than ambiguous incremental prompting» — [claude.com/blog/best-practices-for-using-claude-opus-4-7-with-claude-code](https://claude.com/blog/best-practices-for-using-claude-opus-4-7-with-claude-code)
- **Opus 4.7 native capability**: «reasons through ambiguous tasks with less direction» — implies clear acceptance criteria > step-by-step micromanagement
- **Plan mode default**: «Claude reads files and proposes a plan but makes no edits until you approve» — [docs.claude.com/en/docs/claude-code/common-workflows](https://docs.claude.com/en/docs/claude-code)
- **Adaptive thinking**: Opus 4.7 decides when to reason deeply; configure via `alwaysThinkingEnabled: true` или `/effort xhigh`. Fixed thinking budgets deprecated.
- **Community confirmation**: Karpathy 4-rule template ("Think Before Coding") как top trending CLAUDE.md pattern April 2026; shanraisshan/claude-code-best-practice: «human is oversight, not typist — research → plan → execute → review → ship»; SonarSource 2026 benchmark — 16.4% Opus 4.5 outputs require human review for conceptual bugs (justifies Plan phase against «vibe coding»).

---

## Phase 2 — Work

### Что

Implement по плану в одной голове. Single main thread, sequential reasoning, test-driven cycle.

### Default approach: single-thread Opus 4.7

- 1M context window — весь feature lifecycle помещается в один thread без потерь на handoff'ах
- Adaptive thinking — model сама reasons deeply на сложных moments
- Sequential: read relevant code → write test (RED) → implement → run test (GREEN) → refactor → re-run

### Test-driven cycle (testing.md инварианты)

1. **Test в той же сессии что и код** (rule 1)
2. **Тест сначала падает (RED), потом проходит (GREEN)** (rule 2)
3. **Тесты живут рядом с кодом** (rule 3)
4. **Один тест — одно поведение** (rule 4)
5. **Регрессионный тест перед фиксом бага** (rule 5)

### Progress tracking

- `TodoWrite` / `TaskCreate` для multi-step задач (>3 substantive steps)
- Mark completed немедленно после завершения task — не батчем
- Не использовать для тривиальных линейных задач

### Subagents on demand (НЕ default)

Spawn оправдан только в трёх случаях:

| Trigger | Пример | Agent |
|---------|--------|-------|
| (a) Изоляция контекста | broad codebase scan, 50+ files, log dive | `Explore` (read-only, Haiku) |
| (b) Параллельность | независимые verifications (build + test + lint), parallel research | `general-purpose` × N |
| (c) Auto-compact rescue | редко при 1M context | `general-purpose` |

Не spawn'ить когда:
- Most coding (Anthropic explicit: «multi-agent ill-suited for most coding»)
- Sequential dependency chain (A→B→C — последовательные tokens, ноль изоляции)
- Subagent wrapper над single tool call
- Trivial task — main thread с полным проектным контекстом быстрее

### Model assignment matrix

| Role | Model | Когда |
|------|-------|-------|
| Main / lead | Opus 4.7 | reasoning, integration, decisions |
| Subagent — reasoning | Sonnet 4.6 | research, exploration с thinking |
| Subagent — grunt | Haiku 4.5 | file scans, log filtering, read-only exploration |

Override per spawn: `Agent({model: "haiku"})`.

### Evidence

- **Anthropic multi-agent research system**: «Opus lead + Sonnet subagents = +90.2%» improvement over single-Opus baseline — [anthropic.com/engineering/multi-agent-research-system](https://www.anthropic.com/engineering/multi-agent-research-system)
- **Token economics**: single agent ≈ 4× обычного chat'а; multi-agent ≈ 15×. 80% variance производительности объясняется token usage (BrowseComp eval) — same source
- **«Spawns fewer subagents by default» под Opus 4.7** — [claude.com/blog/best-practices-for-using-claude-opus-4-7-with-claude-code](https://claude.com/blog/best-practices-for-using-claude-opus-4-7-with-claude-code)
- **Skill auto-discovery в subagents** (May 2026, v2.1.x): subagents теперь auto-find project/user/plugin skills через `Skill` tool — устраняет ранний failure mode «subagents не наследуют parent skills»

### Опциональное расширение: subagent isolation для high-stakes coding

Allow per **D-022** в `.claude/docs/principles.md`. Применять когда измеримо повышает quality — high-stakes production features, security-sensitive PRs, multi-day autonomous work с tricky invariants. Default остаётся single-thread main.

#### Pattern 1 — Planner → Generator → Evaluator (Anthropic canonical для long tasks)

Канонический Anthropic pattern документирован в [Rajasekaran, «Harness design for long-running application development», Mar 24 2026](https://www.anthropic.com/engineering/harness-design-long-running-apps). Validated by leaked Claude Code internals (Mar 2026): [generativeprogrammer.com — 12 agentic harness patterns](https://generativeprogrammer.com/p/12-agentic-harness-patterns-from).

- **Planner** — expand 1-4 sentence prompt в full product spec; intentionally high-level technical details чтобы prevent cascading errors.
- **Generator** — implement против spec; self-evaluation per criteria; commit artifacts.
- **Evaluator** — independent QA против hard thresholds; 5-15 critique-refine cycles при необходимости.

**Negotiated sprint contracts**: Generator + Evaluator agree on what «done» looks like **before** any code written. Quote Rajasekaran: *«[Evaluator] is worth the cost когда task sits beyond what current model does reliably solo»* — hard cost-justification threshold, не default.

#### Pattern 2 — TDD triad (test-writer / implementer / refactorer)

Community evidence: AgentCoder paper 87.8% accuracy с TDD subagent isolation vs 61% single-agent. Sources: [alexop.dev](https://alexop.dev/posts/custom-tdd-workflow-claude-code-vue/), [shivamagarwal7.medium.com](https://shivamagarwal7.medium.com/claude-code-pair-programming-sub-agents-that-tdd-with-minimal-supervision-904e586ed009).

- `tdd-test-writer` (RED) — sees only requirement, не impl plans → tests не могут «cheat» encoding implementation.
- `tdd-implementer` (GREEN) — sees only failing test → forced минимальная impl.
- `tdd-refactorer` (REFACTOR) — clean isolated evaluation.

Real-world: **AgentShield в everything-claude-code** (Anthropic Hackathon winner) — red-team / blue-team / auditor pipeline на трёх Opus агентах для security-sensitive TDD.

#### Pattern 3 — Driver-Navigator (Opus + Sonnet)

- **Navigator** (Opus 4.7, strategic): PLAN/RED/REVIEW — никогда не пишет impl.
- **Driver** (Sonnet 4.6, tactical): GREEN/REFACTOR — никогда не пишет/модифицирует тесты.

Source: [shivamagarwal7.medium.com](https://shivamagarwal7.medium.com/claude-code-pair-programming-sub-agents-that-tdd-with-minimal-supervision-904e586ed009).

#### Default vs opt-in criteria

**Default (single-thread main)** для: bugfixes / prototyping / CRUD / small features. 1M context window достаточен; subagent isolation overhead не оправдан.

**Opt-in subagent isolation** оправдан когда:
- Production-critical / public API / data migration / payment flow
- Security-sensitive PR (adversarial review pattern: attacker / defender / auditor)
- Multi-day autonomous work с риском telephone-game между phases
- Empirically measured: previous single-thread attempt failed quality criteria

Reference implementation для opt-in: [claude-code-harness (Chachamaru127)](https://github.com/Chachamaru127/claude-code-harness) — formal Plan→Work→Review с worker/reviewer/scaffolder agents + Go-native guardrail engine + breezing mode для parallel + опциональная harness-mem (persistent memory).

**API constraint**: [Claude Managed Agents](https://platform.claude.com/docs/en/managed-agents/overview) (cloud-hosted Planner/Generator/Evaluator через `managed-agents-2026-04-01` beta) — API-only, out of scope. **Архитектурные паттерны переносятся** на CLI primitives (Task tool + `.claude/agents/` + hooks).

---

## Phase 3 — Review

### Что

Проверить результат против Plan и acceptance criteria. Catch issues до commit'а / PR'а.

### Layered review

| Layer | Cost | Latency | Когда |
|-------|------|---------|-------|
| **Self-review** main thread | free | seconds | always — re-read diff, check criteria, run tests/lint |
| **Local `/review`** built-in | free | seconds | for every substantive change — codebase-context review |
| **`code-reviewer` agent** read-only | free (tokens) | minutes | для нетривиального change — независимый ракурс без conversation context |
| **`claude ultrareview`** shell-level multi-agent | $15-25 | ~20 min | high-stakes commits — production bug стоит >$20 |
| **Manual human review** | varies | varies | security-sensitive, public API, irreversible migration |

### Two-gate validation (community-recommended)

- **Task-completion gate**: после каждой substantive task — tests pass, lint clean
- **Session-end gate**: Stop hook независимо runs tests перед сессионным финишем

Community evidence: false-completion rate 35% → 4% после внедрения two-gate (blakecrosley case study). Single end-session gate fails late: agent drifts на unrelated tasks до validation.

### Code Review customization

- Project `REVIEW.md` (highest-priority instructions для review): severity calibration, paths to skip, repo-specific checks
- `CLAUDE.md` violations flagged as nits в managed review
- Severity tags: 🔴 Important (production bugs) / 🟡 Nit (style) / 🟣 Pre-existing

### Feature-specific reviewer agents > generic personas

Community empirical observation: «backend engineer» / «QA» generic personas underperform vs concrete role-specific reviewers (`security-checker`, `frontend-qa`, `migration-planner`). Smaller контекст → лучше tool selection и более targeted findings.

### Doc + devlog updates (Review extends to context preservation)

- **Doc-with-code rule**: PR обновляет соответствующий doc (`ARCHITECTURE.md` / `CODE-MAP.md` / `GLOSSARY.md` / ADR) в **том же** PR (docs-discipline rule 1)
- **Devlog entry** через `devlog` skill после significant change — frozen context для будущих сессий
- **Auto memory curation**: extract significant learnings в MEMORY.md, delete из ephemeral auto-log (curate-and-delete loop)

### Evidence

- **`/review` built-in**: «local, fast review with codebase context» — [docs.claude.com/en/docs/claude-code/code-review](https://docs.claude.com/en/docs/claude-code)
- **Managed Code Review (`ultrareview`)**: multi-agent cloud review, ~20 min, $15-25, severity tags — same source
- **Two-gate community evidence**: blakecrosley.com — false-completion 35%→4%
- **Feature-specific reviewer beats generic**: shanraisshan via mcp.directory, developersdigest 2026
- **Karpathy template enforcement**: «Goal-Driven Execution» — verify against original acceptance criteria, не self-assessed «done»

---

## Когда расширять Plan→Work→Review

Default — three phases как описано. Расширение по характеру задачи:

### A. Сложный refactor / architectural change

- **Plan**: ADR обязателен + alternatives evaluated + impact assessment
- **Work**: возможно worktree-isolated subagent (`isolation: "worktree"`) — changes discardable
- **Review**: `ultrareview` + manual

### B. Security-sensitive PR

- **Plan**: explicit threat model в plan section
- **Work**: standard + `secret-scan` hook active
- **Review**: adversarial pattern — attacker / defender / auditor subagents (community: ECC `--opus` flag). Structural blindness failure: single auditor может пропустить что adversarial caught (например, query complexity DoS surface).

### C. High-stakes production feature (public API, data migration, payment flow)

- **Plan**: brainstorm 2-3 alternatives, ADR, deliverable spec через `deliverable-planner`
- **Work**: TDD discipline жёстче (regression suite, integration tests), возможно subagent TDD isolation (opt-in)
- **Review**: `ultrareview` + manual + staging deploy

### D. Quick fix / prototype / typo

- **Plan**: skipped или 1-2 предложения
- **Work**: direct edit, минимальный test (smoke если applicable)
- **Review**: self-review + tests, `/review` опционально

---

## Anti-patterns (empirical 2026, community + Anthropic)

| Anti-pattern | Evidence | Замена |
|--------------|----------|--------|
| CLAUDE.md > 200 строк | yunbow experiment 79.0% → 96.9% после split | indexer + topic files в `.claude/rules/*.md` |
| Vibe coding (one-shot без Plan) | SonarSource 16.4% conceptual-bug rate | Plan → Work → Review default |
| Generic «backend engineer» / «QA» subagents | feature-specific empirically outperform | concrete roles (`security-checker`, `frontend-qa`) |
| Авто-compact fires by default | manual `/compact <hint>` at 50% fill better | proactive compaction with hint |
| Correcting in-place after wrong path | context pollution accumulates | `/rewind` to failure point + re-prompt |
| Phantom verification (claiming pass без session execution) | false-completion 35% baseline | Stop hook независимо runs tests |
| Hedging language («I'm confident») без proof | confidence mirage | ban в CLAUDE.md, require evidence |
| Single end-session validation gate | agent drifts before fail visible | two-gate (task + session) |
| Vague rules («be careful with git») | empirically ignored | specific bans («NEVER commit to main directly») |
| Subagent wrapper над single tool call | spawn overhead > value | direct tool call в main thread |
| Multi-agent для most coding | Anthropic explicit «ill-suited» | main thread + parallel verification только после impl |
| Sequential dependency chain через subagents | N× tokens, ноль parallelism gain | main thread sequential |
| Fixed thinking budgets | deprecated в Opus 4.7 (adaptive) | `/effort` levels или adaptive default |
| Free-form debate rounds между agents | 3 rounds = 7,500 tokens restatement | weighted dimension scoring |
| Generator / Evaluator контракт для каждого sprint'а | Opus 4.7 «devises ways to verify own outputs» | inline verification в Review phase |

---

## What's NEW в 2026 (release-dated)

| Feature | Date | Source |
|---------|------|--------|
| **Adaptive thinking** (Opus 4.7 native) | Feb 2026 | claude.com Opus 4.7 best practices |
| **`xhigh` effort tier** (between `high` и `max`) | April 2026 | claude.com Opus 4.7 best practices |
| **Ultrathink restored** (был deprecated Jan 2026) | March 2026 | decodeclaude.com, findskill.ai |
| **`@docs/file.md` import syntax** в CLAUDE.md | 2026 | obviousworks.ch, shareuhack.com |
| **`paths:`-scoped rule files** в `.claude/rules/*.md` (auto-load on path match) | 2026 | shanraisshan via mcp.directory |
| **Skill auto-discovery в subagents** | May 2026, v2.1.x | blakecrosley.com release notes |
| **`autoMode.hard_deny`** unconditional block tier | May 2026, v2.1.136 | blakecrosley.com |
| **`$CLAUDE_EFFORT` env var в hooks** | v2.1.133 | blakecrosley.com |
| **AGENTS.md cross-vendor standard** (Anthropic + OpenAI + Cursor + Factory + Sourcegraph) | 2026 | blakecrosley.com |
| **`ultrareview` managed Code Review** (multi-agent cloud) | Research preview 2026 | docs.claude.com/code-review |
| **Auto memory (200 lines / 25KB) standard** | Feb 2026 | docs.claude.com/memory |

---

## What's RETIRED / DEPRECATED

| Feature | Why retired | Replacement |
|---------|-------------|-------------|
| Fixed thinking budgets (`--thinking-budget` static) | Opus 4.7 adaptive thinking | `/effort` levels |
| Monolithic CLAUDE.md (>200 lines) | empirical quality drop | indexer + topic files |
| Generic role-based subagents («backend engineer», «QA») | feature-specific outperform | concrete role agents |
| Vibe coding (one-shot prompting) | 16.4% conceptual-bug rate | Plan → Work → Review |
| `.claude/commands/` legacy directory | superseded | `.claude/skills/` with richer YAML |
| Hook old `decision`/`reason` top-level format | superseded API | `hookSpecificOutput` wrapper |
| Free-form debate rounds между agents | wasted tokens | weighted dimension scoring |
| `"Skill"` в `allowed_tools` (claude-agent-sdk ≤0.1.76) | API change | `skills` option on `ClaudeAgentOptions` |
| Worktree default `HEAD` branching (v2.1.128-132) | regression reverted | `origin/<default>`, opt-in `worktree.baseRef: "head"` |

---

## Architectural patterns (Anthropic-canon, validated by leaked Claude Code internals March 2026)

Patterns извлечены из Claude Code source leak (March 2026) и validated against Anthropic engineering blog posts. Аналитический разбор: [generativeprogrammer.com — 12 agentic harness patterns from leaked Claude Code](https://generativeprogrammer.com/p/12-agentic-harness-patterns-from).

| Pattern | Описание | Применение harness'у |
|---------|----------|----------------------|
| **Planner → Generator → Evaluator** | Three-agent canonical для долгих задач: artifacts handoff, не shared context. Evaluator 5-15 cycles critique-refine. | D-022 opt-in для high-stakes (см. Phase 2 опц. расширение) |
| **Tiered memory** | Compact index (≤200 строк) always in context; topic files on-demand; full transcripts на диске | Уже aligned: `docs-discipline.md` rule 2 + auto-memory layout `~/.claude/projects/<slug>/memory/MEMORY.md` |
| **Progressive context compaction** (5 stages) | Budget reduction → snip → microcompact → context collapse → auto-compact | Built-in Claude Code mechanism; manual `/compact <hint>` at ~50% fill = community best practice |
| **Tool gating** (<20 active tools) | Start with <20 tools, activate остальные on demand. С 60+ tools модель плохо выбирает correct tool. | Audit current inventory: harness hooks/skills compact; deferred tools via `ToolSearch` — already built-in pattern |
| **Subagent isolation** | Каждый subagent — own `messages[]` + rebuilt permission context | Spawn policy (a)(b)(c) preserve; D-022 расширяет opt-in для quality |
| **Hooks pipeline** (27 event types) | SessionStart / PreToolUse / PostToolUse / UserPromptSubmit / Stop / TaskCreated / TaskCompleted / PostCompact / ... | Active harness использует 5/27 — есть room для quality-gate hooks (Stop-hook session-end validation, TaskCompleted gate) |

**Note**: Anthropic exposes harness internals programmatically через [Claude Agent SDK](https://code.claude.com/docs/en/agent-sdk/overview) (v0.2.111+ для Opus 4.7) — это API-driven layer, out of scope для CLI-subscription harness. Pattern-level knowledge переносится без SDK dependency через CLI primitives.

Применяем selectively per foundational principle (минимум обвязки), не wholesale.

---

## API constraint (CLI subscription only)

Harness работает строго на подписке Claude Code в CLI. **Skip features требующие Anthropic API**:

- Managed Agents (Dreams, Outcomes, Memory stores)
- Beta headers (`--betas`, `managed-agents-*`, `dreaming-*`)
- `--max-budget-usd` cost controls
- Prompt caching / Batch / Files / Citations API tuning
- `ANTHROPIC_API_KEY` workflows

CLI subscription handles prompt caching nativly (без config). См. `feedback_no_anthropic_api.md` в auto-memory.

---

## Notable community references (для inspiration, не imitate wholesale)

| Repo / source | Что брать | Когда применять |
|---------------|-----------|-----------------|
| **[everything-claude-code (affaan-m)](https://github.com/affaan-m/everything-claude-code)** — **Anthropic Hackathon winner** | 36 subagents, skills, hooks, AgentShield security-сканер (red-team / blue-team / auditor pipeline на 3 Opus agents), TDD-workflow | reference для security-sensitive projects + skill/agent catalog |
| **[claude-code-harness (Chachamaru127)](https://github.com/Chachamaru127/claude-code-harness)** | **Formal Plan→Work→Review** + 5 verb-skills (plan/execute/review/release/setup) + 3 agents (worker/reviewer/scaffolder) + Go-native guardrail engine + breezing mode для parallel задач + опциональная harness-mem (persistent memory) + Codex CLI delegation | closest match нашему canonical spine — borrow patterns selectively |
| **[OpenHarness / Ohmo (HKUDS)](https://github.com/HKUDS/OpenHarness)** | Open implementation полной harness architecture: 43 tools, on-demand skills, plugins, multi-tier permissions, hooks, 54 commands, MCP client, persistent memory, multi-agent coordinator, React TUI. Works с Claude/OpenAI/Kimi/GLM | systems-level reference для понимания harness internals |
| **[Atomic (Lavaee)](https://github.com/flora131/atomic)** | TypeScript toolkit philosophy «не переписывай agent — оборачивай». Open workflow «open-claude-design» (5 deterministic phases) ported между Claude Agent SDK / Copilot CLI / opencode за ~500 строк | portable workflow patterns |
| **Superpowers** (124K+ stars, Anthropic marketplace) | 7-phase pipeline + TDD subagent isolation + fresh subagents per phase | high-stakes production features где TDD discipline critical |
| **[awesome-claude-code-subagents (VoltAgent)](https://github.com/VoltAgent/awesome-claude-code-subagents)** | 100+ specialized subagents с правильными permission tiers (read-only Read/Grep/Glob; research +WebFetch/WebSearch; code-writers +Write/Edit/Bash) | inspiration для subagent catalog в проектах |
| **[awesome-claude-code (hesreallyhim)](https://github.com/hesreallyhim/awesome-claude-code)** | Curated list skills/hooks/slash-commands/orchestrators/plugins | discovery resource |
| **[awesome-harness-engineering (ai-boost)](https://github.com/ai-boost/awesome-harness-engineering)** | Meta-cheatsheet: patterns, evals, memory, MCP, permissions, observability. Reference на **claude-devtools** (распределение токенов по 7 категориям контекста, execution trees subagents с cost breakdown) | benchmark methodology + observability tooling |
| **[learn-claude-code (shareAI-lab)](https://github.com/shareAI-lab/learn-claude-code)** | 12 reverse-engineered sessions (s01-s12): agent loop, tool use, TodoWrite, subagents, skills, context compaction, tasks, background tasks, agent commands, protocols, autonomous agents, worktree isolation. Python references + docs на 3 языках | deepest educational resource — harness internals |
| **claude-code-workflows (shinpr)** | `/recipe-implement` chain (PRD → ADR → Design Doc → Tasks → Impl → Review) | regulated environments с design doc requirements |
| **Karpathy 4-rule CLAUDE.md template** (5,828 stars April 2026) | Think Before Coding / Simplicity First / Surgical Changes / Goal-Driven Execution | baseline behavioral CLAUDE.md для нового проекта |
| **byPawel/devlog-mcp** | daily/weekly/monthly devlog compression, retrospectives, Mermaid diagrams | проекты с long-term continuity needs |
| **HumanLayer production CLAUDE.md** (~60 lines) | minimalist indexer reference | benchmark для CLAUDE.md size |

---

## Re-evaluation triggers

Этот doc — **не invariant**. Re-evaluate когда:

- **Major-релиз модели** (4.7 → 4.8 → 5.x): прогон workflow на классах задач, где Plan/Work/Review structure может перестать быть optimal
- **New built-in agent** в `claude agents`: пересмотреть какой Phase он покрывает / заменяет
- **N≥3 эмпирических промаха** одного типа (наблюдаемый failure mode не в anti-patterns списке) — добавить
- **First-party Anthropic publishes update** к best practices Opus 4.x — sync workflow
- **Community pattern достигает critical mass** (>50K stars / featured Anthropic) — оценить include как опциональное расширение

---

## Sources

Retrieval date: **2026-05-10**. Все ссылки — first-party Anthropic + community 2026.

### First-party (Anthropic)

- [Best practices for using Claude Opus 4.7 with Claude Code](https://claude.com/blog/best-practices-for-using-claude-opus-4-7-with-claude-code)
- [Onboarding Claude Code like a new developer](https://claude.com/blog/onboarding-claude-code-like-a-new-developer-lessons-from-17-years-of-development)
- [Multi-Agent Research System](https://www.anthropic.com/engineering/multi-agent-research-system) — canonical multi-agent positioning
- [Effective Harnesses for Long-Running Agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) — Justin Young, Nov 2025
- [Harness Design for Long-Running Apps](https://www.anthropic.com/engineering/harness-design-long-running-apps) — Rajasekaran, Mar 24 2026 (Planner→Generator→Evaluator + negotiated sprint contracts)
- [Building a C compiler with parallel Claudes](https://www.anthropic.com/engineering/building-c-compiler) — Carlini, Feb 5 2026 (lock-based coordination, GCC oracle)
- [Long-running Claude for scientific computing](https://www.anthropic.com/research/long-running-Claude) — Mishra-Sharma, Mar 23 2026 (Ralph loop, single-agent sequential для coupled pipelines)
- [Common Workflow Patterns for AI Agents](https://claude.com/blog/common-workflow-patterns-for-ai-agents-and-when-to-use-them) — Mar 2026
- [How Anthropic teams use Claude Code](https://claude.com/blog/how-anthropic-teams-use-claude-code) — Jul 2025 (Security Engineering team TDD adoption)
- [Claude Code overview / sub-agents / skills / hooks / memory / common-workflows / settings / code-review / agent-teams / best-practices](https://docs.claude.com/en/docs/claude-code)
- [Claude Agent SDK overview](https://code.claude.com/docs/en/agent-sdk/overview) — harness exposed как programmable API (v0.2.111+ для Opus 4.7); architectural reference, API-driven (out of scope для CLI-subscription)
- [Claude Managed Agents (beta) overview](https://platform.claude.com/docs/en/managed-agents/overview) — cloud-hosted P/G/E через `managed-agents-2026-04-01`; API-only, out of scope per harness API constraint
- [GitHub: anthropics/skills marketplace](https://github.com/anthropics/skills)
- [Boris Cherny — AI Ascent 2026 talk (Sequoia)](https://www.youtube.com/watch?v=SlGRN8jh2RI), [Lightcone interview Feb 2026](https://www.youtube.com/watch?v=PQU9o_5rHC4), [Latent Space podcast with Cat Wu](https://www.latent.space/p/claude-code)

### Community 2026 (verified, multi-source consensus где возможно)

- [blakecrosley.com — Agent Architecture](https://blakecrosley.com/guides/agent-architecture) — primary source release-dated 2026 features, subagent failure modes
- [obviousworks.ch — Designing CLAUDE.md right 2026](https://www.obviousworks.ch/en/designing-claude-md-right-the-2026-architecture-that-finally-makes-claude-code-work/)
- [shareuhack.com — Claude Code CLAUDE.md setup 2026](https://www.shareuhack.com/en/posts/claude-code-claude-md-setup-guide-2026)
- [dev.to/yunbow — 200 lines empirical experiment](https://dev.to/yunbow/200-lines-in-claudemd-dropped-my-code-quality-to-79-splitting-into-3-files-got-it-to-969-1glm)
- [alexop.dev — Custom TDD workflow Claude Code Vue](https://alexop.dev/posts/custom-tdd-workflow-claude-code-vue/)
- [shivamagarwal7.medium.com — pair programming TDD subagents](https://shivamagarwal7.medium.com/claude-code-pair-programming-sub-agents-that-tdd-with-minimal-supervision-904e586ed009)
- [kentgigger.com — Claude Code thinking triggers](https://kentgigger.com/posts/claude-code-thinking-triggers)
- [findskill.ai — Ultrathink extended thinking](https://findskill.ai/blog/claude-ultrathink-extended-thinking/)
- [7tonshark.com — Claude ADR pattern](https://7tonshark.com/posts/claude-adr-pattern/)
- [thepromptshelf.dev — Claude Code memory persistence guide 2026](https://thepromptshelf.dev/blog/claude-code-memory-persistence-guide-2026/)
- [andrew.ooo — Superpowers agentic skills framework](https://andrew.ooo/posts/superpowers-agentic-skills-framework-claude-code/)
- [mcp.directory — Claude Code best practices](https://mcp.directory/blog/claude-code-best-practices) (citing shanraisshan/claude-code-best-practice)
- [developersdigest.tech — Claude Code agent teams subagents 2026](https://www.developersdigest.tech/blog/claude-code-agent-teams-subagents-2026)
- [ofox.ai — Claude Code hooks/subagents/skills guide 2026](https://ofox.ai/blog/claude-code-hooks-subagents-skills-complete-guide-2026/)

### Notable harness repos + meta-resources

- [github.com/affaan-m/everything-claude-code](https://github.com/affaan-m/everything-claude-code) — **Anthropic Hackathon winner**, 36 subagents, AgentShield red/blue/auditor pipeline
- [github.com/Chachamaru127/claude-code-harness](https://github.com/Chachamaru127/claude-code-harness) — **formal Plan→Work→Review** reference + verb-skills + worker/reviewer/scaffolder + Go-native guardrails
- [github.com/HKUDS/OpenHarness](https://github.com/HKUDS/OpenHarness) — open implementation полной harness arch (43 tools, hooks, MCP, multi-agent coordinator, React TUI)
- [github.com/flora131/atomic](https://github.com/flora131/atomic) — portable workflow toolkit (TypeScript, open-claude-design 5-phase ported между Agent SDK / Copilot CLI / opencode)
- [github.com/shinpr/claude-code-workflows](https://github.com/shinpr/claude-code-workflows)
- [github.com/byPawel/devlog-mcp](https://github.com/byPawel/devlog-mcp)
- [github.com/VoltAgent/awesome-claude-code-subagents](https://github.com/VoltAgent/awesome-claude-code-subagents) — 100+ subagents с tier'ed permissions
- [github.com/hesreallyhim/awesome-claude-code](https://github.com/hesreallyhim/awesome-claude-code) — curated skills/hooks/commands list
- [github.com/ai-boost/awesome-harness-engineering](https://github.com/ai-boost/awesome-harness-engineering) — meta-cheatsheet + claude-devtools reference
- [github.com/shareAI-lab/learn-claude-code](https://github.com/shareAI-lab/learn-claude-code) — 12 reverse-engineered sessions (deepest educational)

### Architectural analysis

- [generativeprogrammer.com — 12 agentic harness patterns from leaked Claude Code (Mar 2026)](https://generativeprogrammer.com/p/12-agentic-harness-patterns-from) — Planner→Generator→Evaluator, tiered memory, progressive compaction (5 stages), tool gating, subagent isolation, hooks pipeline 27 events
- [medium.com/jonathans-musings — Inside the Agent Harness](https://medium.com/jonathans-musings/inside-the-agent-harness-how-codex-and-claude-code-actually-work-63593e26c176) — J. Fulton, code-level разбор Codex CLI + Claude Code: agent loop, token estimation, compaction, parallel_tool_calls

### Caveats

Community version-specific numbers (e.g., v2.1.136, 124K stars) — community-reported, не verified против Anthropic changelog. Verify против `claude --version` / official release notes перед relying на specific feature availability. Стратегия: feature mentioned by ≥2 independent community sources → likely real; single-source feature → mark «verify».
