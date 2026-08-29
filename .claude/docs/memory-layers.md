---
owner: @harness
last-updated: 2026-08-29
---

# Memory layers (harness reference)

Канонические слои памяти AI-агента и где они находятся в harness'е. Reference doc, не описание роли main thread'а (последнее — CLAUDE.md).

Источники (полный каталог — `external-sources.md` Блоки 1, 5): Anthropic context-engineering + harnesses-for-long-running-agents + multi-agent-research; Externalization (arXiv 2604.08224) — unifying frame. Empirical context — devlog #38.

**Рамка** (Externalization): capability мигрирует **Weights → Context → Harness**. Ключевое для памяти — **state ≠ context** и **файловая система = единственный authoritative state-record** (агент читает курированные снапшоты, не историю; «файл durable, контекст эфемерен»), а storage / state-transitions держи **детерминированными** — вероятностной оставляй только ingestion/interpretation (LLM-судья принимает ~63% неверных ответов, arXiv 2604.11364). Наши memory-файлы это уже кодируют: frontmatter `description` = retrieval-key, body = факт (*source-backed / verbatim*, не перефраз), `[[links]]` = update-metadata. Learned-pipeline не строим (out of scope).

## 5-layer + inter-agent model

| Layer | Что | Где у нас | Persistence | Owner |
|---|---|---|---|---|
| L0 in-session scratchpad | runtime task list | `TaskCreate`/`TaskUpdate` (built-in) | session | session |
| L1 procedural | как работать, инварианты, action-skills | `.claude/CLAUDE.md`, `.claude/rules/`, `.claude/skills/{devlog,update-plan-progress}/` | cross-session, в git | repo |
| L2 episodic | session summaries, recurring patterns | `~/.claude/projects/<hash>/memory/MEMORY.md` + per-topic `.md` | cross-session, user-scoped | user |
| L3 durable artifacts | what happened, why | `.claude/devlog/entries/*.md` + `index.json` | cross-session, в git | repo |
| L4 semantic / decisions | architectural rationale | `.claude/docs/principles.md` (active), `.claude/docs/archive/` (frozen) | cross-session, в git | repo |
| inter-agent | filesystem blackboard | `.claude/audits/<slug>/*.json` — вердикт свежей сессии; внутри dynamic workflow состояние несут сами агент-узлы | per-deliverable, transient | repo |

## Curation rituals

- **L2 → L1 promotion**: `/remember` skill после сессий с ≥3 memory writes или ≥2 корректирующими feedback'ами — чтобы recurring patterns переходили в CLAUDE.md / rules, а не оставались user-scoped только. Каждое promotion требует явного user-confirmation.
- **L0 → L3 promotion**: после значимого изменения — devlog entry через `devlog` skill, регенерация `index.json` через `devlog-reindex`.
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

Носитель паттерна — нативный, своей оркестрации harness не держит:

- **Свежая сессия, промптнутая рефьютить** (не авторская) → JSON-вердикт в `.claude/audits/<slug>/`. Дефолтная ступень для deliverable'а; правило разрешения конфликтов — «исполненное доказательство сильнее прочитанного», поэтому сессию просят не только читать scope, но и **исполнить живой стек**.
- **`/code-review ultra`** → флот на изменении (working diff / PR), результат сводит сам built-in.
- **Dynamic workflow** (`ultracode`) → узлы пишут в собственные артефакты, скрипт сводит; для codebase-scale sweep, где одного контекста не хватает.

Opt-in: вызывает оператор, за пределами авторского контекста.

## Что специально НЕ делаем

- Не персистим `TaskCreate`/`TaskUpdate` state между сессиями — это L0 (session-scoped) by design; cross-session goals переходят в L3 (devlog) или progress.md.
- Не делаем nested CLAUDE.md per subdir (Boris допускает lazy-load, у нас не нужен — single repo, плоская структура).
- Не делаем semantic search над devlog — `grep` справляется при ~40 entries; пересмотреть при ≥200.
