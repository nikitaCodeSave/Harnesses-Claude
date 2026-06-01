# Documentation discipline (harness invariant)

7 правил поддержки проектной документации, инвариантных для любого стека. Расширяется проектным CLAUDE.md, не заменяется.

См. также `.claude/skills/project-docs-bootstrap/` — bootstrap canonical layout (одноразовая операция; этот rule — ongoing discipline).

1. **Doc-with-code rule**. PR, меняющий архитектуру / добавляющий top-level dir / вводящий domain-термин / устанавливающий новую convention — обязан обновить соответствующий doc в **том же** PR. Reviewer (включая Claude) отклоняет PR при отсутствии doc-update.

   **Mapping diff → документ** (классифицируй каждый изменённый файл по характеру правки; один файл может попасть в несколько строк). Под Opus 4.8 это нативная работа main thread'а из git diff — **отдельный skill не нужен** (`sync-docs` ретайрнут в `~/.claude/_archived-skills/`; его ядро — эта таблица):

   | Категория изменения | Признак в diff | Документ |
   |---|---|---|
   | Структурное | новый/удалённый/переименованный модуль, top-level каталог, точка входа | `ARCHITECTURE.md`, `CODE-MAP.md`, корневой `CLAUDE.md` (дерево/индекс) |
   | Поток данных / зависимости | изменён import-граф, новый шаг пайплайна, новый внешний сервис | `ARCHITECTURE.md` |
   | Новый domain-термин | впервые встречается имя сущности / аббревиатура | `GLOSSARY.md` (см. rule #5) |
   | Новая convention | новый паттерн именования, layout, протокол, стиль | `CONVENTIONS.md` |
   | Конфигурация / setup | новый env-var, параметр конфига, шаг установки, зависимость | `README.md` (+ setup-doc если есть) |
   | Операционная процедура | новый деплой / миграция / recovery-сценарий | `RUNBOOKS/` |
   | Архитектурное решение | выбор lib A vs B, протокол, осознанный отказ от refactor'а | `ADR/` (порог — rule #6) |

   Правь **только затронутые разделы**, не весь документ; при frontmatter `last-updated` — обнови дату (rule #4). Эскалация (не «чинить» молча): расхождение 3+ модулей с `ARCHITECTURE.md` — это уже re-bootstrap (`/project-docs-bootstrap`), а не sync; противоречие между `ARCHITECTURE.md` и `CLAUDE.md`; `CLAUDE.md` дублирует содержимое `docs/` (нарушение rule #2).

2. **CLAUDE.md как indexer, не store**. CLAUDE.md ссылается на `docs/ARCHITECTURE.md` / `docs/CODE-MAP.md` / `docs/GLOSSARY.md` / etc., но не дублирует их содержимое. Цель: проектный CLAUDE.md ≤ 200 строк. Длиннее — split в `docs/` или paths-scoped rules.

3. **Live vs archive layers**. **Active layer** (`.claude/docs/principles.md` + последние ~5 devlog entries) редактируется свободно для evolve harness — supersedes / retirement фиксируются inline или новой decision записью. **Archive layer** (`.claude/docs/archive/`, `.claude/devlog/entries/archive/`) — frozen point-in-time snapshot, изменяется только через структурные миграции (новый layout / format wholesale, не индивидуальные правки). Удалённый код / модуль фиксируется в active layer со ссылкой на archive если нужны исторические детали.

4. **Owner + last-updated**. Каждый doc в `docs/` имеет `owner: @<handle>` и `last-updated: YYYY-MM-DD` в frontmatter. Stale (>6 месяцев) — кандидат на review.

5. **Glossary first-use**. Первое использование акронима / domain-термина в любом doc, коммите или комментарии → запись в `docs/GLOSSARY.md`.

6. **ADR для non-trivial решений**. Любое решение, которое будущему контрибьютору было бы непонятно «почему так» (выбор lib A vs B, layout, protocol, отказ от refactor'а) → 1-page ADR в формате Context / Decision / Consequences / Alternatives considered. Threshold: если объяснение решения в Slack заняло >5 минут — ADR.

7. **Progress journal для long-running task**. Задача с wall-clock >1ч или ≥3 distinct decision points → завести `.claude/progress/<slug>.md`. Single-threaded журнал: что сделано, что застряло, текущий state. SessionStart hook отображает active progress-файл в additionalContext. После завершения задачи — конвертация в `.claude/devlog/entries/NNNN-<slug>.md` и удаление progress-файла. Цель: переживать interrupt (auto-compact, перезапуск сессии) без потери intermediate state. Per Anthropic [effective harnesses](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) `claude-progress.txt` pattern.

См. также `.claude/docs/principles.md` (active), `.claude/docs/memory-layers.md` (5-layer reference) и `.claude/docs/archive/decisions-2026Q2.md` ADR-017 (rationale добавления rule).
