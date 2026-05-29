---
id: 48
date: 2026-05-18
title: "Workflow doc split — 6-файловый layout с empirical grounding 2026 Q2"
tags: [docs, harness, refactor]
status: complete
---

# Workflow doc split — 6-файловый layout с empirical grounding 2026 Q2

## Контекст

Заменили монолитный `workflow.md` (380 строк, 2026-05-10 vintage) на тонкий spine + 5 slice docs. Старая версия дублировала Anthropic-canonical `feature-dev` plugin и игнорировала весь inventory Claude Code 2.1.143 (Monitor tool, `/goal`, dispatch flags v2.1.142, hooks v2.1.139 capabilities, plugin marketplace, cloud-offload). Empirical foundation — 2026 Q2 arXiv research-pass + first-party claude.com/blog 2026-05-14 doctrine «harness matters more than the model».

Trigger: пользователь указал на gap между нашим workflow doc и фактическими built-ins Claude Code. Запустили 3 параллельных research-агента (Anthropic first-party / community / arXiv) за окно 2026-04-18 → 2026-05-18, синтезировали Variant C split layout (vs Variant A retire / Variant B overlay).

## Изменения

**Archive**: `docs/workflow.md` → `docs/archive/workflow-2026-05-10.md` с `frozen` frontmatter и `superseded-by` listing.

**6-файловый layout** (active layer, `.claude/docs/`):

1. **`workflow.md`** (95 строк, ≤120 target ✓) — тонкий spine. Opening citation: «harness matters more than the model — review every 3-6 months» (claude.com/blog 2026-05-14). Decision tree «какой built-in для какой задачи». Compressed Plan→Work→Review. Routing к slice docs.

2. **`builtins-inventory.md`** (296 строк) — versioned inventory Claude Code 2.1.143. Включает:
   - 22 core + 8 Research Preview slash-commands (incl `/goal` v2.1.141, `/btw`, `/ultraplan`, `/ultrareview`, `/loop`, `/feedback`)
   - 35+ CLI flags (`--worktree`/`--tmux`/`--remote-control`/`--brief`/`--from-pr`/`--fork-session`/`--json-schema`/`--agents`/`--add-dir`/`--effort`)
   - 10 subcommands (`claude agents`/`auto-mode`/`plugin`/`project`/`ultrareview` etc.)
   - 11 deferred tools (Task*/Cron*/Send*/Schedule*/Team*/Enter*Worktree/LSP/NotebookEdit/WebFetch/WebSearch/MCP)
   - 4 built-in agents (Explore/Plan/general-purpose/statusline-setup)
   - 29 hook events с v2.1.139+ NEW markers (Setup/UserPromptExpansion/PostToolUseFailure/PostToolBatch/InstructionsLoaded/FileChanged/CwdChanged)
   - Plugin marketplace (renamed `claude-code-plugins` → `claude-plugins-official`, table с feature-dev/ralph-wiggum/commit-commands/pr-review-toolkit/code-modernization NEW May 11)

3. **`workflow-async.md`** (220 строк) — Monitor tool (v2.1.98+) как dominant primitive replacing bash sleep loops. Task*/Cron*/ScheduleWakeup/SendMessage. `/loop` self-pacing. Routines (Cherny terminology). Decision tree.

4. **`workflow-orchestration.md`** (239 строк) — worktree (`-w`/`--tmux`/`baseRef`/`bgIsolation`), `claude agents` dispatch flags v2.1.142 (`--add-dir`/`--settings`/`--mcp-config`/`--plugin-dir`/`--permission-mode`/`--model`/`--effort`/`--dangerously-skip-permissions`), agent-view, session lifecycle (`--remote-control`/`--from-pr`/`--fork-session`/`--brief`). Cites arXiv 2604.18071 70-project survey: multi-level recursive subagent = 12.9% корпуса — наша restraint = deliberate.

5. **`workflow-cloud-offload.md`** (188 строк) — `/ultraplan` (3 A/B variants Simple/Visual/Deep), `/ultrareview` cloud bug-hunting fleet, Routines (cron/GitHub-event/API-triggered). API constraint check: subscription only, Bedrock/Vertex/Foundry incompatible. Reframes meta-orchestrator role: picks local CLI vs cloud fleet per phase.

6. **`workflow-evolution.md`** (147 строк, ≤150 target ✓) — empirical-grounded measurement loop. AHE (arXiv 2604.25850): gains от tools/middleware/memory NOT prompts (ablation). AgentFlow (2604.20801): «changing only harness → several-fold delta». SLIM (2605.10923): retire-bias for skills — identified gap (нет retire ritual у нас). 70-project survey context. Cadence: 3-6 month review.

**Updates**:
- `CLAUDE.md` indexer — 123 строки (≤200 invariant ✓). Заменена единая ссылка на `workflow.md` блоком из 6 docs.
- `external-sources.md` — 5 параллельных Edit'ов добавили: april-23-postmortem, managed-agents, large-codebases blog, cybersecurity blog, Code w/ Claude 2026, TechCrunch Cat Wu, Every podcast, 6 новых arXiv (AHE/AgentFlow/Dive into Claude Code/70-project/SLIM/TDD-Governance), release notes v2.1.133-143.
- Auto-memory — 5 новых reference entries:
  - `reference_monitor_tool_replaces_polling.md`
  - `reference_paths_frontmatter_rules.md`
  - `reference_hooks_v2_1_139_capabilities.md`
  - `reference_plugin_marketplace_rename.md`
  - `reference_harness_evolution_papers.md`
  - MEMORY.md index updated.

**Foundational shift**: doc structure теперь mirrors operational layers (sync / async / orchestration / cloud / evolution), вместо single canonical «Plan→Work→Review». Empirical grounding в каждом slice.

## Затронутые файлы

**Created (new)**:
- `.claude/docs/builtins-inventory.md` — versioned inventory 2.1.143
- `.claude/docs/workflow-async.md` — async/background primitives
- `.claude/docs/workflow-orchestration.md` — worktree/dispatch/orchestration
- `.claude/docs/workflow-cloud-offload.md` — cloud-side phases
- `.claude/docs/workflow-evolution.md` — measurement-driven evolution
- `.claude/progress/workflow-rewrite-2026-05-18.md` — journal (post-merge → delete per docs-discipline rule 7)
- `~/.claude/projects/<slug>/memory/reference_monitor_tool_replaces_polling.md` (+ 4 более)

**Modified**:
- `.claude/docs/workflow.md` — полностью переписан как thin spine (380 → 95 строк)
- `.claude/CLAUDE.md` — Reference materials section updated
- `.claude/docs/external-sources.md` — 5 secs extended
- `~/.claude/projects/<slug>/memory/MEMORY.md` — 5 new index entries

**Moved**:
- `.claude/docs/workflow.md` → `.claude/docs/archive/workflow-2026-05-10.md` (с `status: frozen` frontmatter)

## Проверка

```bash
bash .claude/benchmark/static-checks.sh
# === ALL AUTOMATED CHECKS PASSED (16/16) ===

wc -l .claude/docs/workflow*.md .claude/docs/builtins-inventory.md .claude/CLAUDE.md
# CLAUDE.md = 123 (≤200 invariant ✓)
# workflow.md = 95 (≤120 target ✓)
# workflow-evolution.md = 147 (≤150 target ✓)
# others 188-296 (slice docs не invariant-bound)
```

Slice docs не подпадают под `≤200` invariant — этот invariant из docs-discipline rule 2 применяется к CLAUDE.md hierarchy specifically («if rules get lost in noise»). Slice docs грузятся on-demand при работе с конкретным слоем.

## Related

- #43 — harness-setup team-ready (3 iterations) — predecessor major doc work
- archived `workflow-2026-05-10.md` — frozen baseline для empirical comparison
- 5 new auto-memory reference entries — point-in-time snapshot 2.1.143 inventory
