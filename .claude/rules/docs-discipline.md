# Documentation discipline (harness invariant)

6 правил поддержки проектной документации, инвариантных для любого стека. Расширяется проектным CLAUDE.md, не заменяется.

См. также `.claude/skills/project-docs-bootstrap/` — bootstrap canonical layout (одноразовая операция; этот rule — ongoing discipline).

1. **Doc-with-code rule**. PR, меняющий архитектуру / добавляющий top-level dir / вводящий domain-термин / устанавливающий новую convention — обязан обновить соответствующий doc в **том же** PR. Reviewer (включая Claude) отклоняет PR при отсутствии doc-update.

2. **CLAUDE.md как indexer, не store**. CLAUDE.md ссылается на `docs/ARCHITECTURE.md` / `docs/CODE-MAP.md` / `docs/GLOSSARY.md` / etc., но не дублирует их содержимое. Цель: проектный CLAUDE.md ≤ 200 строк. Длиннее — split в `docs/` или paths-scoped rules.

3. **Live vs archive layers**. **Active layer** (`.claude/docs/principles.md` + последние ~5 devlog entries) редактируется свободно для evolve harness — supersedes / retirement фиксируются inline или новой decision записью. **Archive layer** (`.claude/docs/archive/`, `.claude/devlog/entries/archive/`) — frozen point-in-time snapshot, изменяется только через структурные миграции (новый layout / format wholesale, не индивидуальные правки). Удалённый код / модуль фиксируется в active layer со ссылкой на archive если нужны исторические детали.

4. **Owner + last-updated**. Каждый doc в `docs/` имеет `owner: @<handle>` и `last-updated: YYYY-MM-DD` в frontmatter. Stale (>6 месяцев) — кандидат на review.

5. **Glossary first-use**. Первое использование акронима / domain-термина в любом doc, коммите или комментарии → запись в `docs/GLOSSARY.md`.

6. **ADR для non-trivial решений**. Любое решение, которое будущему контрибьютору было бы непонятно «почему так» (выбор lib A vs B, layout, protocol, отказ от refactor'а) → 1-page ADR в формате Context / Decision / Consequences / Alternatives considered. Threshold: если объяснение решения в Slack заняло >5 минут — ADR.

См. также `.claude/docs/principles.md` (active) и `.claude/docs/archive/decisions-2026Q2.md` ADR-017 (rationale добавления rule).
