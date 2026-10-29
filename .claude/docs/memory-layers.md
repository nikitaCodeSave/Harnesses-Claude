---
owner: @harness
---

# Memory layers (harness reference)

Канонические слои памяти AI-агента и где они находятся в harness'е. Reference doc, не описание роли main thread'а (последнее — CLAUDE.md).

Источники (полный каталог — `external-sources.md` Блоки 1, 5): Anthropic context-engineering + harnesses-for-long-running-agents + multi-agent-research; Externalization (arXiv 2604.08224) — unifying frame.

**Рамка** (Externalization): capability мигрирует **Weights → Context → Harness**. Ключевое для памяти — **state ≠ context** и **файловая система = единственный authoritative state-record** (агент читает курированные снапшоты, не историю; «файл durable, контекст эфемерен»), а storage / state-transitions держи **детерминированными** — вероятностной оставляй только ingestion/interpretation (LLM-судья принимает ~63% неверных ответов, arXiv 2604.11364). Авто-память Claude Code это правило нарушает: что и когда сохранить, решает модель, вне ревью и вне репозитория. Поэтому она выключена, а состояние держат артефакты проекта в git ([ADR 0006](adr/0006-arkhitektura-artefaktov-proekta-i-ikh-zhiznennyy-tsikl.md)). Learned-pipeline не строим (out of scope).

## 5-layer + inter-agent model

| Layer | Что | Где у нас | Persistence | Owner |
|---|---|---|---|---|
| L0 in-session scratchpad | runtime task list | **на текущем поколении моделей пуст**: task-list тулы и `TodoWrite` не выдаются без явного opt-in (`CLAUDE_CODE_ENABLE_TODO_TOOLS=1`) — модель ведёт многошаговую работу без письменного чеклиста; версии и точные условия — `native-capabilities.md` | session | session |
| L1 procedural | как работать, инварианты, action-skills | `.claude/CLAUDE.md`, `.claude/rules/` (проектных skills нет) | cross-session, в git | repo |
| L2 episodic | session summaries, recurring patterns | **пуст по решению**: авто-память выключена (`autoMemoryEnabled: false`). По умолчанию она включена; модель пишет её сама и держится за факты, которые проект уже пересмотрел. Повторяющееся становится правилом L1 или решением L4 ([ADR 0006](adr/0006-arkhitektura-artefaktov-proekta-i-ikh-zhiznennyy-tsikl.md)) | — | — |
| L3 durable artifacts | what happened, why | сообщения коммитов (что изменилось), `.claude/benchmark/*/RESULTS.md` (замеры); `.claude/devlog/` — закрытый замороженный журнал ([ADR 0001](adr/0001-devlog-zakryt-resheniya-v-adr.md)) | cross-session, в git | repo |
| L4 semantic / decisions | architectural rationale | `.claude/docs/adr/` (действующие решения), `.claude/docs/principles.md` (active), `.claude/docs/archive/` (frozen) | cross-session, в git | repo |
| inter-agent | filesystem blackboard | `.claude/audits/<slug>/*.json` — вердикт свежей сессии; внутри dynamic workflow состояние несут сами агент-узлы | per-deliverable, transient | repo |

## Curation rituals

- **Поправка → L1 или L4**: поправку оператора, которой должна следовать будущая работа, main thread в той же сессии предлагает записать — строкой `CLAUDE.md` / rule или ADR — и пишет после подтверждения. Других носителей между сессиями, кроме репозитория, нет.
- **L0 → L3 promotion**: после значимого изменения — описательный коммит; замер — в `RESULTS.md` своего стенда. Журнала сессий нет ([ADR 0001](adr/0001-devlog-zakryt-resheniya-v-adr.md)).
- **Работа в полёте → L3**: носитель — открытая спека: она говорит, что должно стать правдой и чего ещё нет. Отдельный progress-журнал не заводится; где проект уже ведёт журнал — встречать его там.
- **L4 capture**: ADR в `.claude/docs/adr/` в той же сессии, где принято решение, которому должна следовать будущая работа (порог — docs-discipline rule 6). Отменяется новым ADR; у отменённого меняется только строка `Status:`.

## Anti-patterns

- **Vendor memory stores** (Letta/Mem0/Zep/vector DB) — overkill для CLI meta-harness, filesystem + git справляются на нашем масштабе.
- **Shared blackboard для inter-agent внутри одной сессии** — Cognition explicit против; subagents read/investigation only, main thread owns writes.
- **Self-описывающие skills/agents/docs** (повторяют CLAUDE.md о роли main thread'а) — anti-pattern из ADR-017.
- **Multi-step memory pipeline** (write → embed → retrieve → synthesise) — premature; structured notes per Anthropic достаточны.
- **Авто-хуки, форсящие запись прогресса** (PreToolUse / PostToolUse) — decision point должен оставаться у разработчика и main thread'а; single-incident в invariant не превращается.

## Inter-agent communication — наш filesystem-blackboard паттерн

Соответствует Anthropic multi-agent-research-system: subagents пишут прямо в filesystem, минуя «game of telephone» через main thread.

Носитель паттерна — нативный, своей оркестрации harness не держит:

- **Свежая сессия, промптнутая рефьютить** (не авторская) → JSON-вердикт в `.claude/audits/<slug>/`. Дефолтная ступень для deliverable'а; правило разрешения конфликтов — «исполненное доказательство сильнее прочитанного», поэтому сессию просят не только читать scope, но и **исполнить живой стек**.
- **`/code-review ultra`** → флот на изменении (working diff / PR), результат сводит сам built-in.
- **Dynamic workflow** (`ultracode`) → узлы пишут в собственные артефакты, скрипт сводит; для codebase-scale sweep, где одного контекста не хватает.

Opt-in: вызывает оператор, за пределами авторского контекста.

## Что специально НЕ делаем

- Не персистим task-list state между сессиями — это L0 (session-scoped) by design; cross-session goals живут в открытой спеке, решения — в ADR. На текущем поколении L0 пуст by default, и это усиливает то же правило: in-flight состояние живёт на диске, а не в тулах сессии.
- Не делаем nested CLAUDE.md per subdir (Boris допускает lazy-load, у нас не нужен — single repo, плоская структура).
- Не делаем semantic search над ADR и архивом devlog — `grep` справляется на этом масштабе.
