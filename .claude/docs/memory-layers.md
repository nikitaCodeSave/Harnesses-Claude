---
owner: @harness
last-updated: 2026-05-12
---

# Memory layers (harness reference)

Канонические слои памяти AI-агента и где они находятся в harness'е. Reference doc, не описание роли main thread'а (последнее — CLAUDE.md).

Источники: Anthropic [effective context engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents) / [harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) / [multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system); Boris Cherny [how-Boris-uses-claude-code](https://howborisusesclaudecode.com/); Lance Martin [context engineering for agents](https://rlancemartin.github.io/2025/06/23/context_engineering/); LangChain [LangMem](https://blog.langchain.com/langmem-sdk-launch/); Cognition [don't build multi-agents](https://cognition.ai/blog/dont-build-multi-agents). Empirical context — devlog #38.

## 5-layer + inter-agent model

| Layer | Что | Где у нас | Persistence | Owner |
|---|---|---|---|---|
| L0 in-session scratchpad | runtime task list | `TaskCreate`/`TaskUpdate` (built-in) | session | session |
| L1 procedural | как работать, инварианты, action-skills | `.claude/CLAUDE.md`, `.claude/rules/`, `.claude/skills/{devlog,project-docs-bootstrap}/` | cross-session, в git | repo |
| L2 episodic | session summaries, recurring patterns | `~/.claude/projects/<hash>/memory/MEMORY.md` + per-topic `.md` | cross-session, user-scoped | user |
| L3 durable artifacts | what happened, why | `.claude/devlog/entries/*.md` + `index.json` | cross-session, в git | repo |
| L4 semantic / decisions | architectural rationale | `.claude/docs/principles.md` (active), `.claude/docs/archive/` (frozen) | cross-session, в git | repo |
| inter-agent | filesystem blackboard | `PREMORTEM.md` → `EVIDENCE.md` → `CRITIC.md` через [discovery-critic](.claude/agents/discovery-critic.md) | per-deliverable, transient | repo |

## Curation rituals

- **L2 → L1 promotion**: `/remember` skill после сессий с ≥3 memory writes или ≥2 корректирующими feedback'ами — чтобы recurring patterns переходили в CLAUDE.md / rules, а не оставались user-scoped только. Каждое promotion требует явного user-confirmation.
- **L0 → L3 promotion**: после значимого изменения — devlog entry через `devlog` skill, регенерация `index.json` через `python3 .claude/devlog/rebuild-index.py`.
- **Long-running task → L3**: convention `progress.md` в `.claude/progress/<slug>.md` для задач с wall-clock >1ч или ≥3 distinct decision points; после завершения конвертируется в devlog entry (см. `.claude/rules/docs-discipline.md` rule 7).
- **L4 capture**: ADR при решениях, объяснение которых в Slack заняло бы >5 минут (per docs-discipline rule 6).

## Anti-patterns

- **Vendor memory stores** (Letta/Mem0/Zep/vector DB) — overkill для CLI meta-harness, filesystem + devlog справляются на нашем масштабе.
- **Shared blackboard для inter-agent внутри одной сессии** — Cognition explicit против; subagents read/investigation only, main thread owns writes.
- **Self-описывающие skills/agents/docs** (повторяют CLAUDE.md о роли main thread'а) — anti-pattern из ADR-017.
- **Multi-step memory pipeline** (write → embed → retrieve → synthesise) — premature; structured notes per Anthropic достаточны.
- **Авто-хуки на progress.md** (PreToolUse / PostToolUse, которые форсят запись) — decision point должен оставаться у разработчика и main thread'а; single-incident в invariant не превращается.

## Inter-agent communication — наш filesystem-blackboard паттерн

Соответствует Anthropic multi-agent-research-system: subagents пишут прямо в filesystem, минуя «game of telephone» через main thread.

- **main agent** → `PREMORTEM.json` (≥4 failure modes, ≥3 distinct categories) + `EVIDENCE.json` (≥3 real runs)
- **discovery-critic** (fresh-context subagent, spawned via `/critique`) → читает оба + код → пишет `CRITIC.json` (schema v2.0 with class-based verdict)
- **`/critique` slash command** → spawns the critic, parses CRITIC.json via jq, applies class-based rubric (CRITICAL_UNADDRESSED severity-dominates rule)
- **discovery-gate.sh** (Stop hook, optional) → pre-/critique reminder: nags about missing PREMORTEM/EVIDENCE, never blocks (always exit 0)

Pattern is opt-in via `/critique` invocation (always available, project-portable). Hook reminder активен только под `EVALUATOR_GATE_ACTIVE=1` или `.claude/.evaluator-active` marker — outside that, normal dev flow without nudges.

## Что специально НЕ делаем

- Не персистим `TaskCreate`/`TaskUpdate` state между сессиями — это L0 (session-scoped) by design; cross-session goals переходят в L3 (devlog) или progress.md.
- Не делаем nested CLAUDE.md per subdir (Boris допускает lazy-load, у нас не нужен — single repo, плоская структура).
- Не делаем semantic search над devlog — `grep` справляется при ~40 entries; пересмотреть при ≥200.
