---
owner: @nikitaCodeSave
last-updated: 2026-06-07
status: active
---

# Orchestration workflow — Claude Code 2.1.169

> Operational layer для **parallel sessions / worktrees / dispatch flags / multi-process coordination**. Сюда идём когда задача требует больше одного thread'а в полёте — но без cloud-offload (см. [workflow-cloud-offload.md](workflow-cloud-offload.md)).
>
> Companion к [workflow.md](workflow.md), [builtins-inventory.md](builtins-inventory.md), [multi-agent.md](multi-agent.md).

## TL;DR

Parallel-session story **stabilized** в v2.1.139-143. Три canonical surfaces:

1. **Worktree** (`-w` + `--tmux` + `worktree.baseRef` + `worktree.bgIsolation`) — isolated working copies одного repo
2. **`claude agents`** subsystem с dispatch flags (v2.1.142) — background agent fleet
3. **`--remote-control` / `--from-pr` / `--fork-session`** — session lifecycle controls

Empirical positioning (per [arXiv 2604.18071](https://arxiv.org/abs/2604.18071) — 70-project survey): **multi-level recursive subagent = 12.9% корпуса**. Наша restraint-policy (main thread owns end-to-end) — **unusual but deliberate trade-off**, не default failure.

## Decision tree

```
Нужны parallel feature branches без cross-contamination?
  └─ Yes → -w worktree (isolated FS view)

Нужно несколько independent sessions параллельно?
  └─ Yes → claude agents с dispatch flags

Возобновить session linked to PR?
  └─ Yes → --from-pr <n> или --resume <pr-url>

Session нужна с tmux pane layout?
  └─ Yes → -w + --tmux

Inter-agent коммуникация через UI (не только tool)?
  └─ Yes → --brief (SendUserMessage)

Multi-dir access?
  └─ Yes → --add-dir <dirs...>

Structured output для downstream pipeline?
  └─ Yes → --output-format=stream-json + --json-schema
```

---

## Worktree (`-w`)

### Basics

```bash
claude -w feature-x          # create worktree, new session
claude -w                    # auto-named worktree
claude --worktree --tmux     # with tmux pane management
```

State: `~/.claude/worktrees/` + git's `.git/worktrees/`.

### Settings (project-scoped, `.claude/settings.json`)

| Setting | Default (v2.1.143) | What it does |
|---------|--------------------|--------------|
| `worktree.baseRef` | `origin/<default>` (since w15) | Branch base. Was `HEAD` in v2.1.128-132 (regression, reverted) |
| `worktree.bgIsolation` | `"worktree"` (default) / `"none"` (since v2.1.143) | Whether background tasks get isolated FS view |
| `--tmux` mode | Native iTerm2 panes if available; `--tmux=classic` для traditional tmux | Pane orchestration |

### When to use

- **Parallel feature branches** — review одну, разрабатываешь другую
- **Experimental refactor** — discardable если не получилось (`--worktree experimental && rm -rf`)
- **High-stakes change** — isolation от main working tree
- **Subagent isolation** — `Agent({isolation: "worktree"})` для quality verification

### Worktree caveats

- Worktree сессии разделяют git history → плохо для concurrent merges
- `.claude/` shared между worktrees (config inherited), но `~/.claude/projects/<slug>/` отдельный
- Auto-cleanup если agent сделал no changes (per Agent tool description)
- **`EnterWorktree` switches between Claude-managed worktrees mid-session** (v2.1.157); managed worktrees оставляются **unlocked** при finish, так что `git worktree remove`/`prune` их чистят (v2.1.157)

---

## `claude agents` subsystem (background fleet)

`claude agents` subcommand manages **background agents**: sessions running asynchronously, dispatched from CLI, observable via `claude agents` UI (since v2.1.139 «agent view»).

### Dispatch flags (all added in v2.1.142, 2026-05-14)

```bash
claude agents dispatch <agent> \
  --add-dir <dirs...> \
  --settings <path-or-json> \
  --mcp-config <files...> \
  --plugin-dir <path> \
  --permission-mode <plan|auto|...> \
  --model <name> \
  --effort <xhigh|...> \
  --dangerously-skip-permissions
```

### Background session settings

- **Background sessions preserve model+effort after waking** (v2.1.143)
- **Background sessions honor `permissions.defaultMode`** из settings.json (v2.1.142)
- **`Shift+Tab`** в attached agent session cycles modes включая auto (v2.1.143)
- **`settings.json` `agent` field honored** для dispatched sessions; `--agent <name>` override (v2.1.157)
- **`claude agents --json` adds `waitingFor`** — на чём заблокирована waiting-session (e.g. permission prompt, v2.1.162); rows show `done/total` при fan-out (v2.1.161). **v2.1.169:** `--json` теперь включает blocked/just-dispatched sessions + поля `id` и `state`; флаг `--all` добавляет completed — точнее observability фронта fan-out'а.
- **Cross-session `SendMessage` relay не несёт user-authority** (v2.1.166) — receiver отклоняет relayed permission requests, auto mode их блокирует. Security-инвариант для любого multi-session fan-out.
- **Background sessions заранее знают про shared-checkout block** (v2.1.169) — до `EnterWorktree` edits в shared checkout заблокированы, и сессии об этом сообщается заранее (нет впустую отклонённого первого edit). Усиливает worktree-isolation-first discipline выше.

### When to dispatch vs single CLI

| Need | Use |
|------|-----|
| Single iteration of task | Standard `claude -p "..."` |
| Long-running agent fleet | `claude agents dispatch` |
| Parallel exploration of independent angles | Multiple `Agent` calls в main thread (см. [multi-agent.md](multi-agent.md)) |
| CI/CD integration | `claude agents dispatch` + `--output-format=json` + `--json-schema` |

### Settings inheritance

`claude agents` dispatch flags **override** project `.claude/settings.json` per-invocation. State: `~/.claude/sessions/` + `~/.claude/tasks/`.

---

## Session lifecycle controls

### `--continue` / `-c`

Continue last session in current cwd. Default — preserves session ID.

### `--resume` / `-r`

```bash
claude -r                          # picker
claude -r <id>                     # specific ID
claude -r <pr-url>                 # PR URL (week 18 feature)
```

### `--from-pr`

```bash
claude --from-pr 1234              # resume session linked to PR #1234
claude --from-pr <pr-url>          # PR URL
claude --from-pr                   # interactive picker
```

### `--fork-session`

Use **с `--resume` или `--continue`**: creates new session ID instead of reusing original. Useful когда want branching session history.

### `--session-id <uuid>`

Explicit session ID. Power-user feature для scripted dispatch.

---

## Inter-session / inter-process surfaces

### `--brief` (SendUserMessage)

Enables `SendUserMessage` tool — agent can ping user mid-flight. Use cases:
- Long autonomous task that needs ad-hoc clarification
- Routine waking up с questionable state
- Background agent surfacing decision point

Без `--brief` — agent commits decisions silently или blocks.

### `--remote-control`

Remote Control session: external tool drives Claude Code. State persists. Useful для:
- IDE integration (VS Code / JetBrains)
- CI orchestration где external system sequences calls
- Custom UI на top of CLI

### `--add-dir <dirs...>`

Additional directory access **at startup**. Runtime equivalent: `/add-dir` slash command.

Use cases:
- Cross-repo refactor
- Reference monorepo вне cwd
- Read-only fixture / data access

### `--json-schema <schema>`

JSON Schema for structured output validation (works с `--print`). Used in CI/CD pipelines где downstream expects structured data:

```bash
claude --print --json-schema '{"type":"object","properties":{"verdict":{"enum":["pass","fail"]}}}' \
       "Review PR #123 and return verdict"
```

### `--include-hook-events` (stream-json only)

Emit hook lifecycle events for observability tooling. Use for:
- Build dashboards / telemetry
- Hook debugging
- Audit trails

---

## Anti-patterns

| Anti-pattern | Source | Replacement |
|--------------|--------|-------------|
| Multi-level recursive subagent для most coding | [arXiv 2604.18071](https://arxiv.org/abs/2604.18071) — 12.9% corpus; Anthropic "ill-suited" | Main thread orchestration |
| Parallel writes к same files через worktree | git merge hell | Sequential или separate features |
| `claude agents dispatch` для one-shot lookup | Spawn overhead | `claude --print "..."` |
| `--remote-control` для local dev | Adds overhead | Standard interactive session |
| `--add-dir /` (root grant) | Permission blast radius | Specific dirs only |
| Worktree без cleanup | Disk space + git confusion | Auto-cleanup + manual `git worktree prune` |

---

## Empirical positioning

70-project agent harness survey (arXiv [2604.18071](https://arxiv.org/abs/2604.18071), Hu Wei, 2026-04-20):

| Pattern | % of corpus |
|---------|-------------|
| Tool-based Delegation | 17.1% |
| Multi-level Recursive | **12.9%** |
| Pipeline/Stage | 1.4% |

«Deeper coordination pairs with more explicit context services»; «stronger execution environments with more structured governance.»

**Implication для нашего harness'а**: main-thread orchestration policy (subagent spawn only при isolation/parallelism/auto-compact-rescue) — deliberate position, не default. Multi-level recursive ≠ universally bad; для production-critical / multi-day autonomous работы opt-in допустим (D-022 в [principles.md](principles.md)).

---

## Sources

- [github.com/anthropics/claude-code releases v2.1.139-143](https://github.com/anthropics/claude-code/releases) — dispatch flags, worktree settings
- [code.claude.com/docs/en/agent-view](https://code.claude.com/docs/en/agent-view) — agent view feature
- [claude.com/blog/agent-view-in-claude-code](https://www.claude.com/blog/agent-view-in-claude-code) (2026-05-11)
- arXiv [2604.18071 — Architectural Design Decisions in AI Agent Harnesses](https://arxiv.org/abs/2604.18071) (Hu Wei, 70-project survey)
- arXiv [2604.14228 — Dive into Claude Code](https://arxiv.org/abs/2604.14228) — subagent isolation pattern via worktree
- [multi-agent.md](multi-agent.md) — full subagent discipline (§7 patterns, §10 verification checklist)
- [principles.md](principles.md) — D-022 opt-in subagent isolation rationale
- Live evidence: `claude agents --help`, `claude --help` (flags inventory)
