# Native capabilities — what Claude Code already does

**Model lines as of Claude Code v2.1.280 (2026-09-22); every other built-in below carries the
older v2.1.251 / 2026-08-29 stamp** — see "Two stamps" below before treating a non-model claim
here as current.

Current lineup [FP, models overview]: the **Claude 5 family** — Fable 5.1, Opus 5.5, Sonnet 5
(plus Mythos 5.1 where an access program grants it) — and **Haiku 4.5**, which is current but of
the earlier 4.5 generation and supports no effort setting. Default model is
account-type-dependent [FP, `model-config`]: **Opus 5.5** (`claude-opus-5-5`, v2.1.280+ — now
*the* default Opus model; 1M context / 128K max output, $4/$20 MTok with $0.20 cache reads,
reliable knowledge cutoff Jun 2026, **default effort `medium`** where Opus 5's was `high`) on
**Pro, Max, Team, Enterprise and the Anthropic API** — Pro and Team Standard started on Sonnet 5
until v2.1.280 — and on Claude Platform on AWS / Bedrock / Google Cloud; **Microsoft Foundry
still defaults to Sonnet 4.5**. **Fable 5.1** (`claude-fable-5-1`, v2.1.257+ — the default
*Fable*; $10/$50 MTok, $0.25 cache reads, cutoff Jun 2026) is the default of no account type
(`/model fable`). Opus 5 and Fable 5 are **legacy** [FP, models overview] — still served, no
longer any plan's default, and Fable 5 is still what `fable` / `best` resolve to in Claude apps
gateway sessions until a gateway is configured for 5.1. `ANTHROPIC_DEFAULT_MODEL`
(v2.1.236) sets what new sessions start on — unlike `ANTHROPIC_MODEL` a `/model` pick still
overrides it and persists; `modelPicker` (v2.1.243) curates the `/model` list itself.

The point of this file: a harness must not reinvent a built-in. Before writing
any custom subagent, hook, skill, or command, confirm the need is not already covered here.
Re-verify with `claude --version` and `/help` — versions drift, and **a tool's absence from
your session's live inventory is an env/profile fact, not product truth** (gating: provider,
telemetry flags, experimental env vars).

**This file is the kit's single version-pinned document.** Every other live doc states
behavior without binding it to a release and points here — a currency pin duplicated in two
places goes stale in one of them silently (`audit-checklist.md` §1 carries the detector).

**Two stamps, not one.** The v2.1.280 header covers the **model lines only** — lineup, plan
defaults, per-model effort defaults, fast mode (re-grounded 2026-09-22). Every other built-in
below was last swept at **v2.1.251 / 2026-08-29**, so treat a non-model claim as carrying that
older stamp until the functional 2.1.252→2.1.280 pass runs (`harness-evolution.md`'s refresh
ledger states both).

Trust legend: **[FP]** first-party docs (code.claude.com / platform.claude.com / anthropic.com),
**[BLOG]** Anthropic blog. Everything below is usable on the CLI subscription (Max/Team/Pro/
Enterprise) unless flagged **API-only** or plan-gated.

## Built-in subagents (5)

The five built-in subagent **types** you must not recreate (source:
`code.claude.com/docs/en/sub-agents`). **`/agents` no longer opens an interactive
wizard** — running it prints a reminder to ask Claude or edit `.claude/agents/` directly;
inspect configured agents via **`/context`** ("Custom Agents"; `/doctor` flags duplicate names). Do **not** confuse either with the CLI subcommand
`claude agents` ("Manage background agents" = list running *sessions*), which does not
enumerate types:

- **Explore** [FP] — read-only codebase search; **since v2.1.198 inherits the main
  conversation's model (capped at Opus)** instead of always running on Haiku; thoroughness
  level (quick / medium / very thorough); skips CLAUDE.md + git status. Use for broad
  fan-out searches.
- **Plan** [FP] — read-only research agent used in plan mode; inherits the main model.
  Plan mode itself (`Shift+Tab`×2 or `--permission-mode plan`) is the read-only-recon
  surface; the Plan agent is its research delegate.
- **general-purpose** [FP] — full-tool, multi-step explore + modify; loads CLAUDE.md + git.
  This is the orchestrator-grade delegate; do **not** clone it into a custom "orchestrator".
- **statusline-setup** [FP] — Sonnet; runs on `/statusline`.
- **claude-code-guide** [FP] — Haiku; answers questions about Claude Code itself.

A sixth *surface* exists but is not a specialist to recreate: the built-in catch-all
**`claude`** agent — the default type for background dispatch / agent view when no agent
name is given (`code.claude.com/docs/en/agent-view`); a dispatch default, not a role.

Subagents can nest — **depth 3 by default** (v2.1.219; nesting was turned *off* by default in
v2.1.217, and the older 5-level figure predates that), tunable via
`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` (`=1` disables nesting). Fan-out has **native caps** —
do not re-encode them as a guard hook: **20 concurrent subagents**
(`CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`) and **200 WebSearch calls per session**
(`CLAUDE_CODE_MAX_WEB_SEARCHES_PER_SESSION`). The former **200-spawns-per-session** cap has been
**removed** — a long session no longer starts refusing new agents (concurrency and depth still
apply), so a harness that worked around it by `/clear`-ing can drop that workaround. Only Explore and Plan
omit CLAUDE.md + git context; both are one-shot (no resume). First-party subagent primitives
you should not rebuild by hand: the **in-session forked subagent `/subtask`** (inherits the
full conversation, reuses the prompt cache) — **`/fork` is no longer this**: since v2.1.212 it
copies the conversation into a *background* session with its own row in `claude agents`, so a
harness step that expected an in-session fork must say `/subtask`. One conditional worth knowing:
**with agent view turned off `/subtask` does not exist and `/fork` starts the forked subagent
instead** — a harness that hard-codes one name breaks on the other configuration. **Worktrees differ between the two, and the isolation is an explicit act, not a property of the
spawn.** A `/fork`ed background copy **starts in the original checkout with its edits blocked**
and is instructed to call **`EnterWorktree`** before changing code; isolation exists only once
that call succeeds — `bgIsolation: "worktree"` (the default) blocks Edit/Write in the main
checkout until `EnterWorktree` is called. Isolation is skipped when: the session already sits in a
linked worktree (one Claude created under `.claude/worktrees/`, **or one you made with
`git worktree add`**); the file being edited is inside a linked worktree; the working directory is
not a git repository and there is no `WorktreeCreate` hook; or the write targets a path **outside
the working directory**. Separately, `worktree.bgIsolation: "none"` turns the whole mechanism off
for repos where worktrees are impractical.
`/subtask`, the in-session form, shares the session's checkout. Do not read a spawn-time probe as
evidence here: an empty worktree field at T0 is what a not-yet-called `EnterWorktree` looks like,
so the observation cannot support a claim about the agent's whole life. For a delegate that must
be isolated *by construction* rather than by instruction, the `isolation: worktree` frontmatter
field below is still the deterministic lever. **Since v2.1.232 the Agent tool takes `subagent_type: "fork"` and forking is on by
default**: such a delegate inherits the full conversation *and the prompt cache*, which makes it
the cheap way to hand off a side task that needs everything you already know — the briefing cost
that makes a fresh delegate expensive is simply absent. The same release made non-teammate agent
spawns in interactive sessions **background by default**. Note the boundary against
independent verification: a fork inherits the author's framing by construction, so it is the wrong
shape for an independent refuter and the right one for "keep working on what we were just doing". Frontmatter
`maxTurns`, `isolation: worktree` (auto-cleaned branch-off), `memory: user|project|local`
(**persistent per-agent memory**, each scope writing to its own root:
`~/.claude/agent-memory/<agentType>/`, `.claude/agent-memory/<agentType>/`, and
`.claude/agent-memory-local/<agentType>/`), and `experimental.cacheTtl`
(`"5m"` / `"1h"`, v2.1.248 — a per-agent prompt-cache TTL used when no subagent TTL setting is
configured; the settings-level pair is `promptCacheTtl` / `subagentPromptCacheTtl`, v2.1.243).
Disable a built-in via
`permissions.deny: ["Agent(Explore)"]`; `Agent(x,y)` allowed-type lists are **enforced**, and
background subagents **prompt for permission in the main session** rather than auto-denying (v2.1.186).

**`CLAUDE_CODE_SUBAGENT_MODEL` sets the *default* subagent model, and v2.1.251 is what made it
so** — the release note is explicit: "Changed `CLAUDE_CODE_SUBAGENT_MODEL` to set the default
subagent model rather than override everything: an agent definition's `model:` and an explicit
per-spawn model now take precedence over it." So the order is **per-spawn model ▸ definition's
`model:` ▸ this variable ▸ the parent's model**, and `inherit` disables the default outright.
A harness that pinned delegate models through this variable was silently re-layered by the
upgrade: what it used to force it now only suggests. **Note the source conflict** — *three* docs
pages (`model-config`, `workflows`, `agent-teams`) still describe the pre-2.1.251 override
semantics, and the changelog for the version you are running is the newer of them all. That a
stale claim survives on several pages at once is why the page count is not the tiebreaker. Read a delegate's actual model
off `/tasks` rather than trusting either document.

## Dynamic workflows — the bounded fan-out primitive [FP/BLOG]

The `ultracode` keyword (or `/effort ultracode`, or simply asking) makes Claude write a JS
orchestration **script** the runtime executes in the background. The script holds the plan,
the loop, the branching, and intermediate results; **only the final answer enters Claude's
context.** Requires v2.1.154+; available on all paid plans — **on Pro it is off by default**,
enable via the `/config` "Dynamic workflows" row. The trigger keyword is `ultracode` — the
bare word "workflow" does not trigger a run (asking in your own words does); a `/config`
"Ultracode keyword trigger" toggle exists.

- Constructs: loops, conditionals, `pipeline()`, `parallel()`, `phase()`, `agent()` (with
  output schemas), arguments, budgets, retries.
- Caps: **up to 16 concurrent agents** (fewer on low-CPU machines), **1,000 agents total per run**.
- Spawned agents inherit your tool allowlist and follow the **ordinary subagent permission
  rules** — a parent in `acceptEdits`/`bypassPermissions` wins and cannot be overridden, a parent
  in auto mode is inherited and makes frontmatter `permissionMode` a no-op (and
  `permissions.disableBypassPermissionsMode` makes a frontmatter `bypassPermissions` a no-op too),
  otherwise the
  definition's mode, else the session's. The script itself has no filesystem/shell access — only
  the agents do.
- Resumable **within the same session** (cached agent results); a fresh session restarts it.
- Manage with `/workflows`; bundled `/deep-research <question>` (needs WebSearch) — **invoke-only
  since v2.1.218: Claude no longer starts it on its own.** Saved workflows live in
  `.claude/workflows/` (project) or `~/.claude/workflows/` (user), run as `/<name>`.
- **The script-writing reference is a bundled skill now, not tool prose** (v2.1.248): the
  Workflow tool's description dropped from ~5.7k to ~1k tokens and the authoring guide moved
  into `workflow-authoring`, loaded only when a script is actually being written. Worth knowing
  as precedent, not just as a fact: Anthropic pays down its own always-loaded budget by moving
  depth behind a trigger — the same move this kit calls progressive disclosure.
- Size guideline (advisory) — **default `medium` since v2.1.219** ("aim for fewer than 15
  agents"); values `small` / `medium` / `large` / `unrestricted`. Settable from **any** settings
  file via the **`workflowSizeGuideline`** key (which then *hides* the `/config` row), or
  interactively via `/config` → "Dynamic workflow size" (v2.1.202).
- Disable: `/config`, `"disableWorkflows": true`, or `CLAUDE_CODE_DISABLE_WORKFLOWS=1`.

**`/batch <instruction>` is the shipped fan-out for a mechanical sweep** [FP, `/en/commands`]: in a
git repo it splits the change across **5–30 subagents, each in its own worktree, each opening a
pull request**. Reach for it before scripting a `for file in …; do claude -p …; done` loop — that
loop is still the documented pattern when you need custom per-item logic or `--allowedTools`
scoping, but a plain "apply this change across these files" is now one command.

**When to reach for it** (`code.claude.com/docs/en/workflows`, "who holds the plan"): scope
exceeds one conversation's coordination; you want the orchestration codified + rerunnable; or
you need a repeatable quality pattern (adversarial cross-review, multi-angle convergence). It
costs **meaningfully more tokens** than the same task in conversation — it is not the everyday
default. See `harness-discipline.md` for the single-agent-first boundary.

## Agent teams — experimental, off by default [FP]

Multiple coordinating Claude Code instances behind `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`:
one fixed lead, teammates with their own context windows, a peer mailbox and a shared task
list they self-claim from (file-locked). **There is no team-creation tool any more** —
`TeamCreate` / `TeamDelete` were removed in v2.1.178, spawning a teammate needs no setup step,
cleanup is automatic at session exit, and the `team_name` input on the Agent tool is accepted
but ignored (same field in `TaskCreated` / `TaskCompleted` / `TeammateIdle` payloads is
deprecated). A harness step that calls either tool is calling something that no longer exists.

**The flag changes ordinary delegation — this is the part to know before enabling it.** While
agent teams are on, a subagent *Claude names on its own* launches as a teammate, so a team can
form during delegation nobody framed as team work. `=0` (user settings outrank a shell export;
project / local / `--settings` / managed layers outrank user) restores plain subagents without
a restart. Headless `-p` and SDK sessions never spawn teammates regardless.

- **Display**: `teammateMode` — `in-process` (**the default since v2.1.179**, any terminal) /
  `auto` / `tmux` / `iterm2` (needs the `it2` CLI); `--teammate-mode` flag is experimental and
  absent from `--help`.
- **Model**: the spawn prompt ▸ the subagent definition's `model` (in-process only) ▸
  `CLAUDE_CODE_SUBAGENT_MODEL` as the default ▸ the lead's model (order per the v2.1.251 release
  note; the `agent-teams` page still lists the variable first). `teammateDefaultModel` was **removed in
  v2.1.234** and a leftover value is ignored. Teammates inherit the lead's **effort**.
- **Permissions**: teammates start with the lead's mode and cannot be given per-teammate modes
  at spawn; their prompts surface in the lead session. One designed exception — a teammate's
  **plan is auto-approved** by the lead session without the operator reviewing it.
- **State on disk**: mailbox `~/.claude/teams/{team}/inboxes/{agent}.json`, config
  `~/.claude/teams/{team}/config.json` (removed at session end; runtime state — never hand-edit
  or pre-author), task list `~/.claude/tasks/{team}/` (survives, swept by `cleanupPeriodDays`).
  Team name = `session-` + the first 8 chars of the session ID; there is no project-level team
  config. Quality-gate hooks: `TeammateIdle`, `TaskCreated`, `TaskCompleted` (exit 2 = keep
  working / block creation / block completion).
- **Cost**: each teammate is a separate instance — token use scales linearly; first-party
  advice is 3–5 teammates, and an in-process teammate falls **outside the main conversation's
  cache TTL bucket** (5 min unless `subagentPromptCacheTtl: "1h"`).
- **Limits**: no `/resume` or `/rewind` for in-process teammates, task status can lag, one team
  per session, no nested teams, no background subagents from an in-process teammate, the lead
  is fixed for its lifetime.

**Document, route on explicit opt-in; do not enable by default** — and when the operator does
enable it, tell them the delegation-shape change above, not just the token cost.
Source: `code.claude.com/docs/en/agent-teams`.

## Tasks / scheduling [FP]

`TaskCreate` / `TaskUpdate` / `TaskList` / `TaskGet` — the structured session task list.
**On the current model generation they are off by default, and so is `TodoWrite`**: since
v2.1.233 none of the five reach Opus 4.8 / Sonnet 5 / Fable 5 / Mythos 5 or later unless you
opt in (`CLAUDE_CODE_ENABLE_TODO_TOOLS=1`, or naming them in `--tools` / `--allowedTools`),
because those models track multi-step work without a written checklist and the definitions cost
context. Consequence for a harness: **a session on a current model writes nothing to the task
list**, so any layer that treated it as the in-flight memory tier has an empty tier — put
in-flight state on disk instead. On older models (e.g. Opus 4.7) the four Task tools are on by
default. When present, it coordinates the run in progress and is
machine-local (a team's shared list lives under `~/.claude/tasks/`), so it is **not** the
repository-owned register of commitments: what outlives the run belongs in the repo, in whatever
carrier the project keeps commitments in. Using the task list as the backlog puts the backlog
outside the repo the work ships from. Scheduling is first-party documented
(`code.claude.com/docs/en/tools-reference`, `/en/scheduled-tasks`): `CronCreate` /
`CronList` / `CronDelete` schedule a recurring or one-shot prompt **within the current
session** (session-scoped; restored on `--resume`/`--continue` if unexpired) — not a
machine-level cron. `ScheduleWakeup` paces the next iteration of a self-paced `/loop`
(Claude calls it itself). The **`/loop`** skill is the
operator surface for recurring runs — since v2.1.248 its self-paced dynamic mode and the
no-prompt autonomous default are **always available**, including on Bedrock/Vertex/Foundry, and
`/usage` carries a **Loops breakdown** (runs, total tokens, tokens per run, last run) that makes
a runaway loop visible without instrumenting anything (v2.1.243). For **durable, cross-session
scheduling** first-party offers three surfaces — Desktop scheduled tasks and GitHub Actions
alongside the cloud one. The cloud surface is **`/schedule`** (the `RemoteTrigger` tool) managing **Routines** on
claude.ai — Anthropic-hosted, survives sessions, min interval 1 h; Pro/Max/Team/Enterprise,
not on Bedrock/Vertex/Foundry. Don't hand-roll a persistent cron around the session-scoped one.

## Background waiting — no sleep-polling

Waiting on a long build/test/deploy with `bash sleep` loops is an explicit first-party
anti-pattern. Two shipped mechanics:

- **Background Bash** (`run_in_background`): the task returns its output-file path and the
  agent is **re-invoked with a task notification on completion** — no polling needed.
- **`Monitor` tool** [FP] (v2.1.98+, `code.claude.com/docs/en/tools-reference#monitor-tool`):
  watches a command in the background and feeds each output line back as it arrives — tail a
  log, poll CI/PR status, watch a directory. Shares Bash permission rules; plugins can declare
  auto-start monitors. **Availability is profile-dependent**: absent on Bedrock/Vertex/Foundry
  and whenever `DISABLE_TELEMETRY` or `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` is set.

Background tasks are **never restored on resume**. Recurring checks are the `/loop` skill
(see Tasks / scheduling). To have external events *pushed* into a session instead of polled
(e.g. CI failures), see **Channels** (`/en/channels` — research preview, claude.ai auth).
**`PushNotification`** sends a desktop (and phone, via Remote Control) notification so a
long-running or scheduled task can reach the operator who stepped away (Anthropic-hosted;
not on Bedrock/Vertex/Foundry).

**Operating a background session is a set of CLI subcommands, not a harness you write** (all in
`claude --help` as of v2.1.251): `claude attach <id>` opens it in the current terminal — the id is
the short one `claude --bg` prints and `claude agents` lists; `logs <id>` prints its recent
terminal output; `stop`/`kill <id>` ends it; `respawn [id]` (or `--all`) restarts it on the
current Claude Code version, which is what you want after an upgrade; `rm <id>` deletes it. A
project that wrapped any of this in a script is carrying obvyazka the CLI now ships.

## Hooks — 33 events [FP]

Far more than the five most projects use. Full list (`code.claude.com/docs/en/hooks` documents
33, matching the binary enum name for name, `PreModelSwitch` / `PostModelSwitch` included):

- Session: `SessionStart`, `Setup`, `SessionEnd` — a `SessionStart` firing on **resume** also
  receives the session's staleness and the estimated re-cache cost (v2.1.251)
- Model: `PreModelSwitch`, `PostModelSwitch` (v2.1.251) — block, confirm, or annotate a model
  switch. The first native seam for "this project's deep work does not silently drop to a
  cheaper model"; previously only advisory prose could say it.
- Per-turn: `UserPromptSubmit`, `UserPromptExpansion`, `Stop`, `StopFailure`
- Tool loop: `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `PostToolBatch`,
  `PermissionRequest`, `PermissionDenied`
- Subagent/task: `SubagentStart`, `SubagentStop`, `TaskCreated`, `TaskCompleted`, `TeammateIdle`
- File/config: `FileChanged`, `CwdChanged`, `DirectoryAdded` (v2.1.219 — fires when `/add-dir`
  registers a new working directory mid-session), `ConfigChange`, `InstructionsLoaded`
- Context/display: `PreCompact`, `PostCompact`, `MessageDisplay`, `Notification`
- Worktree: `WorktreeCreate`, `WorktreeRemove`
- MCP elicitation: `Elicitation`, `ElicitationResult`

Exit code 2 = blocking error (stderr is fed back to Claude). Hooks are deterministic
enforcement; CLAUDE.md instructions are advisory requests. A Stop hook that keeps blocking
is overridden by Claude Code after **8 consecutive blocks** (cap configurable via
`CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`).

`Stop` / `SubagentStop` hooks can return `hookSpecificOutput.additionalContext` to **feed
Claude context and keep the turn going** without the hook being treated as an error — prefer
this "feed-and-continue" shape over hard block-at-stop when the goal is to nudge, not gate.

## Effort, fast, thinking [FP] (`code.claude.com/docs/en/model-config`)

- Tiers: `low`, `medium`, `high`, `xhigh`, `max` — effort is supported across the Claude 5
  family and the Opus 4.x generation (live `/effort` dialog). **The default is per model, and the
  current default model is the exception: Opus 5.5 defaults to `medium`**, where every other
  model that supports effort defaults to `high` except Opus 4.7, which defaults to `xhigh`; an
  org default-effort level, where set, becomes the default for the org's default model. `xhigh`
  itself is absent on Opus 4.6 / Sonnet 4.6, which offer `low` / `medium` / `high` / `max`.
- **The lever a harness reaches for first is inert on the current default model** [FP,
  `model-config`, verbatim]: "**A top-level `effortLevel` in your user settings file doesn't count
  for Opus 5.5.** That key is the older form `/effort` wrote before Claude Code saved levels per
  model: it keeps applying where it applied before, on Opus 5, Fable 5.1, and earlier models,
  while Opus 5.5 and models released after it start at their own default until you choose a level
  for them with `/effort` or the `/model` picker." Scope matters: **user** settings are what this
  excludes — a top-level `effortLevel` in **project, local or managed** settings still applies to
  every model. So a machine carrying `effortLevel: "xhigh"` in `~/.claude/settings.json` does not
  slip one rung on Opus 5.5, it lands on `medium` — two rungs down, silently, with the file still
  valid. Per-model levels live under **`modelSettings`** in user settings, which is also where
  `maxEffortLevel` (v2.1.267) can cap a single model; top-level `maxEffortLevel` caps every
  provider, Bedrock / Vertex / Foundry included, and a user may still pick lower.
  Two v2.1.280 changes to check against a pinned model: a level **saved before `/effort` became
  per-model no longer applies to a newly released model**, and Opus 4.7 / 4.8 / Fable 5 **stopped
  holding their launch-default effort** over `/effort` in `-p` / the Agent SDK, a project /
  managed / `--settings` `effortLevel`, or a per-model level.
- **How to set it — session-wide** (binary- and schema-verified 2026-07-25 on v2.1.220):
  - `effortLevel` in settings — enum `low` | `medium` | `high` | `xhigh` **only**, and **no longer
    a universal lever: in *user* settings it does not reach Opus 5.5 or anything released after
    it** (see the bullet above; project / local / managed layers still do). `max` is
    session-only (use `/effort`); an out-of-enum value here is swallowed by a `.catch()` rather
    than rejected, so a typo costs the level silently while leaving the file valid. `ultracode`
    *is* a settings key (boolean) — a `--settings` layer carrying it starts an `xhigh` session
    (verified 2026-07-26); only the interactive toggle refuses to persist it.
  - `CLAUDE_CODE_EFFORT_LEVEL` — same values **plus `auto`** (= the current model's default).
  - CLI: `claude --effort <level>` for the session (a *launch pin*: `/effort` then reports
    "the launch-effort pin holds effort at X"), `claude agents --effort <level>` as the default
    for dispatched background sessions. Since v2.1.251 **`/effort` saves your default per
    model**, so switching models no longer carries the previous model's level over.
  - **Precedence, measured 2026-07-26 on v2.1.220** (org ceiling ▸ env ▸ **a delegate's frontmatter
    `effort:`** ▸ launch pin ▸ settings ▸ model default) — **the `settings` rank was measured
    before user-settings `effortLevel` stopped reaching new models, so on Opus 5.5 that rank is
    empty for the user layer and the model default wins there.** The frontmatter rank is what makes the
    per-delegate lever below work at all; docs fold launch pin / settings / `/effort` into one
    rank, while the measurement below separates them. `CLAUDE_CODE_EFFORT_LEVEL` wins over everything user-side — including the
    `--effort` flag: with the env set to `auto`, `--effort low` vs `--effort xhigh` produced
    911/953 vs 798/533 output tokens (no effect), while with the env unset the same pair gave
    722 vs 1053 (median, N=3) and `effortLevel` in settings gave 427/493 vs 692/994. The org
    ceiling sits above all of it ("Effort 'X' exceeds your organization's limit …; set to 'Y'").
  - **The trap this creates**: an `env: { "CLAUDE_CODE_EFFORT_LEVEL": … }` block in
    `settings.json` is *still the env var* — it silently outranks that same file's `effortLevel`
    key, the `--effort` flag, and `/effort`, which then answers "Not applied". Pinning effort by
    env in settings is how a harness ends up permanently unable to raise it. Prefer the
    `effortLevel` key. (Project-level `settings.json` is also ignored in an untrusted workspace —
    the setting being present is not evidence it applied.) **Verifying that a level took hold is
    itself hard**: token spend separates tiers only on a task long enough to spend on, and only
    across several runs — on a short prompt, `--effort low` and `--effort xhigh` overlapped
    completely (n=3 each, 2026-07-26), and on a heavy reasoning task the medians parted by ~25%
    while the ranges still crossed. Interactively, `/effort` reports the active level directly;
    that is the answer, not an inference.
- **How to set it per delegate — this is the harness lever.** `effort:` in the frontmatter of
  `.claude/agents/*.md` (also accepted in skill and command frontmatter): a named level
  (`low` / `medium` / `high` / `xhigh` / `max`) or an integer — **`inherit` is not valid here**,
  the loader rejects it; that value belongs to `model:`, which is a different field with a
  different schema. Omitting `effort:` is how you inherit. The **Agent tool overrides only `model` per call, never effort** — the
  level comes from the agent's definition; a dynamic workflow is the surface that *does* take it
  per call (`agent(prompt, {effort})`). Measured 2026-07-26 on v2.1.220, same prompt and same
  parent session: `effort: low` → 862 / 656 output tokens, `effort: xhigh` → 3358 / 3452 (N=2).
  So pinning a cheap level on a mechanical subagent, and a high one on a verifier, is a real
  dial and not decoration. **A delegate that declares no `effort:` inherits the session's
  level** — measured with a hard binary oracle instead of token spend, **varying the session**
  so that inheritance and a fixed default are distinguishable: an agent declaring no `effort:`
  produced the server-tool 400 quoting `'xhigh'` from an `xhigh` session (2/2) and searched
  cleanly from a `high` session (2/2). A fixed model default could not produce that difference.
  An earlier reading here — "an ad-hoc delegate stays at the model default" — rested
  on token spend from a `low` and an `xhigh` parent (937/1550 vs 1043/746): ranges that never
  separated, on the oracle this file marks as weak two bullets above. Declare the level
  explicitly whenever it matters; do not assume a delegate starts cheap.
- **`CLAUDE_EFFORT` reports whoever reads it — session or delegate — at its own level.** It is
  read-only and exported into Bash subprocesses and hook commands (the same value arrives as the
  hook-input field `effort.level` on tool-context hooks); the binary describes it as the active
  level for the current turn *after any silent downgrade for the selected model*. Re-measured on
  v2.1.220 in `claude --print`, each cell read back as set and matched the tier the server-tool
  400 quotes: `high` via the `--effort` flag, `xhigh` via `effortLevel` in settings, `max` via
  the flag. The env path was not re-tested. Inside a **delegate** it reports the *delegate's*
  level, not the parent's — an agent pinned `effort: high` inside an `xhigh` session read back
  `high` and searched cleanly, 2/2. Both earlier readings here — "always `high`, however the
  level was set" and "inside a subagent it read the parent's" — rested on token spend and did
  not survive. The other real channel is the interactive statusline:
  `StatusLineCommandInput.effort.level`, plus **per-agent `effort` in the `subagentStatusLine`
  payload** (v2.1.214, added precisely so agent rows can render model + effort) — the cheap way
  to see "who is running at what" during a fan-out. **Cheaper still since v2.1.243: `/tasks` and
  the agent detail dialogs now print the model and effort level each subagent ran on** — no
  statusline script required, which retires the main reason to write one for fan-out
  observability. Headless leaves only token spend — a
  subagent's own transcript at `<session-dir>/subagents/agent-<id>.jsonl` (+ `.meta.json` naming
  its `agentType`) — and that is a **weak** oracle: it separates tiers only across several runs
  on a task substantial enough to spend on (above). The transcript's own per-message effort field
  (announced v2.1.212) was **not** observed in headless session JSONL.
- **A parent sees only a delegate's final text, never its `tool_result`s.** A delegate can fail a
  tool, keep working, and return success-shaped prose — nothing surfaces. To know, scan
  `<session-dir>/subagents/agent-*.jsonl` (`isSidechain` is not a usable subagent marker), where a
  failed tool carries `is_error: true` on the `tool_result` itself. Scan those records, **not**
  `isApiErrorMessage`: that flag marks an assistant message wrapping an API error and a tool-level
  failure never produces one, so a filter built on it reports clean.
- **Measuring effort is where harness claims go wrong** — four rules, each paid for by a wrong
  entry in this file. Confirm a setting took hold **by an oracle the claim does not depend on**.
  **Vary the variable the conclusion names**; a row that holds it constant cannot support a causal
  claim, however many times it is repeated. **Label a table with the load path actually measured.**
  Read the oracle off `--output-format stream-json` rather than hunting a transcript path (slugs
  fold `_` to `-`, and a wrong path returns a confident, empty "no failures") — and confirm the
  *negative*: no error signature proves nothing until the same scan shows the tool was called.
- **What to know before you raise effort on Opus 5.5** [FP,
  `platform.claude.com/docs/en/models/opus-5-5/{whats-new-opus-5-5,migration-guide}`]:
  - *Effort is the **only** thinking control.* Thinking is **always on** and cannot be disabled:
    `thinking: {"type":"disabled"}` and `{"type":"enabled","budget_tokens":N}` both return 400
    [FP, `thinking-troubleshooting` per-model table]. Where a harness used to switch thinking off
    to save tokens, the lever is now a lower effort rung. (Both disabled-thinking traps — effort
    silently ceilinged at `high`, and a tool call written into the text instead of a `tool_use`
    block — are scoped by first-party **to Opus 5 alone**, and cannot occur where thinking cannot
    be switched off. Opus 4.8 / 4.7 have neither trap: there thinking is *off* by default and only
    `"enabled"` is rejected.)
  - *`max_tokens` is a hard cap on thinking **plus** response text*, and this model thinks more
    per turn at a given level than Opus 5 did, most of all at `xhigh` / `max`. First-party
    testing on agentic coding landed on **128,000 — the model's maximum** [FP,
    `prompting-claude-opus-5-5`]; the 64k starting point in the effort page belongs to the
    Opus 5 / 4.8 / 4.7 sections. In Claude Code the knob is `CLAUDE_CODE_MAX_OUTPUT_TOKENS`.
    A budget sized for the old model can end the turn before the tool call happens — which reads
    as a lost capability, not a truncation.
  - **API-only**, listed because it changes what a Messages-API integration must send — not
    reachable from the CLI, which sets these itself: forced `tool_choice` (`any` / `tool`) returns
    400 (use `auto` plus `strict: true` or structured outputs), and narration between tool calls
    arrives as progress-update `thinking` blocks, empty at the default `display: "omitted"`.
    Whether Claude Code's own `--print` output is affected is **unverified here** — CC manages
    `thinking.display` itself; probe with `--output-format stream-json` before relying on either
    behaviour in a runner.
- **Fable 5.1 specifics** (v2.1.257+, `/model fable`, alias `best`): the default of no plan;
  ~2.5× the Opus 5.5 token price ($10/$50 vs $4/$20); `/fast` does not run on it; safety
  classifiers can auto-fall back to Opus mid-session. Its predecessor Fable 5 (v2.1.170+) is
  legacy but still what `fable` / `best` resolve to in Claude apps gateway sessions.
- `ultracode` is a **setting, not a tier**: sends `xhigh` *plus* auto dynamic-workflow
  orchestration for substantive tasks; session-only.
- `/fast` — faster output (up to ~2.5×), **not** an effort downgrade; **Opus 5.5, Opus 5 and
  Opus 4.8 only** (Opus 5.5 is the fast-mode default since v2.1.280; Opus 4.7's was removed
  2026-07-24, and switching to it turns fast mode off) — never on Sonnet or Haiku; research
  preview (`code.claude.com/docs/en/fast-mode`), billed **via usage credits outside subscription
  rate limits** ($8/$40 MTok on Opus 5.5, $10/$50 on Opus 5 / 4.8) — never "free on the plan".
  The first toggle in a conversation reprices the whole accumulated context at the fast-mode
  uncached input rate, so switch it on at the start of a session, not mid-way.
- `ultrathink` — one-turn deeper-reasoning keyword (in-context only).
- Adaptive thinking triggers reasoning only when the turn needs it — do **not** try to manage a
  thinking budget from the harness. Per-model, from the `thinking-troubleshooting` table:
  **always on and not disableable** on Opus 5.5 / Fable 5.1 / Fable 5 (and the Mythos pair);
  **on by default but disableable** on Opus 5 (only at effort `high` or below) and Sonnet 5;
  **off by default** on Opus 4.8 / 4.7, which reject only `"enabled"`.

## /goal [FP] (`code.claude.com/docs/en/goal`)

A shipped slash command. `/goal <condition>` sets a completion condition; a small fast model
re-checks after every turn (judging only what Claude surfaced) and Claude keeps working
across turns until met. `/goal clear`, `/goal` for status. An early rung of the verification
ladder (prompt check → `/goal` → Stop hook → `/code-review` → fresh-context second opinion).

## Code review — built-in surfaces [FP]

Review is a shipped capability — never scaffold a custom `code-reviewer` subagent (the
classic audit offender, see `audit-checklist.md` §3). The surfaces:

- **`/code-review`** — bundled skill: review the **current working diff** for correctness
  bugs and simplification cleanups at a chosen effort level; `--comment` posts inline PR
  comments, `--fix` applies findings to the working tree. Local, free, codebase-aware —
  **the default rung for any substantive change** [FP, `/en/commands`]. Since v2.1.218 it runs
  as a **background subagent** (review work no longer fills the conversation).
- **`/review`** — now simply an **alias of `/code-review`**, which reviews the current diff
  *or* a PR (`/code-review <level> <pr#>`). Called without a level it reuses the last level you
  typed; `/code-review ultra` runs the deep cloud review. The older split ("`/review` = PR only")
  no longer holds.
- **`/security-review`** — bundled skill: security review of the pending changes on the
  current branch.
- **`/code-review ultra`** (alias `/ultrareview`; CLI: `claude ultrareview [target]`,
  `--json`, `--timeout` default 30 min) — cloud-hosted multi-agent review of the current
  branch or a PR — research preview. First-party economics
  (`code.claude.com/docs/en/ultrareview`): typically **5–10 min, ~$5–25/run via usage credits**;
  3 free runs on Pro/Max (one-time allotment, no refresh; a stopped run still consumes one).
  Reserve it for high-stakes gates (security-sensitive change, migration, payment path);
  `/code-review` covers the everyday case. **This is the fleet-of-reviewers rung** — the kit
  shipped its own 3-role audit until v1.23.0 and retired it here: what made that rung work was
  the independent context, which a fresh session provides for free, while the orchestration
  around it was the pipeline this kit tells others not to hand-roll. Where the change itself is
  the risk, reach for `ultrareview`; where the *deliverable* is (milestone close, irreversible
  gate), open a **new session** and tell it to refute — subscription-local, and it can execute
  the live stack, which a diff review does not.
- A `REVIEW.md` at the repo root tunes the **managed GitHub Code Review service** (Team/Enterprise
  research preview) — the local `/code-review` **does not read it**: "the review follows your
  `CLAUDE.md` like any Claude Code session, but it doesn't read `REVIEW.md`". The calibration lever
  for the local review is the **effort level**: `low`/`medium` report only high-confidence
  findings, `high`–`max` broaden coverage and may include less certain ones. A project on
  Pro/Max that writes a `REVIEW.md` for local review gets nothing.
  (`code.claude.com/docs/en/code-review`; tags: Important / Nit / Pre-existing).

**Counter-pressure from the model side — don't *instruct* self-verification** [FP,
`whats-new-opus-5`]. The current Opus generation "verifies its own work without being told to",
and first-party guidance is explicit: **remove verification instructions carried over from
earlier models** ("include a final verification step", "use a subagent to verify") — they cause
**over-verification**. This does not retire the ladder: the ladder's rungs are *external*
(`/code-review` on the diff, a fresh-context refuter, `/code-review ultra` at a gate), and an
independent evaluator is not the same thing as telling the author to check itself
(`harness-discipline.md`). What it does retire is prompt-level
nagging — the "remember to verify" line in CLAUDE.md and the "then verify with a subagent" tail
on a task prompt. Same model generation also delegates to subagents more readily on its own.

**`/code-review` can start itself again; `/verify` and `/deep-research` cannot.** Since
**v2.1.246** Claude may run `/code-review` on its own — ask for a review in plain language and
it runs the skill without the command being typed, and a scheduled task with `/code-review` as
its prompt runs it too. (Before that it self-started only where an Anthropic feature flag
enabled it.) To keep it typed-only while leaving the command available, set
`skillOverrides: {"code-review": "user-invocable-only"}`. `/verify` and `/deep-research` remain
invoke-only, so a ladder resting on those rungs still needs a carrier: the operator, a CLAUDE.md
duty line, a slash command, or a hook. Prefer the deterministic carriers when it must happen every
time (`harness-discipline.md`, verification ladder).

Review surfaces are profile-dependent like any tool: bundled skills/plugins can be disabled
or blocklisted per-user (`~/.claude/plugins/blocklist.json`). **Verify a surface exists in
the live session (`/`-autocomplete) before routing a remediation to it** — detect, then
prescribe. Where review sits in the verification ladder — see `harness-discipline.md`.

## /doctor — the native harness audit [FP]

`/doctor` (alias `/checkup`) is a **health-check of the harness itself**, not just of the install,
and it is the reason a hand-written "audit my `.claude/`" script is duplicated obvyazka. Read-only
first, then it proposes fixes and asks before applying. Its write proposals touch **user/local
scope**, with one documented exception: the CLAUDE.md checks may propose edits to **checked-in**
files (trimming content Claude could derive from the codebase, v2.1.206). What it covers:

- **Install and settings** — duplicate/leftover installs, PATH, unparseable settings, broken or
  colliding agent definitions (the same ground `claude doctor` prints read-only).
- **Dead weight against context cost** — skills, MCP servers and plugins that cost context but are
  never used, read off real usage counters (`skillUsage` / `pluginUsage` in `~/.claude.json`) and a
  scan of recent transcripts across *all* your projects, then offers to disable them. This is the
  retire half of a skill lifecycle, natively.
- **CLAUDE.md rightsizing** — dedupes local memory files against checked-in ones and trims what a
  session could derive from the codebase (directory layouts, tech-stack lists, architecture
  overviews) while keeping gotchas, rationale and non-standard conventions; proposes migrating
  always-loaded guidance into lazy skills and nested CLAUDE.md files.
- **Slow hooks and context-heavy extensions**, version currency, making auto mode the default
  permission mode, and pre-approving frequently denied read-only commands.
- **Server-managed-settings diagnostics** (v2.1.248) — a startup warning when they fail to load,
  and a `/doctor` + `/status` line explaining the failure or why they were not fetched.

Two neighbouring native checks that overlap what a harness would otherwise hand-roll: a
**startup warning for Bash allow rules with a wildcard before the subcommand** (`Bash(git *
main)`, v2.1.246 — such a rule also matches options inserted before the subcommand, which is
how an allowlist quietly widens), and a **`/permissions` → Auto mode tab** (v2.1.246) for
viewing and editing the classifier rules instead of hand-editing `autoMode.*` blind.

One budget fact it encodes, worth knowing on its own: **the skill listing is budgeted at ~1% of the
context window — when the summed descriptions exceed it, entries get truncated and skill routing
degrades**, which bites before raw token cost does. The practices behind the CLAUDE.md checks are
first-party [BLOG, `claude.com/blog/the-new-rules-of-context-engineering-for-claude-5-generation-models`].

A neighbouring bundled tool: the **`claude-api` skill carries a `prompt-audit` subcommand** —
it audits prompts and tool descriptions for patterns written for older models, which is exactly the
"instructions tuned for older models constrain newer ones" failure this file exists to prevent.

## Memory [FP] (`code.claude.com/docs/en/memory`)

**`/init` is no longer just a file generator** [FP]. With **`CLAUDE_CODE_NEW_INIT=1`** it runs an
interactive multi-phase flow: it asks which artifacts to set up (CLAUDE.md files, skills, hooks),
explores the codebase **with a subagent**, fills gaps with follow-up questions, and presents a
reviewable proposal **before writing anything**. It also reads `AGENTS.md`, `.cursor/rules`,
`.github/copilot-instructions.md`, `.devin/`, `.windsurf/`, `.clinerules` and folds the relevant
parts in. Anything a harness kit does at bootstrap has to be measured against *this*, not against
the old one-shot `/init` — the parts it covers are not the kit's to reimplement.

**A generated instructions file is a draft, not a deliverable.** Two 2026 studies found
LLM-authored `AGENTS.md`/`CLAUDE.md` files made agents *worse*: one measured −2% success at +23%
cost, the other reduced task success in 5 of 8 settings and added 2.45–3.92 steps per task. The
mechanism in both: the generated file restates what the model can already derive from the
repository, so it spends context to say nothing. The rule that follows is not "don't generate" —
it is **generate, then cut everything derivable**, keeping only what a new teammate would have to
be told. `/doctor` automates the cut for a checked-in CLAUDE.md.

Two systems, both loaded every session: **CLAUDE.md** (you write) and **Auto memory** (Claude
writes). CLAUDE.md load order broad→specific: managed policy → user `~/.claude/CLAUDE.md` →
project `./CLAUDE.md` or `./.claude/CLAUDE.md` → local `./CLAUDE.local.md`; plus `.claude/rules/*.md`,
`@import` (depth ≤4). Auto memory lives
in `~/.claude/projects/<project>/memory/` with a `MEMORY.md` index (first 200 lines / 25 KB
loaded each session). Command is **`/memory`** (lists loaded files, toggles auto memory).
**There is no built-in `/remember`** — "remember X" is natural-language behavior writing to
auto memory.

**`AGENTS.md` — read only while no `CLAUDE.md` is on the path** [FP, `/en/memory`, re-checked
2026-10-28]. It is the file Codex, Cursor and Copilot look for. **Since v2.1.277 Claude Code reads
`AGENTS.md` directly — but only when no `CLAUDE.md`, `.claude/CLAUDE.md` or `CLAUDE.local.md` exists in
the working directory or above it**; with one present, only the `CLAUDE.md` files load (user-level
and managed `CLAUDE.md` and `.claude/rules/` don't count for that check). So a root `CLAUDE.md`
switches off every nested `AGENTS.md` below it — in a monorepo each one needs its own bridging
`CLAUDE.md`. A "Project instructions" setting can change the default. The measurement below
predates v2.1.277 and stands as history for that version. Two first-party bridges, both keeping one
source of truth:

- `@AGENTS.md` as the first line of `CLAUDE.md`, with Claude-specific additions below it.
- `ln -s AGENTS.md CLAUDE.md` when nothing Claude-specific is needed (on Windows the symlink needs
  Administrator or Developer Mode — use the import there).

**Measured here, three runs on v2.1.251, with an `InstructionsLoaded` hook as the oracle** (it logs
exactly which instruction files load, and is the right instrument for any "did this reach the
context" question):

| Setup | In the startup context |
|---|---|
| `AGENTS.md` alone | **only the user-level CLAUDE.md** — the project file is absent |
| `CLAUDE.md` containing `@AGENTS.md` | both `CLAUDE.md` **and** `AGENTS.md`, as separate entries |
| `CLAUDE.md` symlinked to `AGENTS.md` | `CLAUDE.md` (one file, carrying the AGENTS.md content) |

The first row is the finding that matters: in a repo that keeps only `AGENTS.md`, Claude starts
with **no project instructions at all**. A prompt can still make it *read* the file — a naive probe
asking "what is the codename?" answers correctly, from a tool call — so a behavioural probe
confirms nothing here. Use the hook.

`/import` (v2.1.213+) appends another agent's config — `AGENTS.md`, `.cursor/rules`,
`.github/copilot-instructions.md` and friends — into the matching `CLAUDE.md` as a **one-time
copy**, and carries over MCP servers, commands, subagents and skills. One-time: it does not keep
them in sync, so for a repo that keeps evolving its `AGENTS.md`, the import or symlink is the
maintainable form and `/import` is the migration.

**What loads when — and the silent-error surface (verified 2026-06-24, FP `code.claude.com/docs/en/memory`).**
CLAUDE.md is delivered as a **user message after the system prompt**, not in the system prompt
itself — which is why output styles / `--append-system-prompt` carry more weight than CLAUDE.md
(see Output styles below). Loading model:
- **At launch, in full, every session:** all CLAUDE.md + CLAUDE.local.md from root→cwd; `.claude/rules/*.md`
  **without** `paths:` (same priority as `.claude/CLAUDE.md`); `@import`s (expanded at launch — splitting
  into imports does **not** save context tokens); `MEMORY.md` first 200 lines / 25 KB only (excess silently
  not loaded).
- **On-demand:** nested subdir CLAUDE.md (when a tool touches a file in that subtree); path-scoped rules
  (on **read** of a matching file — not on Write, not every tool use); skill bodies; auto-memory topic files.
- **After `/compact`:** project-root CLAUDE.md is **re-read from disk and re-injected**; nested subdir
  CLAUDE.md is **NOT** re-injected until the next file read in that subtree; conversation-only instructions
  are **lost**. ⇒ a subdir-scoped convention you relied on can silently vanish mid-long-session after a
  compact. Make must-not-miss rules always-on (root) or deliver via `SessionStart`/`CwdChanged` hook.
- `--add-dir` dirs do **not** load their CLAUDE.md unless `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1`.
- HTML block comments in CLAUDE.md are **stripped** before injection (visible only on direct Read) — fine
  for maintainer notes, but don't hide active instructions there.
- **`claudeMdExcludes`** (settings, any layer incl. local; absolute-path globs, arrays merge) skips ancestor
  CLAUDE.md/rules in monorepos. **Managed-policy CLAUDE.md cannot be excluded** (org instructions always apply).

**Scoped rule delivery — reliability ranking (verified 2026-06-23, re-ground on bump).** To put
a rule "only where it's needed" instead of taxing every turn in root CLAUDE.md, prefer
**nested `<subdir>/CLAUDE.md`**: lazy-loaded **deterministically** when a tool touches a file in
that subtree (native, `code.claude.com/docs/en/large-codebases`) — empirically read and obeyed by
fresh subagents (a directory convention overrode an explicit contrary instruction in test). This is
the reliable mechanism for scoping a campaign / large-feature-area protocol. Do **not** rely on
`.claude/rules/*.md` `paths:` frontmatter for this: it is heuristic, and **#16299 (a scoped rule
loading globally) is open as of 2026-08-29**. The rest of what used to be listed here as an open
cluster has closed — #16853 fixed in 2.1.198, #21858 completed, #23478 and #17204 closed
not-planned by a stale bot — so check state before citing a number. Use `paths:` only for nice-to-have
narrowing, make critical rules always-on. Guaranteed delivery for must-not-miss → a `SessionStart` /
`CwdChanged` hook reading `cwd` → `additionalContext`. **A scoped rule must read as a legitimate
project convention, not an imperative** ("always append token X") — a security-conscious model
correctly refuses injection-shaped instructions found in a working directory.

## Skills, commands, MCP, plugins [FP]

- **Skills** — `.claude/skills/` (+ `~/.claude/`), load on demand by description; descriptions
  cost context at start, full body only when used; `disable-model-invocation: true` → zero cost
  until you trigger it. Reference-skills (knowledge) vs action-skills (do something).
  Invocation control is two independent flags (verified 2026-07-16, `/en/skills`):
  `disable-model-invocation: true` = only the user triggers it (side-effect workflows);
  `user-invocable: false` = only Claude triggers it — hidden from the `/` menu, made for
  background knowledge (first-party example: a `legacy-system-context` skill). **Exact
  spelling `user-invocable`** — the `user-invokable` variant seen in the wild is silently
  ignored. `context: fork` (+ `agent: <type>`) runs the skill body as the prompt of a forked
  subagent — the body never enters main context, only the result returns; combine with
  read-only `allowed-tools` for knowledge lookups over a docs corpus. **Since v2.1.218 a
  `context: fork` skill runs in the *background* by default** — the turn continues without its
  result. So a fork-skill whose answer the current turn depends on **must** carry
  `background: false` in frontmatter; without it the harness step silently proceeds unanswered.
  (Note the direction of the change: **before v2.1.218 a forked skill blocked the turn until it
  finished**; background is the new default, not the old one.) Frontmatter booleans also accept `yes`/`no`/`on`/`off`/`1`/`0` (v2.1.218).
- **Slash commands** — `.claude/commands/*.md`; appear in `/`-autocomplete. Bundled skills keep
  arriving (`/design` — artboard-based UI drafting, a hub for Claude Design, research preview
  with no changelog entry to pin it to; `/claude-api`
  with its `prompt-audit` and `cost-optimize` subcommands), so **check `/`-autocomplete before
  authoring a command for a generic need** — the built-in set is a moving target, and the
  duplicate you write does not announce itself. Two small ones with harness consequences:
  **`/verify`** runs and checks the app itself (the rung above "tests pass" — first-party
  guidance is to run it *after* Claude's own check passes). It and **`/run`** infer a standard
  launch with no setup, and that inference is what degrades on a project needing a database, an
  env file, a graphical session or a multi-step build: there, **`/run-skill-generator`** — once per
  project, again when the build changes — brings the app up from a clean environment and commits
  the working recipe as `.claude/skills/run-<name>/`, which every later run follows; `/verify`
  records its own recipe the same way when it had to work one out. Prefer that over writing a
  launch procedure into CLAUDE.md. **`/btw`** answers a side question
  **without putting it in conversation history**, which is the cheap fix for the context-pollution
  failure mode rather than a `/clear`.
- **Code intelligence** — for a typed language, first-party best-practices recommends installing a
  code-intelligence plugin so Claude navigates by **symbol** instead of reading whole files, with
  automatic error detection after edits. This is the tools-layer move the harness-gains research
  keeps pointing at; it is not something a prompt or a rule can substitute for.
- **MCP** — external tools appear as normal tools; `Elicitation`/`ElicitationResult` support input flows.
- **Plugins** — marketplaces `anthropics/claude-plugins-official` (auto-registered) and
  `anthropics/claude-plugins-community` (`@claude-community`); can ship subagents/hooks/skills/
  commands. A plugin directory under `~/.claude/skills/<name>/` auto-loads without any
  marketplace (`claude plugin init <name>` scaffolds one; inspect with `claude plugin list`).
  **Version semantics** [FP, `/en/plugins-reference#version-management`]: the version in the
  plugin's own `plugin.json` is canonical (it wins over the marketplace entry) and acts as
  the **update cache key** — pushing new commits without bumping it ships nothing to
  installed users. Releases pin via `{name}--v{version}` git tags; `claude plugin validate`
  **warns** when plugin.json and the marketplace entry disagree and still passes (measured:
  "✔ Validation passed with warnings") — it fails only under `--strict`, while `claude plugin tag`
  refuses outright. Installs record the resolved
  `gitCommitSha` (binary-verified). Distribution is no longer git/npm-only: an **`archive` source** installs a
  plugin from a zip over HTTPS with optional SHA-256 pinning. `/plugin install` refreshes a stale
  marketplace catalog and retries before reporting "not found", and plugins installed via
  `/plugin` **activate immediately when it is safe** instead of always demanding
  `/reload-plugins`. A plugin may declare `"."` as its `skills` path (root-level `SKILL.md`).
  **Auto-update** [FP, `/en/plugins/loading#when-auto-update-runs`, verified 2026-10-28]: on by
  default only for Anthropic's official marketplaces; for any other, `autoUpdate: true` on its
  `extraKnownMarketplaces` entry (wins) or the `/plugin` → Marketplaces toggle. Any of
  `DISABLE_UPDATES`, `DISABLE_AUTOUPDATER`, `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` switches the
  whole pass off and hides the toggle unless `FORCE_AUTOUPDATE_PLUGINS=1`. The pass runs in an
  interactive session after the first message (random delay ≤10 min); new versions load next session.

## Output styles [FP] (`code.claude.com/docs/en/output-styles`)

Files in `.claude/output-styles/` (or `~/.claude/`, or managed policy) that **modify the system prompt
directly** — set role/tone/format for *every* response. Activated via `/config` → Output style (saved to
`settings.local.json` `outputStyle`); the standalone `/output-style` command was removed in v2.1.91. Read
**once at session start** — a change takes effect only after `/clear` or a new session.

Built-ins: **Default / Proactive / Explanatory / Learning / Concise** (v2.1.237 — leads with the
result, skips preamble and narration, does the work just as thoroughly; check the built-ins
before authoring a style for "shorter answers", that need is now shipped).

**Silent-error trap — the one reason this is in the kit.** A custom output style's instructions are appended
to the end of the system prompt, and it **omits Claude Code's built-in software-engineering instructions
(how to scope changes, write comments, verify work, security) unless `keep-coding-instructions: true`** is
in frontmatter. The flag **defaults to `false`** — so a custom style authored for "still coding, just
different voice" will silently strip the built-in verification & scoping disciplines unless the author sets it.
Rule: any custom output style used while still doing software work **must** carry `keep-coding-instructions: true`;
omit it only for genuinely non-coding roles (writing/data assistant). Before authoring one, check the built-ins
cover the need. Frontmatter: `name`, `description`, `keep-coding-instructions` (default `false`),
`force-for-plugin` (plugin-only, auto-applies, default `false`).

Comparison of the system-prompt-touching mechanisms: **output style** modifies the system prompt (every turn);
**CLAUDE.md** adds a user message after it (project context); **`--append-system-prompt`** appends without
removing anything (one-off per invocation); **subagent** = own system prompt; **skill** = loaded on invoke.

## Settings, permissions, resilience [FP]

Native enforcement worth knowing before writing manual rules or guard hooks:

- The "default" permission mode is named **Manual** since v2.1.200 (`--permission-mode
  manual` / `"defaultMode": "manual"`; the old `default` spelling is still accepted).
- **A bad `permissions.defaultMode` silently voids the whole settings file.** Most keys are
  declared `.optional().catch(...)`, so a bad value is dropped and the rest of the file still
  loads — `effortLevel` behaves exactly this way. `defaultMode` has **no `.catch()`**: an
  out-of-enum string fails the parse and the *entire* file is discarded — hooks (including the
  guard hook meant to be the hard floor), `permissions.allow`/`deny`, `effortLevel`, `language`,
  `enabledPlugins`, statuslines. Nothing is printed; the session simply runs unconfigured.
  Measured 2026-07-26 on v2.1.220 with a differential oracle: a `--settings` layer carrying
  `{"language":"french", …}` answered in French with a valid `defaultMode` and fell back to the
  user-level language with an invalid one (n=2 each). Accepted values:
  `default` · `manual` (alias of `default`) · `acceptEdits` · `bypassPermissions` · `plan` ·
  `dontAsk` · `auto`. Worth a one-line check anywhere settings are generated or edited by
  tooling — and note that a validator omitting `manual` rejects a valid config:
  ```bash
  jq -e '.permissions.defaultMode // "default" |
    IN("default","manual","acceptEdits","bypassPermissions","plan","dontAsk","auto")' \
    ~/.claude/settings.json
  ```
  The general lesson beyond this key: **an invalid config value is not guaranteed to degrade
  gracefully.** Whether a typo costs one setting or all of them depends on a `.catch()` you
  cannot see from the file, so verify a setting *applied* — by an observable behaviour it
  controls — rather than that it is present.
- Deny rules accept a glob in the tool-name position (`"*"` denies all tools);
  `WebFetch(domain:...)` deny/ask/allow overrides the built-in preapproved hosts;
  a Read/Edit deny rule also blocks the **recognisable file commands** in Bash (`cat`, `head`,
  `tail`, `sed` …) but not a Python or Node script that opens the same path. Path anchors are
  `//`, `~/`, `/` and relative — **`$HOME` is not one of them**: measured, `Read(~/x/**)` denied
  a `cat`, while `Read($HOME/x/**)` let the same file through silently (the control rule warned
  in the same run, so the probe was not blind). Read deny rules
  hide files from Glob/Grep; `acceptEdits` prompts before writing code-executing config
  files (`.npmrc` / `.bazelrc` / `.pre-commit-config.yaml` / `.devcontainer/` …) and shell
  startup files.
- **Cross-session messaging is a shipped surface**: sessions can message each other across your
  machines (`SendMessage` + **`ListAgents`** to discover them; macOS, Linux and — since v2.1.239 —
  Windows, and since v2.1.248 also on Bedrock/Vertex/Foundry and with telemetry disabled). Type **`@`** in the prompt to
  mention another session by name (v2.1.232), and pass **`notify_when_idle`** to ask one session
  for a single notice when it next goes idle (v2.1.236) — opt-in, one-shot, **no polling**, which
  is the same anti-sleep-loop discipline as the Background-waiting section above. Its guard
  rails, all native: a relay **carries no user authority** (receivers refuse relayed permission requests),
  outbound messages pass the permission classifier before dispatch, `crossSessionInbound` holds
  messages addressed to a permission-bypassed session for your approval (`dialogExpiry` bounds the
  wait), and a failed delivery is now reported as an error instead of "Message sent". Treat access
  to another agent as equivalent to that agent's privileges — first-party incident: an
  incident-response agent asked a second Claude over Slack to push a fix on its own initiative.
- `fallbackModel` setting (ordered list) / `--fallback-model` — automatic model fallback,
  including interactive sessions. Managed settings can pin an allowed version range
  (`requiredMinimumVersion` / `requiredMaximumVersion`).
- **A path deny rule is hygiene, not a security boundary — and v2.1.251 is where that stopped
  being theoretical.** That release fixed four ways the permission layer could be walked around:
  Read/Write/Edit followed a **symlink swapped inside the working directory after the check had
  passed**; **Grep and Glob never applied `Read(...)` deny rules to files reached through a
  symlinked search path** at all; the Workflow tool read (and quoted in errors) a `scriptPath`
  outside what the session may read before its permission check ran; and Bash auto-approved
  commands assigning an arithmetic expression to an integer variable (`OPTIND=1/0`). Two
  consequences for a harness. **Keep the client current** — a deny rule's enforcement is a
  property of the release, not of the rule. And **do not treat `deny` as containment against
  anything adversarial**: it fences honest mistakes, while OS-level enforcement is the sandbox
  (this is the same "contain at the environment layer, steer at the model layer" split that
  `evidence-base.md` cites first-party).
- **`--restricted` / `CLAUDE_CODE_RESTRICTED=1`** (v2.1.248) — the shipped hard-floor profile:
  removes the built-in tools that run commands or code plus `WebFetch` (unless named in
  `--tools`), keeps file tools inside the working directory, refuses `bypassPermissions`, and
  **ignores user, project and local settings files**. For "let it read and reason, never let it
  execute" this is now a flag, not a bespoke allowlist — reach for it before hand-building a
  read-only profile out of deny rules. Note what the last clause costs: your own settings do not
  apply either, so a guard hook you rely on is *also* off in that mode.
- **Isolation is enforced for Bash too, in every session type**: a worktree-isolated session (and
  its subagents) can no longer run destructive git commands against the main checkout — isolation
  covers file edits *and* shell. Related hardening you get for free (so do not hand-roll it):
  crafted Bash commands can no longer hide parts of themselves from the permission check
  (zsh `[[ ]]` conditionals, tab/invisible-Unicode padding of the approval dialog), an agent
  definition's `bypassPermissions` no longer overrides an org policy that disables it, workflow
  scripts can no longer escape their sandbox via dynamic `import()`, and a sandbox `denyRead`/
  `denyWrite` entry written with a trailing slash is no longer silently bypassable.
- Sandboxed credentials can be **masked rather than denied** (`mode: "mask"` on Linux/WSL —
  sandboxed commands read a sentinel while the proxy substitutes the real value on egress;
  `extract` regexes, `decode: "jwt"` with `maskClaims`, `awsPairs`/`sigv4` re-signing; needs
  `network.tlsTerminate`, honoured only from user/managed/`--settings` scope).
- **`claudeMd` as a managed setting** puts CLAUDE.md content directly inside `managed-settings.json`
  instead of deploying a file, and it **cannot be excluded** by `claudeMdExcludes`. The division
  first-party draws is worth carrying into any harness design: **settings enforce, CLAUDE.md
  steers** — blocking tools/commands/paths, sandbox isolation, env and login belong in settings;
  code style, data-handling reminders and behavioural instructions belong in the managed CLAUDE.md.
  A rule written on the wrong side of that line is either unenforceable or unreadable.
- **A managed policy can switch off non-plugin customization entirely** —
  `strictPluginOnlyCustomization` — granular, so a policy can lock `skills` / `agents` / `hooks` /
  `mcp` separately — blocks
  `~/.claude/{surface}/`, the project's `.claude/{surface}/`, `settings.json` hooks and `.mcp.json`
  for any of `skills` · `agents` · `hooks` · `mcp`, while plugin-provided and managed sources keep
  loading. Two consequences for a harness: **shipping it as a plugin is the only form that survives
  the policy**, and "my skill is invisible / my hook never fires" inside a managed org is a policy
  fact to rule out before debugging the config.
- **`--safe-mode`** / `CLAUDE_CODE_SAFE_MODE` — start with all customizations (CLAUDE.md,
  plugins, skills, hooks, MCP) disabled: the clean A/B baseline for "model vs harness"
  questions (used by the audit and strip rituals). `disableBundledSkills` /
  `CLAUDE_CODE_DISABLE_BUNDLED_SKILLS` hides bundled skills, workflows, and built-in slash
  commands from the model (context-budget control).
- **Native destructive-command block, and it is an *auto-mode* mechanism (v2.1.183/193).** The
  release note is headed "Improved **auto mode** safety": `git reset --hard` / `checkout -- .` /
  `clean -fd` / `stash drop` are blocked **when you didn't ask to discard local work**,
  `commit --amend` when the commit wasn't made by the agent this session, and `terraform` /
  `pulumi` / `cdk destroy` **unless you asked for the specific stack**. Three conditions, not a
  blanket ban — and none of it is a circuit breaker: the binary's breaker table carries only
  `dangerousRemoval`, `backgroundOperator` and `suspiciousWindowsPath`. **Measured**: in `manual`
  mode with `Bash(git reset:*)` allowed, `git reset --hard` ran and destroyed uncommitted work.
  So: skip a custom DENY rule for these **while the project works in auto mode**; a project that
  runs in `manual`, `acceptEdits` or `bypassPermissions` has no native block here and a deny rule
  is the only guard. The auto-mode classifier is now **diagnosable and configurable**: the denial
  reason surfaces in the transcript, a toast, and `/permissions` → recent denials (v2.1.193); keys
  `autoMode.classifyAllShell` + `autoMode.{allow, soft_deny, hard_deny, environment}` with
  `$defaults` inheritance; the classifier model defaults to Sonnet 5, pinned per session
  (v2.1.210). **Where it runs changed in v2.1.278**: for Claude API and Enterprise users, and on
  Bedrock / Vertex / Foundry / gateways, auto mode now defaults to the **server-side** classifier,
  which does not bill classifier overhead and warns on billed fallback
  (`CLAUDE_CODE_AUTO_MODE_SERVER=0` opts out on the third-party providers); `/status` carries an
  `Auto mode server` row saying which side this session uses. A **PreToolUse hook `ask` now floors the auto-mode decision
  at a prompt** for unsandboxed Bash (v2.1.211) — the classifier can no longer silently
  downgrade a hook `ask`, so a guard hook stays authoritative over auto mode (consistent with
  "hooks are deterministic enforcement", above). **Since v2.1.207 `autoMode` is no longer read
  from the repo-resident `.claude/settings.local.json`** — put these keys in `~/.claude/settings.json`. `!`-commands now auto-provoke a model response by default — revert with
  `respondToBashCommands: false`.
- **The classifier absorbed more of the prompt surface (v2.1.218).** The dangerous-`rm`,
  background-`&` and suspicious-Windows-path checks **no longer open a permission dialog** — the
  auto-mode classifier adjudicates them (the binary's circuit-breaker table marks all three
  `classifierRouted`; `dangerousRemoval` is additionally `bypassImmune`, the other two are not).
  Plan mode
  under auto no longer prompts for
  Bash the static analyzer can't prove read-only. Consequence for a harness: fewer of these
  reach the operator as a prompt, so a project rule that *counts on the dialog appearing*
  should become a `deny`/`ask` rule or a hook (which still floors the decision, above).
- **Bash permission parsing was tightened in v2.1.214–216** — commands over 10,000 characters
  always prompt; fail-closed on file-descriptor redirect forms the analyzer parses differently
  than bash; `docker`/Podman daemon-redirect flags (`--url`, `--connection`, `--identity`,
  remote mode) now prompt; and **non-ASCII word-boundary parsing was aligned with real shell
  parsing**. That last one is the one to carry into any project guard that inspects the command
  string itself — a hand-rolled matcher still splits on its own idea of a word boundary.
- **Sandbox keys**: `sandbox.filesystem.disabled` (v2.1.216 — skip filesystem isolation while
  keeping network/seccomp isolation; macOS + Linux/WSL only, ignored on native Windows, and
  managed settings can lock it) and `sandbox.network.strictAllowlist` (v2.1.219 — deny
  non-allowlisted hosts for sandboxed commands **without prompting**).

## Out of scope (API-only — never propose for a CLI-subscription harness)

managed-agents (Memory stores, Dreams, Outcomes), beta headers, `--bare`, `--max-budget-usd`,
prompt-caching / batch / files / citations API, mid-conversation `role:"system"` cache control,
`ANTHROPIC_API_KEY`-dependent flows. (`--bare` is API-only because it **skips OAuth entirely** —
auth must come from `ANTHROPIC_API_KEY` / `apiKeyHelper`, per the headless doc.)

**Watch (re-checked 2026-06-17 first-party; still true 2026-07-15):** the announced
June 15, 2026 move of subscription `claude -p` / Agent SDK usage onto a separate monthly
**Agent SDK credit** was **paused the day it was to take effect** ("nothing changes for
now" — Anthropic Help Center; third split attempt). Headless `claude --print` on an OAuth
subscription (CI, verify-phases) is **fully intact** and draws from normal subscription
limits. `--bare` remains slated as a future default for `-p` (the one mode that skips
OAuth → needs an API key). Re-verify on the next Anthropic advance notice — this watch
item is open, not closed.
