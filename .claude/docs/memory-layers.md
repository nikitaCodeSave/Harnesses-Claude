---
owner: @harness
last-updated: 2026-06-10
---

# Memory layers (harness reference)

Канонические слои памяти AI-агента и где они находятся в harness'е. Reference doc, не описание роли main thread'а (последнее — CLAUDE.md).

Источники: Anthropic [effective context engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents) / [harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) / [multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system); Boris Cherny [how-Boris-uses-claude-code](https://howborisusesclaudecode.com/); Lance Martin [context engineering for agents](https://rlancemartin.github.io/2025/06/23/context_engineering/); LangChain [LangMem](https://blog.langchain.com/langmem-sdk-launch/); Cognition [don't build multi-agents](https://cognition.ai/blog/dont-build-multi-agents); [Externalization in LLM Agents (arXiv 2604.08224, 2026-04)](https://arxiv.org/html/2604.08224v1) — unifying frame. Empirical context — devlog #38.

**Теоретическая рамка** ([Externalization](https://arxiv.org/html/2604.08224v1)): capability мигрирует наружу по слоям **Weights → Context → Harness** (из параметров в инфраструктуру). Ключевой принцип для памяти — **state ≠ context** и **файловая система как единственный authoritative state-record**: агент читает *курированные снапшоты*, не историю. Это ровно дисциплина `claude-progress.txt` / devlog ниже — «файл durable, контекст эфемерен». Соседний эмпирический факт ([arXiv 2604.11364](https://arxiv.org/pdf/2604.11364)): LLM-судья принял **63% намеренно неверных ответов** → держи storage / state-transitions детерминированными, вероятностной оставляй только ingestion/interpretation. Параллельная линия ([EMBER, arXiv 2606.05894](https://arxiv.org/abs/2606.05894), июнь 2026): юнит durable-памяти — **evidence capsule = дословная выдержка источника + retrieval-key + update-metadata**, и фиксированный budget форсит приоритизацию ДО появления запроса. Наши memory-файлы уже это: frontmatter `description` = retrieval-key, body = факт (держи *source-backed / verbatim*, не перефраз — это и даёт groundability), `[[links]]` = update-metadata. **Method (learned RL-policy) out of scope** — переносим только принцип; learned-pipeline не строим (см. anti-patterns).

## 5-layer + inter-agent model

| Layer | Что | Где у нас | Persistence | Owner |
|---|---|---|---|---|
| L0 in-session scratchpad | runtime task list | `TaskCreate`/`TaskUpdate` (built-in) | session | session |
| L1 procedural | как работать, инварианты, action-skills | `.claude/CLAUDE.md`, `.claude/rules/`, `.claude/skills/{devlog,update-plan-progress}/` | cross-session, в git | repo |
| L2 episodic | session summaries, recurring patterns | `~/.claude/projects/<hash>/memory/MEMORY.md` + per-topic `.md` | cross-session, user-scoped | user |
| L3 durable artifacts | what happened, why | `.claude/devlog/entries/*.md` + `index.json` | cross-session, в git | repo |
| L4 semantic / decisions | architectural rationale | `.claude/docs/principles.md` (active), `.claude/docs/archive/` (frozen) | cross-session, в git | repo |
| inter-agent | filesystem blackboard | `.claude/audit/<slug>/AUDIT-{EVIDENCE,PROCESS,REFUTER,VERDICT}.json` через `/external-audit` (плагин claude-code-harness) | per-deliverable, transient | repo |

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

Текущая реализация — `/external-audit` плагина `claude-code-harness` (3 роли параллельно, каждая пишет свой JSON-вердикт на диск, adjudicator сводит):

- **evidence-executor** → `.claude/audit/<slug>/AUDIT-EVIDENCE.json` (исполняет живой стек)
- **process-auditor** → `AUDIT-PROCESS.json` (git history / scope / red→green, без исполнения)
- **code-refuter** → `AUDIT-REFUTER.json` (опровергает код)
- **adjudicator** (main thread свежей сессии) → `AUDIT-VERDICT.json` по правилу «исполненное доказательство сильнее прочитанного»

Opt-in: оператор вызывает в свежей (не авторской) сессии. Предшественник — PREMORTEM/EVIDENCE/CRITIC blackboard с discovery-critic + `/critique` + discovery-gate hook — удалён 2026-06-11 как superseded (история: devlog #62/#65/#95).

## Что специально НЕ делаем

- Не персистим `TaskCreate`/`TaskUpdate` state между сессиями — это L0 (session-scoped) by design; cross-session goals переходят в L3 (devlog) или progress.md.
- Не делаем nested CLAUDE.md per subdir (Boris допускает lazy-load, у нас не нужен — single repo, плоская структура).
- Не делаем semantic search над devlog — `grep` справляется при ~40 entries; пересмотреть при ≥200.
