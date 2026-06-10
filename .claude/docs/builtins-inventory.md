---
owner: @nikitaCodeSave
last-updated: 2026-06-10
version-targeted: claude-code 2.1.170
---

# Built-ins inventory — Claude Code 2.1.170

> ⚠️ **Lab-doc, не canonical.** Каноничный current-срез built-ins (Opus 4.8 / v2.1.169: 5 субагентов, dynamic workflows, agent teams, effort default `high`, `ultracode`) — `~/.claude/skills/claude-code-harness/references/native-capabilities.md`. Этот файл сохранён ради CC-2.1.x slash-command/flag-детализации; ядро таблиц = 2.1.143-snapshot (Opus 4.7), а дельты 2.1.144→170 вынесены в [§ Delta 2.1.144 → 2.1.170](#delta-211144--211170). Pending consolidation.
>
> Live snapshot того, что Claude Code 2.1.143 даёт «из коробки». **Versioned doc** — переписывается каждый minor release (см. [§ Re-evaluation triggers](#re-evaluation-triggers)).
>
> Источники verification: `claude --version`, `claude --help`, `claude --print "/help"`, GitHub release notes v2.1.139→143, [code.claude.com/docs/en/*](https://code.claude.com/docs/en/).

## TL;DR

Inventory из 4 слоёв:
1. **Slash-commands** (`/foo` interactive) — 22 core + 8 Research Preview + plugin-provided
2. **CLI flags & subcommands** (`claude --flag` / `claude subcommand`) — 35+ flags, 9 subcommands
3. **Built-in tools** (deferred — load via `ToolSearch select:`) — Task*/Cron*/Send*/Schedule*/Team*/Enter*Worktree/LSP
4. **Built-in agents** (`Agent({subagent_type})`) — Explore / Plan / general-purpose / statusline-setup / **claude-code-guide** (5 в v2.1.154+; dynamic workflows (keyword `ultracode`) + agent teams `TeamCreate` добавлены post-2.1.143)

Marketplaces установлены: `anthropics/skills`, `anthropics/claude-plugins-official` (**renamed** from `claude-code-plugins`), `chrome-devtools-plugins`, `firebase`.

---

## Delta 2.1.144 → 2.1.170

Ядро таблиц ниже — 2.1.143-snapshot. Что изменилось к 2.1.170 (canonical current срез — `native-capabilities.md`):

- **Built-in subagents:** типов по-прежнему **5** (новых не добавлено). `/agents` = "Manage agent configurations" (типы), `claude agents` = "Manage background agents" (sessions) — не путать.
- **Dynamic workflows** (research preview, v2.1.154+): trigger keyword **`workflow` → `ultracode`** (2.1.160) — голое "workflow" больше не триггерит; `/config` "Workflow keyword trigger" toggle (2.1.157).
- **Hooks:** `Stop`/`SubagentStop` могут вернуть `hookSpecificOutput.additionalContext` (feed-and-continue без error-label, 2.1.163); `if: "Bash(...)"` больше не over-fire на `$()`/`$VAR`.
- **Slash:** `/plugin list [--enabled|--disabled]` (2.1.163); autocomplete-клик теперь **заполняет** строку, не запускает сразу (Enter to run, 2.1.162); `/effort` подтверждает persistence.
- **CLI flags:** `--fallback-model` теперь и в interactive (2.1.166); `--tools` с явными `Grep`/`Glob` реально включает dedicated search tools (2.1.162); `claude agents --json` добавил `waitingFor`; `--agent <name>` override для dispatched sessions, `claude plugin init <name>` (2.1.157).
- **settings.json:** `fallbackModel` (до 3 ordered, 2.1.166); managed `requiredMinimumVersion`/`requiredMaximumVersion` (2.1.163); `agent` field honored для `claude agents` (2.1.157).
- **Permissions hardening:** glob в deny-tool-name (`"*"`, 2.1.166); `WebFetch(domain:)` override preapproved hosts (2.1.162); `~`/`$HOME`-path deny также блокирует Bash (2.1.163); Read-deny прячет файлы из Glob/Grep (2.1.162); `acceptEdits` спрашивает перед code-executing config-файлами + shell-startup (2.1.160).
- **Fan-out:** упавший Bash в parallel-batch не отменяет siblings (2.1.161); cross-session `SendMessage` relay не несёт user-authority (2.1.166).
- **MCP:** `claude mcp` не печатает secrets (2.1.161); per-server `timeout` < 1000 ms больше не abort'ит каждый call (2.1.162).
- **Plugins:** в `.claude/skills` авто-загрузка без marketplace (2.1.157).
- **2.1.169 (Jun 8):** `--safe-mode` / `CLAUDE_CODE_SAFE_MODE` (старт с отключёнными CLAUDE.md/plugins/skills/hooks/MCP — clean A/B baseline для «модель vs harness»); `disableBundledSkills` / `CLAUDE_CODE_DISABLE_BUNDLED_SKILLS` (прячет bundled skills/workflows/built-in slash-команды от модели — context-budget); `/cd` (смена cwd без слома prompt-cache); `claude agents --json` теперь включает blocked/just-dispatched + поля `id`/`state`, флаг `--all` для completed; background-сессии заранее знают, что shared-checkout edits заблокированы до `EnterWorktree`; порог «CLAUDE.md too long» масштабируется от context-window модели; untrusted project settings не могут задать OTEL client-cert path без trust-confirmation; `/workflows` открывается mid-turn.
- **2.1.170 (Jun 9):** релиз **Claude Fable 5** (Mythos-class, доступ с этой версии); фикс несохранявшихся транскриптов при запуске из VS Code integrated terminal / shell с унаследованными CC env-vars. Harness-relevant изменений нет; workflow-доки, таргетящие 2.1.169, остаются валидными. Fable 5 vs Opus 4.8 A/B (2026-06-09, 3 задачи): ничья — blanket-switch модели не делаем.

---

## Slash-commands (interactive)

### Core (always available)

| Command | Purpose | Notes |
|---------|---------|-------|
| `/help` | Help index | |
| `/clear` | Clear conversation | |
| `/compact [hint]` | Manual compaction with hint | Better than auto-compact at ~50% fill |
| `/init` | Scaffold project CLAUDE.md from repo state | Reads `.cursorrules`/`.windsurfrules` для interop |
| `/config` | Open settings UI | |
| `/model` | Switch model for session | |
| `/effort [low\|medium\|high\|xhigh\|max]` | Effort tier | Opus 4.8 default = `high` (4.7 было `xhigh`); `ultracode` = xhigh + auto dynamic-workflow |
| `/fast` | Toggle fast-mode (faster output, **не** downgrade) | Opus by default; repriced ~3× cheaper на 4.8 |
| `/agents` | Built-in agents browser | |
| `/cost` | Session $ usage | |
| `/status` | Session/system status | |
| `/usage` | Usage limits | New in week 16 |
| `/review` | Local codebase-aware review | Per substantive change |
| `/security-review` | Local security scan | For security-sensitive PR |
| `/memory` | Memory management UI | NEW: auto-memory + CLAUDE.md surfacing |
| `/export` | Export transcript | |
| `/resume [id\|prefix]` | Resume session | Accepts PR URLs in week 18 |
| `/add-dir` | Add directory at runtime | Runtime `--add-dir` equivalent |
| `/mcp` | MCP server config | |
| `/vim` | Toggle vim mode | |
| `/bug` | Report bug | |
| `/doctor` | Check installation | |
| `/login` / `/logout` | Auth | |

### Research Preview (v2.1.139-141 era)

| Command | Purpose | First seen | Notes |
|---------|---------|------------|-------|
| `/goal` | Goal с completion conditions, auto-continue across turns | v2.1.141 (2026-05-13) | "Higher-order prompt" pattern (Cherny). Honors `disableAllHooks` в w16 fix. **Research Preview.** |
| `/btw` | Dismissible side-question overlay | week 16 | Never enters conversation history |
| `/ultraplan` | Cloud planning (3 A/B variants Simple/Visual/Deep) | v2.1.92-101 | Subscription-only; out of scope on Bedrock/Vertex/Foundry |
| `/ultrareview` | Cloud bug-hunting fleet | week 17 | ~$15-25 per run; multi-agent |
| `/autofix-pr` | Toggle auto-fix loop на Claude-on-web | week 15 | CI integration |
| `/loop` | Self-pacing recurring task (interval picks Claude) | week 15 | Replaces manual cron для многих cases |
| `/feedback` | Session attach for feedback report | v2.1.141 | |
| `/team-onboarding` | Generate teammate ramp-up from local usage | week 15 | |

### Plugin-provided (require `claude plugin enable`)

Marketplace **`anthropics/claude-plugins-official`** (Anthropic-authored). Не enabled по умолчанию в этом harness — активируем per task.

| Plugin | Commands | When to enable |
|--------|----------|----------------|
| `feature-dev` | `/feature-dev [description]` | **Structured 7-phase feature workflow** (Discovery → Exploration → Architecture → Impl → Review → ...) с `code-explorer` / `code-architect` / `code-reviewer` agents. Author: Sid Bidasaria (Anthropic) |
| `ralph-wiggum` | `/ralph-loop`, `/cancel-ralph` | Canonical Ralph loop ([Mishra-Sharma 2026](https://www.anthropic.com/research/long-running-Claude)). Sequential iterative refinement с stop-hook |
| `commit-commands` | `/commit`, `/commit-push-pr`, `/clean_gone` | Git commit/PR helpers |
| `pr-review-toolkit` | (multiple) | Local PR review beyond `/review` |
| `agent-sdk-dev` | (dev helpers) | When building plugins/skills |
| `plugin-dev` | (plugin lifecycle) | When authoring custom plugins |
| `frontend-design` | (UI helpers) | Frontend-specific |
| `hookify` | (hook scaffolding) | When writing new hooks |
| `security-guidance` | (security checklists) | Security-sensitive PR (alt to built-in `/security-review`) |
| `code-modernization` | (legacy refactor) | **NEW (May 11)** — patches legacy code via diff, не editing |
| `pyright-lsp`, `kotlin-lsp`, `jdtls-lsp` | LSP integration | Language-specific symbol intelligence |
| `context7` | docs lookup | Library documentation queries |
| `skill-creator` | `/skill-creator` | When authoring new skills |

**Current state in этом harness'е**: `context7`, `pyright-lsp`, `skill-creator` enabled. Activate другие per-task через `claude plugin enable <name>@claude-plugins-official`.

---

## CLI flags

### Session configuration
- `--model <name>` — model alias (`opus`/`sonnet`/`haiku`) or full ID
- `--effort <low|medium|high|xhigh|max>` — effort tier
- `--agent <name>` — preset agent for session
- `--agents <json>` — inline custom agents без файла: `'{"reviewer": {"description":"...", "prompt":"..."}}'`
- `--add-dir <dirs...>` — additional directory access
- `--allowedTools` / `--disallowedTools` — fine-grained tool gating: `"Bash(git *) Edit"`
- `--system-prompt[-file]` / `--append-system-prompt[-file]` — override/append system prompt
- `--permission-mode <default|plan|acceptEdits|dontAsk|bypassPermissions|auto>` — permission posture
- `--ide` — IDE auto-connect on startup
- `--exclude-dynamic-system-prompt-sections` — moves env/cwd/git-status в первое user message (улучшает cache reuse)

### Headless / non-interactive
- `--print` / `-p` — single response then exit
- `--output-format <text|json|stream-json>` — structured output для piping
- `--input-format <text|stream-json>` — streaming input
- `--include-hook-events` — emit hook lifecycle events (stream-json only)
- `--include-partial-messages` — partial chunks (stream-json only)
- `--json-schema <schema>` — structured output validation (JSON Schema)
- `--max-budget-usd <amount>` — **API-key only, out of scope** per [api-constraint.md](../rules/api-constraint.md)

### Session lifecycle
- `--continue` / `-c` — continue most recent session in cwd
- `--resume [id]` / `-r` — resume by ID, picker, or **PR URL** (week 18)
- `--from-pr [n|url]` — resume session linked to PR
- `--fork-session` — create new session ID instead of reusing original
- `--session-id <uuid>` — explicit session ID
- `--no-session-persistence` — disposable (only with `-p`)
- `-n, --name <name>` — display name (in prompt box / picker / terminal title)

### Worktree / orchestration
- `--worktree [name]` / `-w` — create git worktree for session
- `--tmux` / `--tmux=classic` — tmux pane (with `--worktree`)
- `--remote-control [name]` — Remote Control session
- `--remote-control-session-name-prefix <prefix>` — name auto-prefix
- `--brief` — enable `SendUserMessage` (agent-to-user communication)

### Plugins / MCP
- `--plugin-dir <path>` — load plugin from disk (repeatable, `.zip` supported в w18)
- `--plugin-url <url>` — fetch plugin .zip from URL (w18)
- `--mcp-config <files...>` — MCP server config
- `--strict-mcp-config` — only --mcp-config, ignore others

### Misc
- `-d, --debug [filter]` — debug mode (e.g., `"api,hooks"`, `"!1p,!file"`)
- `--debug-file <path>` — debug log file
- `--bare` — minimal mode (**API-key only**, out of scope)
- `--betas <betas...>` — beta headers (**API-key only**, out of scope)
- `--tools <tools...>` — `""` (disable all), `"default"`, or comma-list

---

## CLI subcommands

| Subcommand | Purpose | Key options |
|------------|---------|-------------|
| `claude agents` | Manage background agents | `--add-dir/--settings/--mcp-config/--plugin-dir/--permission-mode/--model/--effort/--dangerously-skip-permissions` (**all added in v2.1.142**) |
| `claude auto-mode` | Inspect classifier config | `config` / `critique` / `defaults` |
| `claude doctor` | Health check + auto-updater | |
| `claude mcp` | MCP server config CLI | |
| `claude plugin` (= `plugins`) | Plugin lifecycle | `install/list/details/disable/enable/uninstall/update/marketplace/tag/validate/prune` |
| `claude project` | Project state lifecycle | `purge` (delete transcripts/tasks/file-history/config) |
| `claude setup-token` | Long-lived auth token | Requires Claude subscription |
| `claude ultrareview` | Cloud-hosted multi-agent code review | `[target]` = PR number / base branch |
| `claude update` / `upgrade` / `install` | Version management | |
| `claude auth` | Auth management | |

---

## Built-in tools (deferred — load via `ToolSearch select:`)

Эти не объявлены в верхнем списке tools; загружаются on-demand:

| Tool | Purpose |
|------|---------|
| `TaskCreate / TaskList / TaskGet / TaskUpdate / TaskOutput / TaskStop` | Structured task list (L0 memory layer) |
| `CronCreate / CronList / CronDelete` | Scheduled task lifecycle |
| `ScheduleWakeup` | Future-time session wake |
| `SendMessage` | Inter-agent message mid-flight |
| `TeamCreate / TeamDelete` | Team orchestration (background agents) |
| `EnterPlanMode / ExitPlanMode` | Plan-mode lifecycle (slash equivalent) |
| `EnterWorktree / ExitWorktree` | Worktree lifecycle (slash equivalent) |
| `LSP` | Symbol-level code intelligence (с `pyright-lsp` / `jdtls-lsp` / `kotlin-lsp` plugins) |
| `NotebookEdit` | Jupyter notebook editing |
| `WebFetch / WebSearch` | External research |
| `mcp__<server>__<tool>` | MCP-provided (e.g., `mcp__claude-in-chrome__*`, `mcp__plugin_context7_context7__*`) |

---

## Built-in agents (`Agent({subagent_type})`)

| Agent | Purpose | Tools |
|-------|---------|-------|
| `Explore` | Read-only research / find code | All read tools, no Edit/Write |
| `Plan` | Architect-level planning | All read tools, no Edit/Write |
| `general-purpose` | Open-ended multi-step research/exec | `*` |
| `statusline-setup` | UI: status line config | Read, Edit |

`claude agents` shows all + custom. **Built-ins-first** is invariant — никогда не дублировать (per [CLAUDE.md](../CLAUDE.md) «Built-ins first»).

---

## Hook events (~29 total in 2.1.143)

Verified против [code.claude.com/docs/en/hooks](https://code.claude.com/docs/en/hooks):

| Event | NEW in window | Purpose |
|-------|---------------|---------|
| `SessionStart` | | Inject context at session start |
| `UserPromptSubmit` | | Inspect prompt before model sees it |
| `UserPromptExpansion` | v2.1.139 | Inspect after `@file` expansion |
| `PreToolUse` | | Block-at-decision for tool calls |
| `PostToolUse` | | Post-tool transformation |
| `PostToolUseFailure` | v2.1.139 | Post-tool error handling |
| `PostToolBatch` | v2.1.139 | Batch of tool results |
| `Stop` | | Session-end validation |
| `PreCompact` / `PostCompact` | | Compaction lifecycle |
| `Setup` | v2.1.139 | One-time `--init-only` |
| `InstructionsLoaded` | v2.1.139 | Debug what was loaded |
| `FileChanged` | v2.1.139 | Filesystem watch |
| `CwdChanged` | v2.1.139 | Working dir change |
| `TaskCreated` / `TaskCompleted` | | `TaskCreate` lifecycle |

### Hook config — new capabilities in v2.1.139

- **`args: string[]`** — shell-free exec (safer, no tokenisation / pipes / variable expansion)
- **`continueOnBlock`** — `PostToolUse` hook feeds rejection reason back to Claude вместо stopping
- **`if:` field** uses permission-rule syntax: `"Bash(rm *)"`, `"Edit(*.ts)"`
- **`hookSpecificOutput.sessionTitle`** — `UserPromptSubmit` may set session title
- **`hookSpecificOutput.terminalSequence`** — OSC notifications без `/dev/tty`
- **`effort.level` JSON field + `$CLAUDE_EFFORT` env** — hook sees current effort tier
- **`CLAUDE_ENV_FILE`** — env persistence across Bash (SessionStart / Setup / CwdChanged / FileChanged)

---

## Memory & rules

### Memory hierarchy (per [code.claude.com/docs/en/memory](https://code.claude.com/docs/en/memory))

Precedence (highest → lowest):

1. Managed-policy CLAUDE.md (org-wide via `managed-settings.json` → `claudeMd` key)
2. Local `./CLAUDE.local.md`
3. Project `./CLAUDE.md` / `./.claude/CLAUDE.md`
4. User `~/.claude/CLAUDE.md`
5. Subdirectory CLAUDE.md (lazy-load on path touch)

**Size**: target ≤200 lines per CLAUDE.md file. `claudeMdExcludes` setting для monorepo skipping.

### Auto-memory (separate system от CLAUDE.md)

- Path: `~/.claude/projects/<slug>/memory/MEMORY.md`
- Loaded: first 200 lines / 25KB каждую сессию
- Topic files (`feedback_*.md`, `reference_*.md`, `user_*.md`) lazy-loaded by relevance
- Toggle: `autoMemoryEnabled`, env `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1`, `autoMemoryDirectory` (user-settings only — отклоняется в project/local)
- **Subagents** can have own auto-memory (per `/sub-agents#enable-persistent-memory`)

### Rules (`.claude/rules/*.md`) — first-party feature

- YAML frontmatter `paths:` для glob-scoped loading
- Без `paths:` → загружаются at launch alongside CLAUDE.md
- Native since 2.0.64+
- **Known bug** ([Issue #16853](https://github.com/anthropics/claude-code/issues/16853)): subdirectory paths-scoped rules иногда не загружаются. В этом harness обходится через full-load (no `paths:` в `testing.md`/`docs-discipline.md`/`api-constraint.md`)

### AGENTS.md interop

- `@AGENTS.md` import OR symlink CLAUDE.md → AGENTS.md
- `/init` reads `.cursorrules` / `.windsurfrules`

---

## Marketplaces

| Marketplace | Source | Notable contents |
|-------------|--------|------------------|
| `anthropics/skills` | github.com/anthropics/skills | Canonical skills; `claude-api`, `skill-creator` |
| **`anthropics/claude-plugins-official`** | github.com/anthropics/claude-plugins-official | feature-dev, ralph-wiggum, commit-commands, pr-review-toolkit, **code-modernization (NEW May 11)**, agent-sdk-dev, plugin-dev, frontend-design, hookify, security-guidance, etc. **Renamed from `claude-code-plugins` — старое имя возвращает 404** |
| `chrome-devtools-plugins` | (Chrome MCP) | `chrome-devtools-mcp` |
| `firebase` | (Firebase plugin source) | Firebase tooling |

---

## Re-evaluation triggers

Этот doc — **versioned**, не invariant. Перепиши когда:

- **Minor release** (2.1.144+) меняет slash-команды / flags / subcommands / hook events / plugin marketplace contents
- **Added/removed built-in agent** (`claude agents` diff)
- **New hook event** документировано в [code.claude.com/docs/en/hooks](https://code.claude.com/docs/en/hooks)
- **Plugin moved** между marketplaces / переименован

---

## Sources

- [github.com/anthropics/claude-code releases — v2.1.139 → 143](https://github.com/anthropics/claude-code/releases)
- [github.com/anthropics/claude-plugins-official](https://github.com/anthropics/claude-plugins-official)
- [code.claude.com/docs/en/best-practices](https://code.claude.com/docs/en/best-practices), [/memory](https://code.claude.com/docs/en/memory), [/hooks](https://code.claude.com/docs/en/hooks), [/agent-view](https://code.claude.com/docs/en/agent-view), [/sub-agents](https://code.claude.com/docs/en/sub-agents)
- [claude.com/blog/agent-view-in-claude-code](https://www.claude.com/blog/agent-view-in-claude-code) (2026-05-11)
- arXiv [2604.14228 — Dive into Claude Code](https://arxiv.org/abs/2604.14228) — independently reverse-engineered primitives map
- [Anthropic April 23 postmortem](https://www.anthropic.com/engineering/april-23-postmortem) — effort default rollback (Opus 4.7 = xhigh)
- [Code w/ Claude 2026 keynote — Simon Willison live-blog](https://simonwillison.net/2026/May/6/code-w-claude-2026/)
- [code.claude.com/docs/en/changelog](https://code.claude.com/docs/en/changelog) — per-version 2.1.155→169 (delta section)
- Live evidence: `claude --version` (**2.1.169**), `claude --help`, `claude plugin list`, `claude --print "/help"`
