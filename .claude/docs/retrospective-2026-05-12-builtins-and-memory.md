---
owner: @harness
last-updated: 2026-05-12
status: complete
type: session-retrospective
---

# Retrospective: Claude Code built-ins + memory architecture (2026-05-12)

Один-сессионный анализ. Цель: зафиксировать принятые решения, эмпирические подтверждения, anti-patterns и векторы дальнейшего роста — для будущего анализа качества разработки в этом harness'е.

## 1. Контекст и trigger

**Входное состояние (начало сессии)**:
- Релиз Claude Code 2.1.139 (11 мая 2026) ввёл встроенные `/goal` (loop-to-condition внутри сессии) и `claude agents` (TUI для фоновых сессий).
- Пользователь принёс чужой текст про «мета-роль агента», предлагающий «полноценный рефакторинг» harness'а под built-ins.
- Контекст harness'а: meta-orchestrator репо на CLI-подписке (no Anthropic API), foundational principle «минимум обвязки даёт максимум продуктивности под Opus 4.7».

**Trigger от пользователя**: «Ознакомься с обновлениями claude code и подходящим для нашей задачи функционалом… выполни полноценный рефакторинг проекта».

**Ключевой выбор подхода**: **empirical-first** вместо принятия чужого guidance как ТЗ. Соответствует saved feedback'у [[feedback_grow_with_community]] — research first-party + community перед опорой на внутренние артефакты.

## 2. Решения по теме built-ins (Claude Code 2.1.139)

### 2.1 `/goal` — позиция и применимость

**Эмпирически подтверждено**:
- `/goal` — built-in (strings бинаря: `/goal clear to stop early`, `No goal set. Usage: /goal <condition>`, `/goal is only available in trusted workspaces…`).
- Работает в `--print` headless без trust dialog UI (verified: live test в `/tmp/claude-goal-test/`, `num_turns=4`, `stop_reason=end_turn`, файл реально изменён).
- Гибрид моделей: Opus 4.7 1M ($0.109, основная работа) + Haiku 4.5 ($0.003, служебная роль) — ~97:3 cost split.
- Внутренние функции: `goalNonInteractive`, `restoreGoalFromTranscript`, `findGoalToRestore`, `active_goal` (transcript-based state).

**Принятая позиция**: `/goal` **не заменяет** наши runner'ы. Чтение `headless-runner.sh` и `battle-test-runner.sh` показало: это measurement pipelines (clone → inject → build → grade → report), а `/goal` — runtime loop control **внутри** одной `claude --print` сессии. Разные уровни абстракции.

**Где `/goal` применим**: prompt-engineering внутри `prompt.txt` для battle-test-runner Phase 3 как acceptance condition (`/goal pytest exits 0 and deliverable invokes without ImportError`). Локальное усиление, не структурное изменение.

**Cost watch**: тривиальный `/goal` (одна Edit, 4 turn, 14s) — $0.113. Для long-running — $1+. Любое будущее использование требует явное `stop after N turns` либо внешний `timeout`.

### 2.2 `claude agents` — позиция

**Эмпирически подтверждено**: `claude agents --help` показывает только `--setting-sources` → full-screen TUI. Документация: [code.claude.com/docs/en/agent-view](https://code.claude.com/docs/en/agent-view). Каждая сессия — независимый процесс под daemon с автоматической worktree-изоляцией.

**Принятая позиция**: кандидат на замену последовательного multi-run в Layer D protocol (n=3..5 на cell). **Не верифицирован эмпирически** в нашем окружении — отложен как candidate-for-future-trial, не decision. ADR не пишется до empirical evidence.

### 2.3 `continueOnBlock` hook field

**Эмпирически подтверждено**: строка `continueOnBlock` присутствует в бинаре 2.1.139. *Изначально в первой fact-check сессии был отвергнут как «не подтверждено» — эмпирика поправила меня*. Это lesson сама по себе: первичная верификация важнее интуиции.

**Принятая позиция**: реальное поле; кандидат для будущего trial (например, `loop-protected-guard.sh` мог бы возвращать reject + `continueOnBlock: true` для soft-warnings). Сейчас preconditions не появились.

### 2.4 `/spec` — отвергнуто

В чужом тексте упоминался как built-in. В бинаре 2.1.139 **не найден**. Custom skill из другого проекта (вероятно `dialog_analyzer`) или выдумка. **Не принимаем как факт без верификации источника**.

## 3. Решения по теме памяти

### 3.1 5-layer canonical model — наш маппинг

| Layer | Канонически (Anthropic / LangMem / Lance Martin) | Наш asset | Состояние |
|---|---|---|---|
| L0 in-session scratchpad | runtime task list (Manus `todo.md`) | `TaskCreate`/`TaskUpdate` (built-in) | ✓ |
| L1 procedural | CLAUDE.md, skills, rules | `.claude/CLAUDE.md` + `.claude/rules/` + 2 action-skills | ✓ |
| L2 episodic | session summaries, recurring patterns | `~/.claude/projects/<hash>/memory/MEMORY.md` (auto-memory) | ✓ + curation ritual задокументирован |
| L3 durable artifacts | `claude-progress.txt`, structured logs | `.claude/devlog/entries/*.md` + `progress.md` convention | ✓ |
| L4 semantic / decisions | ADR archive, principles | `.claude/docs/principles.md` + `.claude/docs/archive/` | ✓ |
| inter-agent | filesystem blackboard (Anthropic multi-agent paper) | `PREMORTEM.md` → `EVIDENCE.md` → `CRITIC.md` через `discovery-critic` | ✓ + explicit documentation |

### 3.2 Главный закрытый пробел: L2 curation loop

**До сессии**: auto-memory есть (`~/.claude/projects/.../memory/`), но **systematic promotion** memory entries → CLAUDE.md/rules не использовался. `/remember` skill доступен с built-in level, но я (main thread) сам им не пользовался.

**Решение**: документирован operational ritual в `.claude/docs/memory-layers.md`:
- Trigger: после сессий с ≥3 memory writes или ≥2 корректирующими feedback'ами
- Output: candidate promotions из memory в rules / CLAUDE.md с user-confirmation на каждую
- **НЕ авто-trigger через hook** — operational discipline, не enforced механизм (single-incident в invariant не превращается)

### 3.3 `progress.md` convention (L3 reinforcement)

**Решение**: rule 7 в `.claude/rules/docs-discipline.md`:
- Long-running task (>1ч wall-clock или ≥3 distinct decision points) → `.claude/progress/<slug>.md`
- Single-threaded journal: decisions, dead-ends, current state
- SessionStart hook отображает active progress-файл в `additionalContext`
- После завершения → конвертация в devlog entry + удаление progress-файла

**Источник pattern'а**: Anthropic [effective harnesses](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) `claude-progress.txt`.

### 3.4 Inter-agent communication — explicit documentation

**Что было**: pattern существовал implicitly через `discovery-critic.md` + `discovery-gate.sh` + 3 artifacts (PREMORTEM/EVIDENCE/CRITIC). Не было документировано как canonical pattern.

**Решение**: в `memory-layers.md` явно зафиксировано как **filesystem-blackboard pattern**, соответствующий Anthropic [multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system) — subagents пишут прямо в filesystem, минуя «game of telephone» через main thread.

## 4. Что НЕ сделано (явные отказы)

| Отказ | Причина |
|---|---|
| «Полноценный рефакторинг» под чужой текст | Текст содержал непроверенные утверждения + описывал другой проект (`dialog_analyzer`/`STEP_REGISTRY`); foundational principle запрещает обвязку под недоказанные assumption'ы |
| Retire `headless-runner.sh` / `battle-test-runner.sh` под `/goal` | Эмпирика чтения runner'ов показала: они measurement pipelines, не bash-loops; `/goal` их не заменяет |
| Создание `.claude/skills/meta-orchestrator-role.md` (предложено чужим текстом как «first step») | Self-описывающие skills — anti-pattern из ADR-017; дублирует CLAUDE.md |
| Vendor memory stores (Letta/Mem0/Zep) | Overkill для CLI meta-harness; filesystem + devlog справляются на 38-entries масштабе |
| Vector DB + RAG над devlog | Premature; пересмотр при ≥200 entries |
| Авто-hook на запись `progress.md` | Decision point остаётся у разработчика; форсирование через hook = single-incident в invariant |
| Persistence `TaskCreate`/`TaskUpdate` между сессиями | By-design L0 (session-scoped); cross-session goals переходят в L3 (progress.md или devlog) |
| Отдельный `.claude/init.sh` | Расширил существующий `session-context.sh` — foundational principle не плодить компоненты |
| Полноценный ADR про parallel-runs через agent view | Нет empirical evidence в нашем окружении; ADR без evidence = wishful thinking |
| Static-check на размер `.claude/progress/` | Single-incident; пересмотр после ≥2 случаев применения convention |

## 5. Метрики сессии

- **Эмпирических тестов**: 1 live `/goal` run + бинарный strings analysis + smoke-test модифицированного hook'а
- **Стоимость empirical research**: $0.113 (один `/goal` test)
- **Devlog entries created**: 2 (#37 fact-check, #38 memory layers) → total **38 entries**
- **Memory entries written**: 1 reference (`reference_goal_agentview_empirical.md`) + index update
- **Code changes**: 5 файлов изменено / создано (`memory-layers.md`, `session-context.sh`, `docs-discipline.md`, `CLAUDE.md`, `.gitkeep`)
- **Документация changes**: +52 строки (memory-layers.md), +1 rule (docs-discipline), +1 reference line (CLAUDE.md)
- **Размер файлов после правок**: CLAUDE.md 113 ≤ 200 budget ✓, memory-layers.md 52, session-context.sh 52
- **Layer A validation**: 14/14 static checks passed ✓
- **Hook smoke tests**: 2 сценария (с/без progress-файла) — оба корректные

## 6. Источники (verified, с URL)

### Anthropic engineering (canonical for harness)
- [Effective context engineering for AI agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents) — compaction, structured note-taking, multi-agent isolation, context rot, just-in-time retrieval
- [Effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) — cross-session durable artifacts pattern (`claude-progress.txt`)
- [How we built our multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system) — filesystem-blackboard, LeadResearcher save plan to Memory pattern
- [Claude Code memory docs](https://code.claude.com/docs/en/memory) — auto-memory mechanics

### Boris Cherny (Claude Code creator)
- [howborisusesclaudecode.com](https://howborisusesclaudecode.com/) — 87-tip site, CLAUDE.md как living artifact
- [Claude Code agent view docs](https://code.claude.com/docs/en/agent-view) — TUI for parallel sessions

### Community / industry
- Cognition [Don't Build Multi-Agents](https://cognition.ai/blog/dont-build-multi-agents) — single-threaded writes, subagents read-only
- Lance Martin [Context Engineering for Agents](https://rlancemartin.github.io/2025/06/23/context_engineering/) — select/compress/isolate
- LangChain [LangMem SDK](https://blog.langchain.com/langmem-sdk-launch/) — semantic/episodic/procedural taxonomy

### Vendor reference (NOT adopted, listed for context)
- Letta / Mem0 / Zep — benchmarks per Mem0 [State of AI Agent Memory 2026](https://mem0.ai/blog/state-of-ai-agent-memory-2026); overkill для нашего масштаба

### Что специально верифицировано «нет публикаций»
- **Matt Pocock** — публикует про SKILL.md как процессуальную память + deep modules; **НЕ** про runtime memory stores. Если упоминается в контексте memory architecture — путаница

## 7. Lessons learned (что усвоено в этой сессии)

1. **Empirical-first экономит от bloat'а**. Изначальный план «полноценный рефакторинг» был на 5-7 новых файлов и retire 2 runner'ов. После эмпирической проверки получилось 5 малых изменений без новых компонент-в-стиле-обвязки.
2. **Чужие тексты не ТЗ**. Текст про «мета-роль» содержал смесь верных, неверных и не-нашего-проекта утверждений. Принятие любого fragment'а без верификации привело бы к ошибочной обвязке. Lesson зафиксирован в [[reference_goal_agentview_empirical]].
3. **Первичная верификация важнее интуиции**. Я в первой fact-check сессии отверг `continueOnBlock` как «не подтверждено». Эмпирика (strings бинаря) поправила меня — это реальное поле. *Скептицизм без верификации тоже ошибка.*
4. **Разные уровни абстракции легко смешать**. `/goal` (runtime control) и наши runner'ы (measurement pipeline) на первый взгляд кажутся пересекающимися. Чтение источников + чтение собственных скриптов = единственный способ не ошибиться в категоризации.
5. **Built-ins first работает как принцип**. `/remember` skill уже доступен на built-in level — нужно было только начать им пользоваться systematically, а не создавать custom replacement.
6. **Foundational principle — практический фильтр**. На каждом decision point вопрос «Opus 4.7 уже умеет это нативно?» отсёк ≥5 предлагавшихся компонент.

## 8. Untested items (что осталось для будущей эмпирики)

| Untested item | Условие проверки | Ожидаемый риск |
|---|---|---|
| `continueOnBlock` в наших hooks | Live test на `loop-protected-guard.sh` с soft-warning return | Низкий — поле существует, поведение нужно понять |
| `claude agents` TUI для parallel benchmark runs | Запустить 3 одинаковых cell'а через TUI; verify worktree-isolation + permission-context per-process + отсутствие гонок при записи `reports/` | Средний — требует trust dialog для нашего проекта |
| `/remember` operational ritual в практике | Реальная сессия с ≥3 memory writes → вызов `/remember` → измерение качества promotions | Низкий — built-in уже tested by Anthropic |
| `progress.md` convention под реальной long task | Задача с wall-clock >1ч с сессионным interrupt | Низкий — convention простая |
| `/goal` в `prompt.txt` для battle-test Phase 3 | One run с `/goal pytest exits 0` в prompt vs без | Средний — может увеличить cost / turns |

## 9. Векторы дальнейшего развития качества кодинга

Под Opus 4.7 на CLI-подписке. **Каждый вектор требует empirical trigger** — не делается upfront.

### 9.1 Empirical exploration backlog

1. **`claude agents` для parallel benchmark D-layer** (n=3..5). Triggered при: следующий benchmark прогон, требующий n≥3. Trial: запустить через agent view вместо sequential bash. Result → ADR если работает, retire-candidate-note если нет.
2. **`continueOnBlock` в `loop-protected-guard.sh`**. Triggered при: следующий false-positive block от текущего guard'а. Trial: вернуть `continueOnBlock: true` для warning-class событий вместо exit 2.
3. **`/goal` в benchmark prompts**. Triggered при: следующий «модель сдалась преждевременно» incident в battle-test. Trial: добавить `/goal <condition>` в начало `prompt.txt` для одного run, сравнить metrics.

### 9.2 Operational practice improvements

4. **`/remember` regular usage**. Не code change — discipline. Триггер: текущая сессия (≥3 memory writes уже сделано). Recommended action: вызвать `/remember` в конце этой сессии и посмотреть proposed promotions.
5. **`progress.md` под следующую long task**. Triggered естественно при появлении wall-clock >1ч задачи. Validate convention.

### 9.3 Структурные кандидаты (НЕ делать без эмпирики)

6. **Vendor memory store integration** — пересмотр при ≥200 devlog entries или ≥10 cross-session goals одновременно. Сейчас premature.
7. **Semantic search над devlog** — пересмотр при ≥200 entries или эмпирическом случае «не смог найти прошлое решение через grep». Сейчас не нужно.
8. **Nested CLAUDE.md per subdir** — пересмотр если top-level CLAUDE.md приближается к 200 строк budget'у. Сейчас 113 → дальше до budget'а.

### 9.4 Open questions (что мы НЕ закрыли)

- Какова реальная роль Haiku в `/goal` гибриде? Evaluator? Classifier? Summary? Три кандидата, эмпирика на одном прогоне не дала однозначно. **Ответ найдётся через**: stream-json инспекция нескольких прогонов с разными моделями.
- Как `/goal` ведёт себя при `restoreGoalFromTranscript` после auto-compact? Конкретно — переживает ли goal-state context compression? **Ответ найдётся через**: long-running `/goal` test с принудительным compact.
- Когда `claude agents` worktree-isolation ломается? Параллельные writes в общие external директории, side-effects? **Ответ найдётся через**: parallel benchmark trial.

## 10. Главный вывод

Сессия зафиксировала **дисциплину empirical-first как primary defense** против harness bloat'а. Каждое решение «не сделать X» здесь так же важно, как решение «сделать Y» — потому что под Opus 4.7 на 1M context window большинство «улучшений» обвязки на самом деле снижают capability модели, не повышают.

Следующий шаг качества — **не больше обвязки, а более систематическая discipline пользования existing built-ins** (`/remember`, `/goal`, `claude agents`) и **эмпирическая верификация** перед фиксацией любого нового pattern'а в `.claude/rules/` или `.claude/docs/`.

---

**Связанные артефакты**:
- `.claude/devlog/entries/0037-empirical-fact-check-goal-agent-view-continueonblock-claude.md`
- `.claude/devlog/entries/0038-memory-layers-doc-and-progress-md-convention.md`
- `.claude/docs/memory-layers.md`
- `.claude/rules/docs-discipline.md` (rule 7)
- `.claude/hooks/session-context.sh` (progress.md detection)
- `~/.claude/projects/.../memory/reference_goal_agentview_empirical.md`
