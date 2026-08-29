---
owner: nikitaCodeSave
last-updated: 2026-08-29
---

# Claude Code harness principles

Active principles этого harness'а. Self-contained, evidence-based на canonical Anthropic Claude Code documentation 2026. Sources в конце документа.

## Foundational

- **Минимум обвязки → максимум продуктивности под способной моделью** (принцип model-agnostic — не пере-привязывай к версии; провенанс последнего re-grounding — refresh-ledger в `harness-evolution.md` кита). Anthropic: *«As models improve, developers should strip away unnecessary scaffolding rather than accumulate complexity»* — [Harness Design for Long-Running Apps](https://www.anthropic.com/engineering/harness-design-long-running-apps). Сильнейшая первопартийная эмпирика этого принципа: из системного промпта самого Claude Code **вырезано более 80%** под текущее поколение моделей «with no measurable loss on coding evaluations» — [The new rules of context engineering](https://claude.com/blog/the-new-rules-of-context-engineering-for-claude-5-generation-models). Там же назван механизм вреда: over-constraining через system prompt + CLAUDE.md + skills порождает **конфликтующие инструкции в одном запросе**.
- **Single-agent first; spawn fewer subagents by default**. Под способной моделью один main thread остаётся дефолтом для most coding. Bounded fan-out — через built-in **dynamic workflows** (keyword `ultracode`), не кастомную обвязку, и только когда scope превышает один контекст (см. Subagents).
- **Adaptive thinking; effort default `high`**. Дефолтный effort tier — `high`; `xhigh` рекомендуется для трудных и long-running async задач. Model сама decides when to reason deeply; fixed thinking budgets deprecated.
- **1M context — constraint, не resource to ignore**. *«Context rot — steady degradation of model performance as the window gets full — kicks in well before the hard limit»* — [Effective Harnesses for Long-Running Agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents). Текущее поколение заметно надёжнее на long-context и при восстановлении после compaction, но context rot сохраняется — bigger ≠ free. Эмпирический pre-rot порог ~256–400K ([Chroma «Context Rot»](https://research.trychroma.com/context-rot), operational data Manus [Phil Schmid Part 2](https://philschmid.de/context-engineering-part-2)) — **pending re-measurement на текущем поколении**; компактифицируй *до* входа в зону деградации, не у потолка. State живёт на диске (git history, devlog, MEMORY.md), не аккумулируется в context.
- **Verification — highest-leverage practice**. *«Claude performs dramatically better when it can verify its own work — run tests, compare screenshots, validate outputs. Without clear success criteria, it might produce something that looks right but actually doesn't work»* — Best Practices.
- **CLI subscription only** (harness-specific). Out of scope: managed-agents (Dreams/Outcomes/Memory stores), beta headers (`--betas`, `managed-agents-*`, `dreaming-*`), `--max-budget-usd`, prompt caching / batch / files / citations API. CLI native primitives (hooks, skills, subagents, slash commands) — единственный execution surface.

## Components inventory (current state)

- **Skills** (action-only, workflow-templates): `update-plan-progress`. Devlog — плагин `devlog@skills-dir` (скилл + `devlog-reindex` на PATH + SessionStart-дайджест), в репо не дублируется. SKILL.md ≤500 строк. Каноничное знание о дизайне harness'а — глобальный `~/.claude/skills/claude-code-harness/`. (`project-docs-bootstrap` в harness не входит — native + WORKFLOW.md §3 + docs-discipline покрывают bootstrap.)
- **Custom agents**: нет. Дубли built-in не создаются: orchestrator-роль — сам main thread, security — built-in `/security-review`, audit — `/code-review ultra` для изменения и свежая сессия для deliverable'а.
- **Built-in agents** (5): `Explore` (read-only research), `Plan` (architect-level planning), `general-purpose` (open-ended), `statusline-setup` (UI), `claude-code-guide` (вопросы про Claude Code).
- **Hooks**: проектных хуков harness не держит (ретайрены 2026-07-15 вместе с loop-кластером), глобальных своих — тоже: `system-guard` ретайрен 2026-08-29, его землю занял нативный слой (auto-mode классификатор адъюдицирует опасный `rm`, деструктивные git/IaC блокируются из коробки). Активен один внешний: `session-start-digest` (SessionStart: devlog + active-progress inject) из плагина `devlog`. Test-quality — за глобальным CLAUDE.md §5, хуком не дублируется.
- **Always-loaded rules**: `testing.md` (5 invariants), `docs-discipline.md` (7 invariants), `api-constraint.md`.
- **Reference docs** (on-demand): `workflow.md` (Plan→Work→Review spine + slice docs), `multi-agent.md`, `benchmark.md`, и др. в `.claude/docs/`.

## Subagents

- **Built-ins first**. Перед созданием custom — `claude agents`. Дублирование built-in (`Explore`/`Plan`/`general-purpose`/`statusline-setup`/`claude-code-guide`) — anti-pattern.
- **Spawn justified ТОЛЬКО**: (а) context isolation (search-heavy / broad codebase scan загрязнит main), (б) parallelism (independent verifications сходящиеся в main), (в) auto-compact rescue (редко при 1M).
- **Single-agent default; bounded fan-out когда scope превышает один контекст**. Most coding — single thread (*«Most coding tasks involve fewer truly parallelizable tasks than research»* — [Multi-Agent Research System](https://www.anthropic.com/engineering/multi-agent-research-system)). Bounded fan-out закрыт first-party примитивом — **dynamic workflows** (keyword `ultracode`, или просто попроси); по built-ins-first роутим к нему для codebase-scale sweep / миграции / trust-critical верификации (find→refute→converge), НЕ переизобретаем оркестрацию кастомной машинерией. Стоит заметно больше токенов — не дефолт; verify ROI до fan-out. First-party обоснование — [«A harness for every task» (Shihipar & Bidasaria, 2 июня 2026)](https://claude.com/blog/a-harness-for-every-task-dynamic-workflows-in-claude-code): изолированные субагенты структурно лечат три failure-mode длинных/параллельных прогонов — **agentic laziness**, **self-preferential bias** (ровно почему §8 fresh-context ≠ self-recheck), **goal drift**.
- **Subagent isolation для high-stakes — opt-in допустимо**. Patterns: Planner→Generator→Evaluator (canonical Anthropic для long tasks, Rajasekaran 2026 — теперь нативно покрывается dynamic workflows на CLI-подписке, без API), TDD triad (test-writer/implementer/refactorer), Driver-Navigator (Opus+Sonnet). Cost-threshold per Rajasekaran: *«worth the cost когда task sits beyond what current model does reliably solo»*. **Mandatory** pipeline за каждую задачу — anti-pattern.
- **Model assignment**: main/lead = топовая Opus; reasoning subagent = Sonnet-тир; grunt (file scans, log filtering) = Haiku-тир. Пин через `CLAUDE_CODE_SUBAGENT_MODEL` теперь задаёт **дефолт**, а не override — `model:` в определении агента и явная модель при spawn'е его перебивают; фактический уровень каждого делегата виден в `/tasks`. Agent teams (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`) — experimental, off by default, и включение меняет обычное делегирование: субагент, которому Claude сам дал имя, стартует как teammate.
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
- **Event types**: Claude Code определяет десятки hook-событий (точное число — только в `~/.claude/skills/claude-code-harness/references/native-capabilities.md`, единственном version-pinned файле). Собственных хуков harness не держит вовсе; активен один внешний — `session-start-digest` (SessionStart: devlog + progress inject) из плагина `devlog`.
- **Handler types**: `command` (shell + JSON), `mcp_tool`, `http`. Exit code 0 = allow, 2 = block, other = non-blocking error.
- Source: [Hooks documentation](https://docs.claude.com/en/docs/claude-code/hooks).

## Memory

- **CLAUDE.md hierarchy** (highest → lowest precedence): managed-policy → local → project (`./CLAUDE.md` / `./.claude/CLAUDE.md`) → user (`~/.claude/CLAUDE.md`). Subdirectory CLAUDE.md — lazy-loaded когда files в этой directory затрагиваются.
- **CLAUDE.md ≤200 lines**. *«If rules get lost in noise, file is too long»* — Best Practices. Длиннее — split в path-scoped `.claude/rules/*.md` или import via `@file` syntax.
- **Бюджет CLAUDE.md тратится на gotchas**: *«briefly describe what your repo is for, but spend most of the tokens on gotchas»* — [new rules of context engineering](https://claude.com/blog/the-new-rules-of-context-engineering-for-claude-5-generation-models). Всё, что сессия выведет из структуры кода (дерево каталогов, список стека, обзор архитектуры), в always-loaded слое не держим — оно уезжает в lazy skills и nested CLAUDE.md.
- **`/doctor` — нативный аудитор этого слоя**: считает неиспользуемые skills/MCP/plugins против их context-cost (по счётчикам `skillUsage`/`pluginUsage`), дедуплицирует local CLAUDE.md против checked-in, предлагает срез лишнего и миграцию в lazy skills, ловит медленные хуки. Отдельный самописный аудит-скрипт этого слоя — дублирование built-in. Смежный факт бюджета: **листинг skills занимает ~1% контекстного окна, и при переполнении описания усекаются** — раздутый листинг ломает роутинг раньше, чем упирается в стоимость токенов.
- **`@path/to/file.md` import syntax** — expanded at launch. Resolves relative к containing file. Max depth 5 hops (cycle detection enabled).
- **Auto-memory**: `~/.claude/projects/<slug>/memory/MEMORY.md` (first 200 lines / 25KB auto-loaded). Topic files (`feedback_*.md`, `user_*.md`) загружаются on-demand при relevance.
- **Curate-and-delete loop**: значимые learnings в MEMORY.md / topic files; ephemeral session-log trim. Stale (>6 months) — review.
- **State on disk, не в context**: git history, devlog entries, MEMORY.md — primary truth между сессиями.
- Source: [Memory documentation](https://docs.claude.com/en/docs/claude-code/memory).

## Settings & permissions

- **Permissions model** (3-layer, evaluated `deny` → `ask` → `allow`): `Tool`, `Tool(command *)`, `Tool(regex:pattern)`, `MCP(server:tool)`. Native hardening расширяет слой (ручной deny остаётся минимальным): glob в deny-tool-name (`"*"`), `WebFetch(domain:)` override preapproved-хостов, `~`/`$HOME`-path deny также блокирует Bash, Read-deny прячет из Glob/Grep, `acceptEdits` спрашивает перед code-executing config-файлами (`.npmrc`/`.bazelrc`/`.devcontainer/` …).
- **defaultMode**: `default` / `plan` (review-before-execute) / `auto` (classifier-based) / `acceptEdits` (rare) / `dontAsk` (production scripts) / `bypassPermissions` (explicit intent).
- **Settings hierarchy**: local > project > user > managed-policy. Arrays concat, objects deep-merge.
- **Quarantine pattern для untrusted-content fan-out** ([«A harness for every task»](https://claude.com/blog/a-harness-for-every-task-dynamic-workflows-in-claude-code)): в triage/research workflow'ах субагенты, читающие untrusted public content (web / issues / email), **лишаются high-privilege действий** — acting выполняют отдельные субагенты. Privilege-separation против prompt-injection; применять, когда fan-out обрабатывает недоверенный вход.
- **Security boundary этого harness'а**: permissions whitelist (deny/ask/allow) + нативный слой — auto-mode классификатор и встроенный блок деструктивных git/IaC. Своего guard-хука нет: он дублировал эту землю и ретайрен 2026-08-29. Deny-правило при этом **гигиена, а не containment** — против активного обхода работает sandbox (OS-level, optional). Secret-detection и обычные safety checks делает сама модель нативно — не дублируются harness-скриптом (см. memory `native_capabilities_take_precedence`).
- Source: [Settings documentation](https://docs.claude.com/en/docs/claude-code/settings).

## Testing & verification

- **Verification universal, TDD opt-in**. 2026 Anthropic reframe: TDD — один из методов verification, не invariant. *«Give Claude a way to verify its work — this is the single highest-leverage thing you can do»* — Best Practices.
- **TDD оправдан** для changes *«easily verifiable with unit, integration, or end-to-end tests»* — Best Practices (опт-in framing).
- 5 invariants в `.claude/rules/testing.md`: тест в той же сессии что и код / RED → GREEN / тесты рядом с кодом / один тест — одно поведение / регрессионный тест перед фиксом.
- **Address root causes, не symptoms**: *«fix the underlying issue, don't suppress the error»* — Best Practices.
- **Cross-vendor judge для silent-wrong класса**. Свежий контекст своего же семейства делит с автором слепые пятна; ревьюер другого вендора — нет. Codex подключён MCP-сервером (`codex_peer`), поверхность вызова заморожена в глобальном скилле `codex-mcp`, дисциплина применения — `multi-agent.md` §7.3. Эмпирика: 5 реальных дыр в `system-guard.sh` мимо 109 тестов, трёх фикс-коммитов и всех нативных проходов (devlog #127). Вывод внешнего ревьюера **триажируется и воспроизводится тестом**, не принимается на веру.

## Documentation

- **CLAUDE.md как indexer, не store**. Ссылается на `docs/ARCHITECTURE.md` / `docs/CODE-MAP.md` / `docs/GLOSSARY.md` (project layer); `.claude/docs/` (harness layer); `.claude/rules/` (always-loaded invariants). Цель: ≤200 строк.
- **Project docs layout** (bootstrap нативно под способной моделью — рычаг `WORKFLOW.md` §3 + `docs-discipline.md`): `docs/ARCHITECTURE.md`, `docs/CODE-MAP.md`, `docs/GLOSSARY.md`, `docs/CONVENTIONS.md`, `docs/ADR/`, `docs/RUNBOOKS/`. Read-before-write — каждый doc отражает реальное состояние, не template.
- **Harness docs** (этого pack'а): `.claude/docs/principles.md` (этот файл, current state), `workflow.md`, `multi-agent.md`, `benchmark.md`. Archive layer (`.claude/docs/archive/`) — frozen historical snapshot.
- **Live vs archive**: active docs редактируются inline для evolve; archive — frozen, изменяется только через structural migrations.
- 7 invariants в `.claude/rules/docs-discipline.md`: doc-with-code rule / CLAUDE.md как indexer / live vs archive / owner+last-updated / glossary first-use / ADR для non-trivial decisions / progress journal для long-running task.

## Process

- **Plan → Work → Review** — canonical Anthropic baseline. Plan mode (`--permission-mode plan` / Shift+Tab×2) для architectural changes до writes. Skip для trivial fixes. Full workflow — `.claude/docs/workflow.md`.
- **`/code-review` built-in** (`/review` — его алиас) — local, free, instant — для inner-loop. `/code-review ultra` / `claude ultrareview` (managed multi-agent cloud review) — для high-stakes gates.
- **Auto mode не drop-in для review**. *«Auto mode is not a drop-in replacement for careful human review on high-stakes infrastructure»* — Anthropic Engineering.
- **Single-incident NOT invariant**. Pattern требует multi-source evidence или повторяющейся empirics перед фиксацией как rule.
- **Pilot validation для harness changes**: Tier 0 (static, <10s, blocker) → Tier 1 (pilot project task suite) → Tier 2 (per-component evals). Methodology — `.claude/docs/benchmark.md`.
- **Empirical cost envelope** — **не перемеряно на текущем поколении** (замеры 2026-05, devlog #24/#52; читать как исторический ориентир, не как норматив): на low-exploration задачах preload-обвязка даёт чистый overhead (+24-27% cost при идентичном quality; на text2sql — ×2.6 cost, ×2 turns через Task-ceremony при tie по качеству). Направление устойчиво и совпадает с axis «ROI ∝ exploration cost»: обвязка окупается там, где дорога разведка, и проигрывает там, где задача очевидна.
- **Self-improvement Ralph-loop** (2026-05-11, devlog #26/#27): empirical evolution цикл harness'а через variance-checked fitness function + retire-bias + protected-files guard. Pattern adapted from [Mishra-Sharma «Long-running Claude» (Mar 2026)](https://www.anthropic.com/research/long-running-Claude) + Huntley ralph-wiggum. **Ретайрен 2026-07-15 (negative result)**: единственный прогон (\$72.50 / 37 iter) дал fitness ≈ +0.000, holdout-oracle ни разу не запускал pytest, accept'ы = сам loop-тулинг — single-shot micro-A/B недомерен под invocation-noise. Scaffolding архивирован в `.claude/docs/archive/loop-2026-05/`.

## Anti-patterns

- **Multi-agent для most coding** — Anthropic explicit (single-agent — дефолт). Sequential dependency chain (A→B→C через subagents), subagent wrapper над single tool call, multi-agent для tightly-coupled pipelines. **Переизобретение оркестрации** кастомной subagent-машинерией там, где справится built-in dynamic workflow.
- **Mandatory multi-agent pipelines** (PM→Architect→Dev→QA, Generator/Evaluator за каждый sprint) — anti-pattern. Opt-in для high-stakes — допустимо.
- **Дублирование built-in subagents / capabilities** — `Explore`/`Plan`/`general-purpose`/`statusline-setup` не форкаются.
- **Self-описывающие skills** — повторяют CLAUDE.md о role main thread'а.
- **CLAUDE.md > 200 строк** — instructions lost в noise, model adherence drops.
- **Trust-then-verify gap** — *«Claude produces a plausible-looking implementation that doesn't handle edge cases. Fix: Always provide verification (tests, scripts, screenshots). If you can't verify it, don't ship it»* — Best Practices.
- **Block-at-write hooks** mid-thought (vs PreToolUse block-at-decision).
- **Fixed thinking budgets** — deprecated (вытеснены adaptive thinking).
- **Vague instructions** ("be careful with X", "write clean code") — empirically ignored. Specific bans / specific verification criteria > vague guidance.

## Sources

Retrieval date: **2026-08-07**.

- [Claude Code Best Practices](https://docs.claude.com/en/docs/claude-code/best-practices) — canonical Cherny + team 2026
- [Claude Code: Sub-agents](https://docs.claude.com/en/docs/claude-code/sub-agents)
- [Claude Code: Skills](https://docs.claude.com/en/docs/claude-code/skills)
- [Claude Code: Hooks](https://docs.claude.com/en/docs/claude-code/hooks)
- [Claude Code: Memory](https://docs.claude.com/en/docs/claude-code/memory)
- [Claude Code: Settings](https://docs.claude.com/en/docs/claude-code/settings)
- [Claude Code: Common workflows](https://docs.claude.com/en/docs/claude-code/common-workflows)
- [Claude Code: Code review](https://docs.claude.com/en/docs/claude-code/code-review)
- [The new rules of context engineering for Claude 5 generation models](https://claude.com/blog/the-new-rules-of-context-engineering-for-claude-5-generation-models) — Shihipar; 80% системного промпта вырезано, gotchas-бюджет CLAUDE.md, progressive disclosure, `/doctor`
- [Prompting Claude Opus 5](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5) — не над-инструктировать верификацию; полная спека сразу; effort как единственный рычаг глубины
- [How Anthropic secures its AI-native SDLC](https://claude.com/blog/how-anthropic-secures-its-ai-native-software-development-lifecycle) — hard access boundaries; границы агента включают доступ к другим агентам
- [How we contain Claude across products](https://www.anthropic.com/engineering/how-we-contain-claude) — containment на уровне окружения раньше, чем steering на уровне модели
- [Anthropic Engineering: Multi-Agent Research System](https://www.anthropic.com/engineering/multi-agent-research-system)
- [Anthropic Engineering: Effective Harnesses for Long-Running Agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents)
- [Anthropic Engineering: Harness Design for Long-Running Apps](https://www.anthropic.com/engineering/harness-design-long-running-apps) — Rajasekaran, Mar 24 2026 (Planner→Generator→Evaluator canonical)
- [GitHub: anthropics/skills marketplace](https://github.com/anthropics/skills)
- [Chroma Research: «Context Rot»](https://research.trychroma.com/context-rot) — Hong/Troynikov/Huber, July 2025; 18 моделей, эмпирическое подтверждение pre-rot threshold
- [Phil Schmid: «Context Engineering Part 2»](https://philschmid.de/context-engineering-part-2) — Manus operational data: 1M-модель деградирует на <256K; компактифицировать *до* зоны rot'а
- [Hyung Won Chung tweet](https://x.com/hwchung27/status/1943395653738287429) — *«mistake not to add structure now, mistake not to remove it later»*; structural-retire рамка для periodic harness-prune
- [How Boris uses Claude Code](https://howborisusesclaudecode.com/) — Boris Cherny (Head of Claude Code) practices; supplemental первичный источник для «тончайшая возможная обвязка» philosophy
