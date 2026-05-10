---
owner: @nikitaCodeSave
last-updated: 2026-05-10
---

# Claude Code harness principles

Active principles этого harness'а. Self-contained, evidence-based на canonical Anthropic Claude Code documentation 2026. Sources в конце документа.

## Foundational

- **Минимум обвязки → максимум продуктивности под Opus 4.7**. Anthropic: *«As models improve, developers should strip away unnecessary scaffolding rather than accumulate complexity»* — [Harness Design for Long-Running Apps](https://www.anthropic.com/engineering/harness-design-long-running-apps).
- **Spawn fewer subagents by default**. Anthropic: *«Opus 4.7 spawns fewer subagents by default. Do not spawn a subagent for work you can complete directly in a single response»* — [Best Practices](https://docs.claude.com/en/docs/claude-code/best-practices).
- **Adaptive thinking**, `xhigh` effort tier — default для agentic coding workloads. Model сама decides when to reason deeply. Fixed thinking budgets deprecated.
- **1M context — constraint, не resource to ignore**. *«Context rot — steady degradation of model performance as the window gets full — kicks in well before the hard limit»* — [Effective Harnesses for Long-Running Agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents). State живёт на диске (git history, devlog, MEMORY.md), не аккумулируется в context.
- **Verification — highest-leverage practice**. *«Claude performs dramatically better when it can verify its own work — run tests, compare screenshots, validate outputs. Without clear success criteria, it might produce something that looks right but actually doesn't work»* — Best Practices.
- **CLI subscription only** (harness-specific). Out of scope: managed-agents (Dreams/Outcomes/Memory stores), beta headers (`--betas`, `managed-agents-*`, `dreaming-*`), `--max-budget-usd`, prompt caching / batch / files / citations API. CLI native primitives (hooks, skills, subagents, slash commands) — единственный execution surface.

## Components inventory (current state)

- **Skills** (action-only, workflow-templates): `devlog`, `project-docs-bootstrap`. SKILL.md ≤500 строк.
- **Custom agents**: `deliverable-planner`, `meta-creator` (в `.claude/agents/`).
- **Built-in agents**: `Explore` (read-only research), `Plan` (architect-level planning), `general-purpose` (open-ended), `statusline-setup` (UI).
- **Hooks**: `secret-scan` (PreToolUse Edit|Write|MultiEdit), `dangerous-cmd-block` (PreToolUse Bash), `auto-format` (PostToolUse), `session-context` (SessionStart).
- **Always-loaded rules**: `testing.md` (5 invariants), `docs-discipline.md` (6 invariants).
- **Reference docs** (on-demand): `workflow.md` (Plan→Work→Review canonical), `multi-agent.md` (subagent дисциплина), `benchmark.md` (3-tier methodology).

## Subagents

- **Built-ins first**. Перед созданием custom — `claude agents`. Дублирование built-in (`Explore`/`Plan`/`general-purpose`/`statusline-setup`) — anti-pattern.
- **Spawn justified ТОЛЬКО**: (а) context isolation (search-heavy / broad codebase scan загрязнит main), (б) parallelism (independent verifications сходящиеся в main), (в) auto-compact rescue (редко при 1M).
- **Multi-agent ill-suited для most coding**. *«Most coding tasks involve fewer truly parallelizable tasks than research»* — [Multi-Agent Research System](https://www.anthropic.com/engineering/multi-agent-research-system). 4–15× tokens overhead. Verify ROI до spawn.
- **Subagent isolation для high-stakes — opt-in допустимо**. Patterns: Planner→Generator→Evaluator (canonical Anthropic для long tasks, Rajasekaran 2026), TDD triad (test-writer/implementer/refactorer), Driver-Navigator (Opus+Sonnet). Cost-threshold per Rajasekaran: *«worth the cost когда task sits beyond what current model does reliably solo»*. **Mandatory** pipeline за каждую задачу — anti-pattern.
- **Model assignment**: main/lead = Opus 4.7; reasoning subagent = Sonnet 4.6; grunt (file scans, log filtering) = Haiku 4.5.
- **Custom agent justified только**: специализированный domain (security-reviewer, accessibility-auditor), restricted tool set enforcing policy, persistent memory isolation. Orchestration / general-purpose work — main thread.

## Skills (Agent Skills)

- **Action-skills only**. Workflow-templates для конкретной операции (`devlog`, `project-docs-bootstrap`). Self-описывающие skills (повторяют CLAUDE.md о role main thread'а) — anti-pattern.
- **Frontmatter required**: `name` (lowercase, hyphens, ≤64 chars), `description` (когда применять, обязательно включать trigger-контекст).
- **Optional**: `allowed-tools`, `model`, `paths` (glob для auto-load), `disable-model-invocation`, `user-invocable`.
- **SKILL.md ≤500 строк**. Длинный reference content — в `references/` subfolder, читается on-demand.
- **Skill-creator** — через marketplace plugin (`anthropics/skills`), не форкается локально.
- Source: [Skills documentation](https://docs.claude.com/en/docs/claude-code/skills).

## Hooks

- **Use hook когда action must happen every time с zero exceptions**. *«Unlike CLAUDE.md instructions which are advisory, hooks are deterministic and guarantee the action happens»* — Best Practices.
- **Block-at-decision (PreToolUse), не block-at-write**. PreToolUse инспектирует tool input до execution; `UserPromptSubmit` — инспектирует user prompt content. Avoid blocking mid-thought.
- **Event types в harness'е**: `PreToolUse` (secret-scan, dangerous-cmd-block), `PostToolUse` (auto-format), `SessionStart` (session-context inject). Full canonical list: SessionStart, UserPromptSubmit, PreToolUse, PostToolUse, Stop, PreCompact, PostCompact, и др.
- **Handler types**: `command` (shell + JSON), `mcp_tool`, `http`. Exit code 0 = allow, 2 = block, other = non-blocking error.
- Source: [Hooks documentation](https://docs.claude.com/en/docs/claude-code/hooks).

## Memory

- **CLAUDE.md hierarchy** (highest → lowest precedence): managed-policy → local → project (`./CLAUDE.md` / `./.claude/CLAUDE.md`) → user (`~/.claude/CLAUDE.md`). Subdirectory CLAUDE.md — lazy-loaded когда files в этой directory затрагиваются.
- **CLAUDE.md ≤200 lines**. *«If rules get lost in noise, file is too long»* — Best Practices. Длиннее — split в path-scoped `.claude/rules/*.md` или import via `@file` syntax.
- **`@path/to/file.md` import syntax** — expanded at launch. Resolves relative к containing file. Max depth 5 hops (cycle detection enabled).
- **Auto-memory**: `~/.claude/projects/<slug>/memory/MEMORY.md` (first 200 lines / 25KB auto-loaded). Topic files (`feedback_*.md`, `user_*.md`) загружаются on-demand при relevance.
- **Curate-and-delete loop**: значимые learnings в MEMORY.md / topic files; ephemeral session-log trim. Stale (>6 months) — review.
- **State on disk, не в context**: git history, devlog entries, MEMORY.md — primary truth между сессиями.
- Source: [Memory documentation](https://docs.claude.com/en/docs/claude-code/memory).

## Settings & permissions

- **Permissions model** (3-layer, evaluated `deny` → `ask` → `allow`): `Tool`, `Tool(command *)`, `Tool(regex:pattern)`, `MCP(server:tool)`.
- **defaultMode**: `default` / `plan` (review-before-execute) / `auto` (classifier-based) / `acceptEdits` (rare) / `dontAsk` (production scripts) / `bypassPermissions` (explicit intent).
- **Settings hierarchy**: local > project > user > managed-policy. Arrays concat, objects deep-merge.
- **Security boundary этого harness'а**: permissions whitelist + `secret-scan` hook (PreToolUse Edit|Write|MultiEdit) + `dangerous-cmd-block` (PreToolUse Bash). OS-level sandbox optional.
- Source: [Settings documentation](https://docs.claude.com/en/docs/claude-code/settings).

## Testing & verification

- **Verification universal, TDD opt-in**. 2026 Anthropic reframe: TDD — один из методов verification, не invariant. *«Give Claude a way to verify its work — this is the single highest-leverage thing you can do»* — Best Practices.
- **TDD оправдан** для changes *«easily verifiable with unit, integration, or end-to-end tests»* — Best Practices (опт-in framing).
- 5 invariants в `.claude/rules/testing.md`: тест в той же сессии что и код / RED → GREEN / тесты рядом с кодом / один тест — одно поведение / регрессионный тест перед фиксом.
- **Address root causes, не symptoms**: *«fix the underlying issue, don't suppress the error»* — Best Practices.

## Documentation

- **CLAUDE.md как indexer, не store**. Ссылается на `docs/ARCHITECTURE.md` / `docs/CODE-MAP.md` / `docs/GLOSSARY.md` (project layer); `.claude/docs/` (harness layer); `.claude/rules/` (always-loaded invariants). Цель: ≤200 строк.
- **Project docs layout** (создаётся `project-docs-bootstrap` skill в target-проектах): `docs/ARCHITECTURE.md`, `docs/CODE-MAP.md`, `docs/GLOSSARY.md`, `docs/CONVENTIONS.md`, `docs/ADR/`, `docs/RUNBOOKS/`. Read-before-write — каждый doc отражает реальное состояние, не template.
- **Harness docs** (этого pack'а): `.claude/docs/principles.md` (этот файл, current state), `workflow.md`, `multi-agent.md`, `benchmark.md`. Archive layer (`.claude/docs/archive/`) — frozen historical snapshot.
- **Live vs archive**: active docs редактируются inline для evolve; archive — frozen, изменяется только через structural migrations.
- 6 invariants в `.claude/rules/docs-discipline.md`: doc-with-code rule / CLAUDE.md как indexer / live vs archive / owner+last-updated / glossary first-use / ADR для non-trivial decisions.

## Process

- **Plan → Work → Review** — canonical Anthropic baseline. Plan mode (`--permission-mode plan` / Shift+Tab×2) для architectural changes до writes. Skip для trivial fixes. Full workflow — `.claude/docs/workflow.md`.
- **`/review` built-in** — local, free, instant — для inner-loop. `claude ultrareview` (managed multi-agent cloud review) — для high-stakes gates.
- **Auto mode не drop-in для review**. *«Auto mode is not a drop-in replacement for careful human review on high-stakes infrastructure»* — Anthropic Engineering.
- **Single-incident NOT invariant**. Pattern требует multi-source evidence или повторяющейся empirics перед фиксацией как rule.
- **Pilot validation для harness changes**: Tier 0 (static, <10s, blocker) → Tier 1 (pilot project task suite) → Tier 2 (per-component evals). Methodology — `.claude/docs/benchmark.md`.
- **Empirical cost envelope** (2026-05-11, devlog #24): на T01/T02 simple tasks our harness даёт +24-27% cost vs no-harness baseline под Opus 4.7 при идентичном quality. ECC raw inject ≈ neutral, но ломает pytest discovery через 90+ parasitic tests. cwc-long-running-agents +46% cost — opt-in для long-running fixed-spec scenarios. Re-measure при major model upgrade или ±10% baseline drift.

## Anti-patterns

- **Multi-agent для most coding** — Anthropic explicit. Sequential dependency chain (A→B→C через subagents), subagent wrapper над single tool call, multi-agent для tightly-coupled pipelines.
- **Mandatory multi-agent pipelines** (PM→Architect→Dev→QA, Generator/Evaluator за каждый sprint) — anti-pattern. Opt-in для high-stakes — допустимо.
- **Дублирование built-in subagents / capabilities** — `Explore`/`Plan`/`general-purpose`/`statusline-setup` не форкаются.
- **Self-описывающие skills** — повторяют CLAUDE.md о role main thread'а.
- **CLAUDE.md > 200 строк** — instructions lost в noise, model adherence drops.
- **Trust-then-verify gap** — *«Claude produces a plausible-looking implementation that doesn't handle edge cases. Fix: Always provide verification (tests, scripts, screenshots). If you can't verify it, don't ship it»* — Best Practices.
- **Block-at-write hooks** mid-thought (vs PreToolUse block-at-decision).
- **Fixed thinking budgets** — deprecated (adaptive thinking в Opus 4.7).
- **Vague instructions** ("be careful with X", "write clean code") — empirically ignored. Specific bans / specific verification criteria > vague guidance.

## Sources

Retrieval date: **2026-05-10**.

- [Claude Code Best Practices](https://docs.claude.com/en/docs/claude-code/best-practices) — canonical Cherny + team 2026
- [Claude Code: Sub-agents](https://docs.claude.com/en/docs/claude-code/sub-agents)
- [Claude Code: Skills](https://docs.claude.com/en/docs/claude-code/skills)
- [Claude Code: Hooks](https://docs.claude.com/en/docs/claude-code/hooks)
- [Claude Code: Memory](https://docs.claude.com/en/docs/claude-code/memory)
- [Claude Code: Settings](https://docs.claude.com/en/docs/claude-code/settings)
- [Claude Code: Common workflows](https://docs.claude.com/en/docs/claude-code/common-workflows)
- [Claude Code: Code review](https://docs.claude.com/en/docs/claude-code/code-review)
- [Best practices for Opus 4.7 with Claude Code](https://claude.com/blog/best-practices-for-using-claude-opus-4-7-with-claude-code)
- [Anthropic Engineering: Multi-Agent Research System](https://www.anthropic.com/engineering/multi-agent-research-system)
- [Anthropic Engineering: Effective Harnesses for Long-Running Agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents)
- [Anthropic Engineering: Harness Design for Long-Running Apps](https://www.anthropic.com/engineering/harness-design-long-running-apps) — Rajasekaran, Mar 24 2026 (Planner→Generator→Evaluator canonical)
- [GitHub: anthropics/skills marketplace](https://github.com/anthropics/skills)
