---
owner: @nikitaCodeSave
last-updated: 2026-06-09
---

# Claude Code harness principles

Active principles этого harness'а. Self-contained, evidence-based на canonical Anthropic Claude Code documentation 2026. Sources в конце документа.

## Foundational

- **Минимум обвязки → максимум продуктивности под способной моделью** (re-grounded на Opus 4.8; принцип model-agnostic — не пере-привязывай к версии). Anthropic: *«As models improve, developers should strip away unnecessary scaffolding rather than accumulate complexity»* — [Harness Design for Long-Running Apps](https://www.anthropic.com/engineering/harness-design-long-running-apps).
- **Single-agent first; spawn fewer subagents by default**. Под способной моделью один main thread остаётся дефолтом для most coding. Bounded fan-out — через built-in **dynamic workflows** (keyword `ultracode`), не кастомную обвязку, и только когда scope превышает один контекст (см. Subagents).
- **Adaptive thinking; effort default `high` (Opus 4.8)**. На 4.8 дефолтный effort tier — `high` (на 4.7 был `xhigh`); `xhigh` рекомендуется для трудных и long-running async задач. Model сама decides when to reason deeply; fixed thinking budgets deprecated.
- **1M context — constraint, не resource to ignore**. *«Context rot — steady degradation of model performance as the window gets full — kicks in well before the hard limit»* — [Effective Harnesses for Long-Running Agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents). Opus 4.8 заметно надёжнее на long-context и при восстановлении после compaction (GraphWalks 1M F1 ~40%→~68%), но context rot сохраняется — bigger ≠ free. Эмпирический pre-rot порог ~256–400K ([Chroma «Context Rot»](https://research.trychroma.com/context-rot), operational data Manus [Phil Schmid Part 2](https://philschmid.de/context-engineering-part-2)) — **pending re-measurement под 4.8**; компактифицируй *до* входа в зону деградации, не у потолка. State живёт на диске (git history, devlog, MEMORY.md), не аккумулируется в context.
- **Verification — highest-leverage practice**. *«Claude performs dramatically better when it can verify its own work — run tests, compare screenshots, validate outputs. Without clear success criteria, it might produce something that looks right but actually doesn't work»* — Best Practices.
- **CLI subscription only** (harness-specific). Out of scope: managed-agents (Dreams/Outcomes/Memory stores), beta headers (`--betas`, `managed-agents-*`, `dreaming-*`), `--max-budget-usd`, prompt caching / batch / files / citations API. CLI native primitives (hooks, skills, subagents, slash commands) — единственный execution surface.

## Components inventory (current state)

- **Skills** (action-only, workflow-templates): `update-plan-progress`. Devlog — глобальный канон `~/.claude/skills/devlog/` (project-pin скрипта: `.claude/devlog/rebuild-index.py`). SKILL.md ≤500 строк. Каноничное знание о дизайне harness'а — глобальный `~/.claude/skills/claude-code-harness/`. (`project-docs-bootstrap` ретайрнут 2026-06 — staleness A/B n=2: нет лифта над native + WORKFLOW.md §3 + docs-discipline.)
- **Custom agents**: нет — зачистка 2026-06-11 (devlog #95): `meta-creator` (нативная способность), `security-reviewer` (built-in `/security-review`), `discovery-critic` + `/critique` + `discovery-gate` hook (superseded плагином `claude-code-harness:/external-audit` с 3 ролями).
- **Built-in agents** (5): `Explore` (read-only research), `Plan` (architect-level planning), `general-purpose` (open-ended), `statusline-setup` (UI), `claude-code-guide` (вопросы про Claude Code).
- **Hooks**: `session-context` (SessionStart), `stop-validation` (Stop, advisory), `loop-protected-guard` (PreToolUse, активен при `LOOP_MODE=1`), `cost-warn` (UserPromptSubmit).
- **Always-loaded rules**: `testing.md` (5 invariants), `docs-discipline.md` (7 invariants), `api-constraint.md`.
- **Reference docs** (on-demand): `workflow.md` (Plan→Work→Review spine + slice docs), `multi-agent.md`, `benchmark.md`, и др. в `.claude/docs/`.

## Subagents

- **Built-ins first**. Перед созданием custom — `claude agents`. Дублирование built-in (`Explore`/`Plan`/`general-purpose`/`statusline-setup`/`claude-code-guide`) — anti-pattern.
- **Spawn justified ТОЛЬКО**: (а) context isolation (search-heavy / broad codebase scan загрязнит main), (б) parallelism (independent verifications сходящиеся в main), (в) auto-compact rescue (редко при 1M).
- **Single-agent default; bounded fan-out когда scope превышает один контекст**. Most coding — single thread (*«Most coding tasks involve fewer truly parallelizable tasks than research»* — [Multi-Agent Research System](https://www.anthropic.com/engineering/multi-agent-research-system)). Что изменилось под 4.8: Anthropic ship'нул **dynamic workflows** как first-party bounded-fan-out примитив (keyword `ultracode`, или просто попроси) — по built-ins-first роутим к нему для codebase-scale sweep / миграции / trust-critical верификации (find→refute→converge), НЕ переизобретаем оркестрацию кастомной машинерией. Стоит заметно больше токенов — не дефолт; verify ROI до fan-out. First-party обоснование — [«A harness for every task» (Shihipar & Bidasaria, 2 июня 2026)](https://claude.com/blog/a-harness-for-every-task-dynamic-workflows-in-claude-code): изолированные субагенты структурно лечат три failure-mode длинных/параллельных прогонов — **agentic laziness**, **self-preferential bias** (ровно почему §8 fresh-context ≠ self-recheck), **goal drift**.
- **Subagent isolation для high-stakes — opt-in допустимо**. Patterns: Planner→Generator→Evaluator (canonical Anthropic для long tasks, Rajasekaran 2026 — теперь нативно покрывается dynamic workflows на CLI-подписке, без API), TDD triad (test-writer/implementer/refactorer), Driver-Navigator (Opus+Sonnet). Cost-threshold per Rajasekaran: *«worth the cost когда task sits beyond what current model does reliably solo»*. **Mandatory** pipeline за каждую задачу — anti-pattern.
- **Model assignment**: main/lead = Opus 4.8; reasoning subagent = Sonnet 4.6; grunt (file scans, log filtering) = Haiku 4.5. Agent teams (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`) — experimental, off by default.
- **Custom agent justified только**: специализированный domain (security-reviewer, accessibility-auditor), restricted tool set enforcing policy, persistent memory isolation. Orchestration / general-purpose work — main thread.

## Skills (Agent Skills)

- **Action-skills only**. Workflow-templates для конкретной операции (`devlog`, `update-plan-progress`). Self-описывающие skills (повторяют CLAUDE.md о role main thread'а) — anti-pattern.
- **Frontmatter required**: `name` (lowercase, hyphens, ≤64 chars), `description` (когда применять, обязательно включать trigger-контекст).
- **Optional**: `allowed-tools`, `model`, `paths` (glob для auto-load), `disable-model-invocation`, `user-invocable`.
- **SKILL.md ≤500 строк**. Длинный reference content — в `references/` subfolder, читается on-demand.
- **Skill-creator** — через marketplace plugin (`anthropics/skills`), не форкается локально.
- Source: [Skills documentation](https://docs.claude.com/en/docs/claude-code/skills).

## Hooks

- **Use hook когда action must happen every time с zero exceptions**. *«Unlike CLAUDE.md instructions which are advisory, hooks are deterministic and guarantee the action happens»* — Best Practices.
- **Block-at-decision (PreToolUse), не block-at-write**. PreToolUse инспектирует tool input до execution; `UserPromptSubmit` — инспектирует user prompt content. Avoid blocking mid-thought.
- **Event types в harness'е**: `SessionStart` (session-context inject), `Stop` (stop-validation, advisory), `PreToolUse` (loop-protected-guard при LOOP_MODE), `UserPromptSubmit` (cost-warn). Claude Code определяет **30** hook-событий (полный срез — `~/.claude/skills/claude-code-harness/references/native-capabilities.md`); harness использует 4. Глобальный `system-guard.sh` (PreToolUse, DENY catastrophic) — user-level.
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

- **Permissions model** (3-layer, evaluated `deny` → `ask` → `allow`): `Tool`, `Tool(command *)`, `Tool(regex:pattern)`, `MCP(server:tool)`. Native hardening 2.1.160–166 расширяет слой (ручной deny остаётся минимальным): glob в deny-tool-name (`"*"`), `WebFetch(domain:)` override preapproved-хостов, `~`/`$HOME`-path deny также блокирует Bash, Read-deny прячет из Glob/Grep, `acceptEdits` спрашивает перед code-executing config-файлами (`.npmrc`/`.bazelrc`/`.devcontainer/` …).
- **defaultMode**: `default` / `plan` (review-before-execute) / `auto` (classifier-based) / `acceptEdits` (rare) / `dontAsk` (production scripts) / `bypassPermissions` (explicit intent).
- **Settings hierarchy**: local > project > user > managed-policy. Arrays concat, objects deep-merge.
- **Quarantine pattern для untrusted-content fan-out** ([«A harness for every task»](https://claude.com/blog/a-harness-for-every-task-dynamic-workflows-in-claude-code)): в triage/research workflow'ах субагенты, читающие untrusted public content (web / issues / email), **лишаются high-privilege действий** — acting выполняют отдельные субагенты. Privilege-separation против prompt-injection; применять, когда fan-out обрабатывает недоверенный вход.
- **Security boundary этого harness'а**: permissions whitelist (deny/ask/allow) + глобальный `system-guard.sh` (PreToolUse, DENY catastrophic команд — verified: заблокировал `rm -rf` в devlog #50). Secret-detection и обычные safety checks делает сам Opus 4.8 нативно — не дублируются harness-скриптом (см. memory `native_capabilities_take_precedence`). OS-level sandbox optional.
- Source: [Settings documentation](https://docs.claude.com/en/docs/claude-code/settings).

## Testing & verification

- **Verification universal, TDD opt-in**. 2026 Anthropic reframe: TDD — один из методов verification, не invariant. *«Give Claude a way to verify its work — this is the single highest-leverage thing you can do»* — Best Practices.
- **TDD оправдан** для changes *«easily verifiable with unit, integration, or end-to-end tests»* — Best Practices (опт-in framing).
- 5 invariants в `.claude/rules/testing.md`: тест в той же сессии что и код / RED → GREEN / тесты рядом с кодом / один тест — одно поведение / регрессионный тест перед фиксом.
- **Address root causes, не symptoms**: *«fix the underlying issue, don't suppress the error»* — Best Practices.

## Documentation

- **CLAUDE.md как indexer, не store**. Ссылается на `docs/ARCHITECTURE.md` / `docs/CODE-MAP.md` / `docs/GLOSSARY.md` (project layer); `.claude/docs/` (harness layer); `.claude/rules/` (always-loaded invariants). Цель: ≤200 строк.
- **Project docs layout** (bootstrap нативно под Opus 4.8 — рычаг `WORKFLOW.md` §3 + `docs-discipline.md`): `docs/ARCHITECTURE.md`, `docs/CODE-MAP.md`, `docs/GLOSSARY.md`, `docs/CONVENTIONS.md`, `docs/ADR/`, `docs/RUNBOOKS/`. Read-before-write — каждый doc отражает реальное состояние, не template.
- **Harness docs** (этого pack'а): `.claude/docs/principles.md` (этот файл, current state), `workflow.md`, `multi-agent.md`, `benchmark.md`. Archive layer (`.claude/docs/archive/`) — frozen historical snapshot.
- **Live vs archive**: active docs редактируются inline для evolve; archive — frozen, изменяется только через structural migrations.
- 6 invariants в `.claude/rules/docs-discipline.md`: doc-with-code rule / CLAUDE.md как indexer / live vs archive / owner+last-updated / glossary first-use / ADR для non-trivial decisions.

## Process

- **Plan → Work → Review** — canonical Anthropic baseline. Plan mode (`--permission-mode plan` / Shift+Tab×2) для architectural changes до writes. Skip для trivial fixes. Full workflow — `.claude/docs/workflow.md`.
- **`/review` built-in** — local, free, instant — для inner-loop. `claude ultrareview` (managed multi-agent cloud review) — для high-stakes gates.
- **Auto mode не drop-in для review**. *«Auto mode is not a drop-in replacement for careful human review on high-stakes infrastructure»* — Anthropic Engineering.
- **Single-incident NOT invariant**. Pattern требует multi-source evidence или повторяющейся empirics перед фиксацией как rule.
- **Pilot validation для harness changes**: Tier 0 (static, <10s, blocker) → Tier 1 (pilot project task suite) → Tier 2 (per-component evals). Methodology — `.claude/docs/benchmark.md`.
- **Empirical cost envelope** (2026-05-11, devlog #24; **4.7-era — re-measure due под 4.8**): на T01/T02 simple tasks our harness даёт +24-27% cost vs no-harness baseline под Opus 4.7 при идентичном quality. ECC raw inject ≈ neutral, но ломает pytest discovery через 90+ parasitic tests. cwc-long-running-agents +46% cost — opt-in для long-running fixed-spec scenarios. Re-measure trigger (major model upgrade) наступил с 4.7→4.8: первый 4.8-замер (n=1, devlog #52) на low-exploration text2sql — harness = pure overhead (×2.6 cost, ×2 turns через Task-ceremony), quality tie (score-дельта 81 vs 87 — внутри Ollama-шума, одна F-Q). Направленно подтверждает axis «ROI ∝ exploration cost». Полный n=3 verdict pending.
- **Self-improvement Ralph-loop** (2026-05-11, devlog #26/#27): empirical evolution цикл harness'а через variance-checked fitness function + retire-bias + protected-files guard. Pattern adapted from [Mishra-Sharma «Long-running Claude» (Mar 2026)](https://www.anthropic.com/research/long-running-Claude) + Huntley ralph-wiggum. Scaffolding `.claude/loop/`; protected files routed через proposal-only mode чтобы избежать recursive failure. Cost envelope per loop iter: \$1.30-2.50 benchmark-dominated. Smoke validation pending Bug 3 fix (external fixtures + worktrees).

## Anti-patterns

- **Multi-agent для most coding** — Anthropic explicit (single-agent — дефолт). Sequential dependency chain (A→B→C через subagents), subagent wrapper над single tool call, multi-agent для tightly-coupled pipelines. **Переизобретение оркестрации** кастомной subagent-машинерией там, где справится built-in dynamic workflow.
- **Mandatory multi-agent pipelines** (PM→Architect→Dev→QA, Generator/Evaluator за каждый sprint) — anti-pattern. Opt-in для high-stakes — допустимо.
- **Дублирование built-in subagents / capabilities** — `Explore`/`Plan`/`general-purpose`/`statusline-setup` не форкаются.
- **Self-описывающие skills** — повторяют CLAUDE.md о role main thread'а.
- **CLAUDE.md > 200 строк** — instructions lost в noise, model adherence drops.
- **Trust-then-verify gap** — *«Claude produces a plausible-looking implementation that doesn't handle edge cases. Fix: Always provide verification (tests, scripts, screenshots). If you can't verify it, don't ship it»* — Best Practices.
- **Block-at-write hooks** mid-thought (vs PreToolUse block-at-decision).
- **Fixed thinking budgets** — deprecated (adaptive thinking в Opus 4.8).
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
- [Chroma Research: «Context Rot»](https://research.trychroma.com/context-rot) — Hong/Troynikov/Huber, July 2025; 18 моделей, эмпирическое подтверждение pre-rot threshold
- [Phil Schmid: «Context Engineering Part 2»](https://philschmid.de/context-engineering-part-2) — Manus operational data: 1M-модель деградирует на <256K; компактифицировать *до* зоны rot'а
- [Hyung Won Chung tweet](https://x.com/hwchung27/status/1943395653738287429) — *«mistake not to add structure now, mistake not to remove it later»*; structural-retire рамка для periodic harness-prune
- [How Boris uses Claude Code](https://howborisusesclaudecode.com/) — Boris Cherny (Head of Claude Code) practices; supplemental первичный источник для «тончайшая возможная обвязка» philosophy
