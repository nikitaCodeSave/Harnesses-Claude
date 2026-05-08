# Research Patches: docs/Harnesses_gude.md → v0.2

- **Дата**: 2026-05-09 (обновлено после ревью + API-constraint)
- **Источник аудита**: `docs/RESEARCH-AUDIT.md` (CONFIRMED 39 / STALE 6 / WRONG 4 / DUPLICATE 4 / UNVERIFIABLE 12)
- **Статус**: патчи зафиксированы, **не применены**. `docs/Harnesses_gude.md` остаётся неизменным до отдельной фазы применения.
- **Принцип**: каждый патч ссылается на (а) claim-ID в аудите и (б) строку в research-документе → трассируемость в обе стороны.
- **Глобальный constraint (новый)**: harness работает на **подписке Claude Code в CLI без API-ключа**. Любые упоминания API-only фич (Anthropic Managed Agents API, beta headers, `--betas`, `--max-budget-usd`, managed memory mount) — **выкидываются полностью**, не выносятся в optional-разделы.

## Сводка приоритетов

| Приоритет | Категория | Кол-во |
|---|---|---|
| P0 | Корректность фактов / API cleanup | 5 |
| P1 | Дубликаты + неверные числа | 4 |
| P2 | Новые секции (CLI-ergonomic) + sources reliability | 3 |
| P3 | Снижение категоричности (хедж) | 2 |
| **Итого** | | **14** |

---

## P0 — корректность фактов

### P0-1 — мис-сшитая цитата «carries context across sessions»

- **Audit ref**: C1 (WRONG)
- **Файл / строка**: `docs/Harnesses_gude.md:7`
- **Old**:
  > Opus 4.7 «more agentic, more precise … carries context across sessions», работает «coherently for hours» (Cognition/Devin) и «verifies its own outputs before reporting back»
- **New**:
  > Opus 4.7 — «more agentic», «more precise», «works coherently for hours» (Cognition/Devin), «carries work all the way through instead of stopping halfway», «devises ways to verify its own outputs before reporting back»
- **Источник новой**: https://www.anthropic.com/news/claude-opus-4-7 (дословно, см. C2/C3)

### P0-2 — «always write in third person» как ложная цитата Anthropic

- **Audit ref**: B3 + C19 (WRONG, двойное расхождение)
- **Файл / строки**: `docs/Harnesses_gude.md:26` и `docs/Harnesses_gude.md:192`
- **L26 Old**:
  > Описание (`description`) — **единственный триггер**: «include both what the Skill does and specific triggers/contexts for when to use it … always write in third person».
- **L26 New**:
  > Описание (`description`) — **единственный триггер**. anthropics/skills/skill-creator: «include both what the skill does AND specific contexts for when to use it». **Рекомендация автора research'а** (не цитата Anthropic): писать description от третьего лица для единообразия.
- **L192 Old**: `Обязательно: imperative form, third person в description, лимит ~150 строк в SKILL.md, остальное — в references/.`
- **L192 New**: `Желательно: imperative form, третье лицо в description (стилистическая рекомендация автора). Лимит SKILL.md — 500 строк per code.claude.com/docs/skills (см. также P1-3); остальное — в references/.`

### P0-3 — managed memory полностью выкинуть из research'а

- **Audit ref**: A4 (WRONG)
- **Constraint**: Managed Agents API недоступен на подписке Claude Code. Поэтому НЕ переносим в optional bridge-раздел — удаляем целиком.
- **Файлы / строки**: `docs/Harnesses_gude.md:17` (Key Finding 3), `:30` (Key Finding 8c), упоминания в разделе 5.6 «memory-management/SKILL.md»
- **Action**:
  1. В Key Finding 3 (L17) убрать «managed memory ([Claude Managed Agents memory blog])» из перечня Claude Code-примитивов.
  2. В Key Finding 8 (L30) удалить пункт (c) «Memory Tool (managed agents API) для long-running агентов» и пункт «Anthropic про managed memory: …». Иерархия памяти редуцируется до **трёх уровней**: `CLAUDE.md` (static), `MEMORY.md` (auto, 200 lines / 25KB), subagent memory frontmatter (v2.1.33+).
  3. В разделе 5.6 «memory-management/SKILL.md» удалить bullet «Managed Agents memory tool — для production multi-session агентов через API».
  4. **Никакого Optional Bridge раздела не создавать.** Research работает только в CLI surface.

### P0-4 — hook-каталог 7 → 14 (расширение по B12)

- **Audit ref**: B12 (STALE/WRONG, ~29 hook events vs 12 в research'е)
- **Файлы / строки**: `docs/Harnesses_gude.md:28` (Key Finding 6) + раздел 6 (стр. 228-241)

**L28 Old**:
> Lifecycle: SessionStart, UserPromptSubmit, PreToolUse, PostToolUse, PostToolUseFailure, Stop, SubagentStop, PreCompact, Notification, PermissionRequest, Setup, SessionEnd ([Hooks reference](https://code.claude.com/docs/en/hooks)).

**L28 New** (актуальный список ~29 событий, code.claude.com/docs/hooks-reference, сгруппирован по фазам):
> **session**: Setup, SessionStart, SessionEnd · **prompt**: UserPromptSubmit, UserPromptExpansion · **tool**: PreToolUse, PostToolUse, PostToolUseFailure, PostToolBatch · **permission**: PermissionRequest, PermissionDenied · **subagent**: SubagentStart, SubagentStop · **task**: TaskCreated, TaskCompleted, TeammateIdle · **system**: InstructionsLoaded, ConfigChange, CwdChanged, FileChanged · **lifecycle**: Stop, StopFailure, PreCompact, PostCompact · **worktree**: WorktreeCreate, WorktreeRemove · **UI**: Notification, Elicitation, ElicitationResult.

**Раздел 6 (каталог hooks)** — расширить с 7 до 14 хуков, добавив 7 новых:

| Event | Matcher | Скрипт | Use-case |
|---|---|---|---|
| `TaskCreated` | — | `block-empty-task-desc.sh` | block-spawn гейт: отбрасывает спавн subagent'а с пустым/слишком коротким description |
| `ConfigChange` | — | `config-audit.sh` (async) | audit log в `.claude/memory/config-audit.jsonl` |
| `CwdChanged` | — | `env-reload.sh` | direnv-style: при смене cwd обновляет env vars |
| `WorktreeCreate` / `WorktreeRemove` | по slug pattern (см. note) | `worktree-bridge.sh` | для non-git VCS (jj, sapling, hg) |
| `Elicitation` / `ElicitationResult` | — | `elicit-log.sh` (async) | observability AskUserQuestion-паттернов |
| `PermissionDenied` | — | `denied-log.sh` (async) | сохраняет каждый отказ в `.claude/memory/denied.jsonl` |
| `StopFailure` | — | `stop-recovery.sh` | при провале Stop — recovery hint в `MEMORY.md` |

**Note про matcher для `WorktreeCreate`/`WorktreeRemove`** (из ревью): эти события дёргаются на любые worktree-операции — session-уровневые `--worktree`, agent-уровневые `isolation: worktree`, и bridge-сценарии для non-git VCS. Если используется как bridge, matcher должен фильтровать по slug pattern (`name`-based). В шаблоне оставить matcher пустым с комментарием: `# matcher: настроить по slug, если хук используется как VCS-bridge — иначе сработает на каждой worktree-операции`.

Итого каталог: 7 старых + 7 новых = **14 хуков**.

### P0-5 — очистить research от всего API-only материала (NEW по constraint)

- **Constraint**: harness — для подписки Claude Code CLI. API-фичи (Managed Agents API, beta headers, --betas, --max-budget-usd) **не доступны и нерелевантны**.
- **Audit ref**: A12, B25, B26, B27, C17 — все CONFIRMED как факты Anthropic platform, но не применимы к нашему surface.
- **Files / lines**:
  - `:32` — упоминание «task budgets — beta»
  - `:30` — упоминание «Managed Agents memory tool через API»
  - `:378` — caveat 7 про `managed-agents-2026-04-01` header
  - `:202` — пункт «портировать в Claude Managed Agents API» в Recommendations Stage 4
- **Action**:
  1. Удалить «task budgets — beta» из Key Finding 10 (L32). Если хочется упомянуть thinking-budgets removal — сформулировать как «фиксированных thinking budgets больше нет; адаптивное мышление — единственный mode» без отсылки к API beta header.
  2. Удалить весь пункт про «Memory Tool (managed agents API)» (см. также P0-3).
  3. Удалить caveat 7 про managed-agents-2026-04-01.
  4. Удалить Recommendations Stage 4 «managed agents bridge» полностью, либо переформулировать как: «harness целенаправленно не покрывает API multi-session агентов; для этой поверхности нужен отдельный artifact».
  5. **Никаких упоминаний `--betas` и `--max-budget-usd` в патчах P2-1.**

---

## P1 — дубликаты и неверные числа

### P1-1 — agents trim: 8 → 5 (с уточнённой формулировкой по ревью)

- **Audit ref**: D1, D2 (DUPLICATE built-ins)
- **Файлы / строки**:
  - Дерево структуры: `docs/Harnesses_gude.md:58-66`
  - Каталог агентов: `docs/Harnesses_gude.md:152-163`
  - Мета-CLAUDE.md: `docs/Harnesses_gude.md:105-148`
- **Action**:
  1. Из дерева убрать `codebase-explorer.md`, `architect.md`, `orchestrator.md`.
  2. Из таблицы агентов удалить строки `codebase-explorer`, `architect`. Строку `orchestrator` заменить на:
     > **orchestrator-роль исполняется самим основным потоком сессии (main agent), не отдельным subagent'ом.** Не нужен ни custom subagent с этим именем, ни built-in. Для делегирования глубоких задач из основного потока используется built-in `general-purpose` через `Task` tool — но это **инструмент**, а не оркестратор.
  3. В мета-CLAUDE.md (после блока «Decision tree») добавить пункт:
     ```
     ## Built-ins first
     Перед созданием любого custom subagent'а: проверить inventory через
     `claude agents`. Built-ins (Explore, Plan, general-purpose, statusline-setup)
     дублировать запрещено. Кастомный агент создаётся только когда built-ins
     не покрывают задачу.
     ```
  4. Итог: каталог `.claude/agents/` сокращается до **5 файлов**:
     `deliverable-planner.md`, `code-reviewer.md`, `debug-loop.md`, `onboarding-agent.md`, `meta-creator.md`.
     - Note: `code-reviewer` теперь конкурирует с `claude ultrareview` — см. P2-2.
     - Note: `onboarding-agent` — кандидат на удаление в Worktree №5 (Phase 2), если `CLAUDE_CODE_NEW_INIT=1` покроет.

### P1-2 — skill-creator через marketplace, не форк (с user-level scope caveat)

- **Audit ref**: D3 (DUPLICATE)
- **Файлы / строки**: `docs/Harnesses_gude.md:68` (дерево) + раздел 5.1 (`:185-192`)
- **L68 Old**: `│   ├── skill-creator/SKILL.md      # форк из anthropics/skills`
- **L68 New**: `│   # skill-creator НЕ форкается; подключается как plugin (см. 5.1)`
- **Раздел 5.1 New body** (заменяет старый):
  > Канонический skill-creator живёт в [anthropics/skills](https://github.com/anthropics/skills/blob/main/skills/skill-creator/SKILL.md). Не копировать в `.claude/skills/` — подключить как marketplace:
  > ```bash
  > claude plugin marketplace add anthropics/skills
  > claude plugin install skill-creator@anthropics-skills
  > ```
  > **Caveat про scope (из ревью)**: skill-creator одинаков для всех проектов и не несёт project-specific логики. Ставить нужно на **user-level** (`~/.claude/`), не загрязняя `.claude/` каждого проекта. Конкретный механизм (`--user` flag или запуск из домашней директории) — проверяется в Worktree №4 (Phase 2).
  >
  > Форк делать только если нужны проектные изменения, которые нельзя описать через композицию.

### P1-3 — лимит SKILL.md 150 → 500 строк

- **Audit ref**: B8 (STALE)
- Покрыто P0-2.

### P1-4 — убрать «<5K при активации»

- **Audit ref**: B4 (STALE)
- **Файл / строка**: `docs/Harnesses_gude.md:26`
- **Old**: `прогрессивная загрузка (~100 токенов на metadata-сканирование, <5K при активации)`
- **New**: `прогрессивная загрузка: при сканировании skill'ов читается только YAML frontmatter (~100 токенов per code.claude.com/docs/skills); тело SKILL.md грузится только при активации (держите его коротким, см. лимит 500 строк).`

---

## P2 — новые секции

### P2-1 — раздел 13 «CI-mode harness (--bare режим)» (без API-фич)

- **Audit ref**: NEW FINDINGS P7, P8, P12 (только subscription-friendly)
- **Куда**: новый раздел **13** перед `## Recommendations` (после раздела 12 «Открытые вопросы»). **Раздел 14 не создаётся** — Managed Agents Bridge выкинут (см. P0-3, P0-5).
- **Содержимое**:
  > ### 13. CI-mode harness (--bare режим)
  >
  > Помимо интерактивного DX, harness должен иметь **second surface — CI-mode**: детерминированный, headless. Это критично для GitHub Actions, pre-commit, batch-review.
  >
  > Рецепт (subscription-friendly, **без API-only флагов**):
  > ```bash
  > claude --bare \
  >        --print \
  >        --json-schema "$(cat .claude/schemas/review.json)" \
  >        --output-format json \
  >        --add-dir . \
  >        --settings .claude/settings.ci.json \
  >        --agents "$(cat .claude/agents.ci.json)" \
  >        -p "Review the diff and emit findings"
  > ```
  >
  > Что выключает `--bare`: hooks, LSP, plugin sync, attribution, auto-memory, background prefetches, keychain reads, CLAUDE.md auto-discovery (per `claude --help`). Контекст подаётся явно через `--system-prompt`, `--add-dir`, `--mcp-config`, `--settings`, `--agents`, `--plugin-dir`.
  >
  > Что добавляет:
  > - `--json-schema` — валидация structured output (вход для парсинга в CI).
  > - `--output-format json` — машинное чтение.
  >
  > **Не используем** (API-only, недоступно на подписке): `--betas`, `--max-budget-usd`. Это сознательное ограничение surface.
  >
  > **Артефакт**: `.claude/scripts/ci-review.sh` — обёртка для GitHub Actions. Создаётся в Worktree №2 (Phase 2). Worktree №2 дополнительно проверяет, можно ли красиво обернуть `claude ultrareview` в slash-skill через `disable-model-invocation: true`.

### P2-2 — `claude ultrareview` как shell-команда, не slash (по ревью)

- **Audit ref**: NEW FINDING P10
- **Файл / строка**: `docs/Harnesses_gude.md:266-275` (раздел 7, slash commands)
- **Action**: строку `/review | Diff-review последних изменений | code-reviewer` заменить на:
  > | `/review` | **In-session** local diff-review через code-reviewer agent | code-reviewer |
  > | (shell) `claude ultrareview` | **Out-of-session** cloud-hosted multi-agent review (~30 минут, отдельная стоимость). Запускается из shell, **не slash-командой** внутри сессии Claude Code. | built-in CLI subcommand |
  >
  > Развилка использования: `/review` — каждое изменение в работе; `claude ultrareview` — перед merge или для regulated-контекстов с требованием independent multi-agent. **Worktree №2 проверяет**, можно ли обернуть `ultrareview` в slash-skill через `disable-model-invocation: true` (skill дёргает `Bash` для вызова shell-subcommand).

### P2-3 — добавить «Sources reliability» в Caveats (по ревью)

- **Audit ref**: 12 UNVERIFIABLE пунктов
- **Куда**: новый подпункт в разделе «Caveats» (после пункта 10)
- **Content**:
  > **11. Sources reliability**. Часть утверждений в этом research'е опирается на community / interpretive sources, не на canonical Anthropic docs. Конкретно: цитаты, для которых WebFetch вернул certificate error или которые цитируются по transcribed video (C4, C10); числовые границы и имена файлов, не подтверждённые дословно (B6, B7, B16); community observations без публичных issue (A3, B10). Применять с осторожностью; перепроверять при следующем audit.

---

## P3 — снижение категоричности

### P3-1 — auto-selection custom agents

- **Audit ref**: B10 (UNVERIFIABLE)
- **Файл / строка**: `docs/Harnesses_gude.md:376`
- **Old**: «Auto-selection of custom agents unreliable: open issues подтверждают…»
- **New**: «Auto-selection of custom agents — community-наблюдение (без конкретных issue в публичном tracker'е, на момент аудита 2026-05-09): авто-селекция custom subagent'а по description иногда не срабатывает. Резерв — explicit invocation через slash command.»

### P3-2 — slash-commands ↔ skills унификация

- **Audit ref**: A3 (UNVERIFIABLE)
- **Файл / строка**: `docs/Harnesses_gude.md:17`
- **Old**: «slash-commands (унифицированы со skills с v2.1.101)»
- **New**: «slash-commands и skills — единая поверхность (точная версия унификации не верифицирована по CHANGELOG; косвенное свидетельство — флаг `--disable-slash-commands` в v2.1.136 описан как "Disable all skills")»

---

## Фаза 2 — план 5 worktree'ев (порядок пересмотрен по ревью)

| Order | Worktree | Цель | Зависимости |
|---|---|---|---|
| **1st** | **№3 agents-trim** | Создать harness впервые с trimmed-каталогом из 5 агентов + built-ins-first мета-CLAUDE.md. Самый дешёвый, не требует instrumentation, даёт быстрый сигнал. | Нет |
| **2nd** | **№1 hooks-expanded** | Реализовать 5 ценных новых хуков (TaskCreated, ConfigChange, CwdChanged, PermissionDenied, StopFailure) → даёт observability, на которую опираются остальные | После №3 (общий harness базис) |
| **3rd / parallel** | **№4 marketplace-skill-creator** | `claude plugin marketplace add anthropics/skills` (с user-level scope). Удалить локальный форк | Не зависит от №1, можно параллельно с №5 |
| **3rd / parallel** | **№5 new-init-bridge** | `CLAUDE_CODE_NEW_INIT=1` → сравнить с onboarding-agent. Решение: `/onboard` ужимается в обёртку или `onboarding-agent` удаляется (харнесс → 4 custom-агента) | Не зависит от №1, можно параллельно с №4 |
| **4th** | **№2 ci-mode** | `.claude/scripts/ci-review.sh` (`--bare + --json-schema + --output-format json`, без API-флагов). Прогон на disposable PR | После №3 (стабильный DX-harness) |

**Note для №3 (важно)**: `.claude/agents/` и `.claude/skills/` сейчас **пустые директории**. Это значит «trim» = «не создавать DUPLICATE с самого начала», а не «удалить existing». Worktree №3 фактически создаёт harness впервые, как v0.2-style.

**Note для №3 (метрики, по ревью)**: A/B сравнение trimmed vs full можно сделать без observability из №1 — наблюдением walltime и `Stop` count. Не нужно ждать №1.

---

## Application notes

- **Не править `Harnesses_gude.md` вживую**. Application = отдельный коммит с этими 14 патчами в порядке P0 → P1 → P2 → P3.
- После Phase 2 (особенно №3 и №5) могут возникнуть дополнительные патчи v0.3.
- Подписочный constraint — durable: любые будущие правки research'а не должны возвращать API-only материал.
