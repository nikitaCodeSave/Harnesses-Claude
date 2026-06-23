---
id: 111
date: 2026-06-23
title: "Campaign standard shipped to kit v1.10.0 — Phase 5 scoped-delivery, not a new mode"
tags: [harness, kit, campaign]
status: complete
supersedes: 110
---

# Campaign standard → kit v1.10.0 (Phase 5 scoped-delivery, не новая mode)

## Контекст
#110 заработал эмпирику: рычаг ведения многоспринтовой «кампании» = надёжная scoped-доставка
протокола (nested CLAUDE.md, детерминированно), single-canon беклога НЕ обязателен. Follow-on был —
перенести в shipped-kit `claude-code-harness`. Оператор одобрил.

## Решение (Decision)
**Главное открытие при переносе: kit УЖЕ содержит скелет «кампании» — `bootstrap-checklist.md`
Phase 5 «Long-running build kit»** (oracle / feature-ledger / progress / session-ritual / evaluator).
Создавать параллельную «Mode 5: Campaign» = нарушить принцип 6 самого kit (no duplication). Поэтому
**хирургически граблю только новое** в Phase 5, а не строю дубль. «Scaffolder» = main thread по
чеклисту (не скрипт — скрипт противоречил бы «conventions, not machinery»).

**Изменения (kit v1.9.2 → v1.10.0, `~/.claude/skills/claude-code-harness/`):**
- `references/bootstrap-checklist.md` Phase 5 — новый **item 7**: scope протокола кампании в её
  директорию через nested `CLAUDE.md` (`campaigns/<slug>/{CLAUDE.md,spec.md,backlog.md,archive/}`);
  единая точка входа = reuse `.claude/progress/<slug>.md` (item 3, НЕ второй progress-файл);
  **lifecycle live→archive** (anti-fragmentation, прямой урок dialog_analyzer: state в 4–6 местах,
  два правящихся канона беклога дрейфовали); **«don't force single-canon»** (A/B: drift=0 при N=3
  dual-canon — рычаг доставка, не структура; не строить mirror-sync машинерию).
- `references/native-capabilities.md` Memory § — **scoped rule delivery reliability ranking**:
  nested CLAUDE.md = детерминированный scoped-механизм (verified probe); `paths:` frontmatter
  ненадёжен (bug-cluster #16853/#16299/#21858/#23478/#17204, unfixed 2.1.x) → убран ложный claim
  «path-scoped via paths:, else always-on» из load-order; hook = guaranteed для must-not-miss;
  правило должно читаться как легитимная конвенция, не injection-imperative.
- `.claude-plugin/plugin.json` — bump 1.10.0 (новый паттерн = minor).
- project-docs/* НЕ тронуты (нет shipped-by-bump) — паттерн = bootstrap-time guidance, не
  verbatim-ship; version/ticket-bound факт о `paths:` живёт в native-capabilities per content-gate.

## Затронутые файлы
- `~/.claude/skills/claude-code-harness/`: `references/bootstrap-checklist.md`,
  `references/native-capabilities.md`, `.claude-plugin/plugin.json` (v1.10.0)

## Проверка
- grep: item 7 landed (1), lifecycle+don't-force (2), scoped-delivery+#16853 (2), старый paths-claim removed (0)
- plugin.json = 1.10.0
- не дублирует Phase 5 (граблено внутрь, не новая mode) — принцип 6 соблюдён
- НЕ закоммичено ни в одном репо (оператор review)

## Alternatives considered (отклонены)
- Новая «Mode 5: Campaign» + `references/campaign-standard.md` + scaffolder-скрипт — дубль Phase 5
  (принцип 6) + скрипт против «conventions not machinery».
- Ship паттерна в project-docs/* verbatim — version-bound факт о `paths:` нарушил бы content-gate.

## Related
- #110 — эмпирика (deep-research + A/B + probe), provenance вердикта.
- Memory: [[reference-campaign-workflow-research]], [[reference-paths-frontmatter-rules]].
