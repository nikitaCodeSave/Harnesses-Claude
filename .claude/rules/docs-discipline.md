# Documentation discipline (harness invariant)

6 правил поддержки проектной документации, инвариантных для любого стека. Расширяется проектным CLAUDE.md, не заменяется.

См. также `.claude/skills/project-docs-bootstrap/` — bootstrap canonical layout (одноразовая операция; этот rule — ongoing discipline).

1. **Doc-with-code rule**. PR, меняющий архитектуру / добавляющий top-level dir / вводящий domain-термин / устанавливающий новую convention — обязан обновить соответствующий doc в **том же** PR. Reviewer (включая Claude) отклоняет PR при отсутствии doc-update.

2. **CLAUDE.md как indexer, не store**. CLAUDE.md ссылается на `docs/ARCHITECTURE.md` / `docs/CODE-MAP.md` / `docs/GLOSSARY.md` / etc., но не дублирует их содержимое. Цель: проектный CLAUDE.md ≤ 200 строк. Длиннее — split в `docs/` или paths-scoped rules.

3. **Append-only history**. ADR не редактируется (новый ADR с `Supersedes ADR-NNN`). Devlog не редактируется (новый entry с `supersedes:`). Удалённый код / модуль описывается в retirement ADR, не исчезает молча.

4. **Owner + last-updated**. Каждый doc в `docs/` имеет `owner: @<handle>` и `last-updated: YYYY-MM-DD` в frontmatter. Stale (>6 месяцев) — кандидат на review.

5. **Glossary first-use**. Первое использование акронима / domain-термина в любом doc, коммите или комментарии → запись в `docs/GLOSSARY.md`.

6. **ADR для non-trivial решений**. Любое решение, которое будущему контрибьютору было бы непонятно «почему так» (выбор lib A vs B, layout, protocol, отказ от refactor'а) → 1-page ADR в формате Context / Decision / Consequences / Alternatives considered. Threshold: если объяснение решения в Slack заняло >5 минут — ADR.

См. также `docs/HARNESS-DECISIONS.md` ADR-017 — обоснование добавления этого rule.
