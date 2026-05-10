---
id: 16
date: 2026-05-10
title: "D-021: two-tier docs split (active vs archive)"
tags: [docs, harness, refactor]
status: complete
---

# D-021: two-tier docs split (active vs archive)

## Контекст

Append-only history (docs-discipline rule #3, ADR-017) стал friction'ом против foundational principle. Каждый retired/superseded ADR продолжал жить в active context: `HARNESS-DECISIONS.md` достиг ~67 KB, 397 строк, 18 ADR'ов. CLAUDE.md ссылается на этот файл как «читать перед расширением harness'а» — cold-start tax растёт linearly с числом decisions, даже если 80% из них уже captured в shorter form (compact index из ADR-018, или сами active rules в CLAUDE.md / rules/).

Пользователь явно подсветил проблему: правила мешают «развитию идеи и проекта». Two-tier split выбран как middle ground между full wipe (потеря контекста почему мы здесь) и status quo (continued bloat).

## Изменения

### Active layer (новый, editable)
- **`docs/HARNESS-PRINCIPLES.md`** — single short doc (~80 строк) с active decisions: foundational, components inventory, built-ins first, sub-agent spawn, memory & boundary, documentation, testing, process discipline, anti-patterns. + Decision log (post-archive) tight-форматом для будущих decisions, начиная с D-021.

### Archive layer (frozen)
- **`docs/archive/DECISIONS-2026Q2.md`** — moved from `docs/HARNESS-DECISIONS.md` (preamble + compact index + ADR-002…020 + правила обновления). Frozen point-in-time snapshot, не редактируется кроме structural migrations.
- **`.claude/devlog/entries/archive/0001-…0010`** — 10 historical devlog entries (bootstrap до retire ADR-005). Active layer оставлен из 5 latest (0011-0015 + новый 0016).

### Discipline update
- **`.claude/rules/docs-discipline.md`** rule #3 переписан: append-only → live-vs-archive layers semantics. Active editable, archive frozen.

### CLAUDE.md updates
- Foundational principle ¶2 (higher-order orchestration) — убрана inline ссылка на ADR-007, единый message «environment configurator OK; duplicate-of-built-in / self-description anti-pattern» без cross-ADR refs.
- Foundational principle ¶3 — убрана ссылка на ADR-014 и preamble в HARNESS-DECISIONS.md (preamble переехал в archive). Single-incident rule остаётся inline.
- Built-ins first — убрана «См. ADR-007.» (правило само-достаточно).
- Reference materials — `HARNESS-DECISIONS.md` заменён на `HARNESS-PRINCIPLES.md` + `docs/archive/DECISIONS-2026Q2.md` (для контекстуальных «почему» вопросов).

## Затронутые файлы

- `docs/archive/DECISIONS-2026Q2.md` — moved (was `docs/HARNESS-DECISIONS.md`)
- `docs/HARNESS-PRINCIPLES.md` — новый, ~80 строк
- `.claude/devlog/entries/archive/0001-…0010-*.md` — moved (10 files)
- `.claude/rules/docs-discipline.md` — rule #3 переписан, footer reference updated
- `.claude/CLAUDE.md` — Foundational ¶2/¶3, Built-ins first, Reference materials
- `.claude/devlog/entries/0016-*.md` — этот entry
- `.claude/devlog/index.json` — регенерирован (содержит archive entries with `entries/archive/...` path)

## Проверка

```
$ ls docs/ docs/archive/
docs/:
  HARNESS-BENCHMARK.md  HARNESS-PRINCIPLES.md  Harnesses_gude.md
  MULTI-AGENT-BASELINE.md  PRACTICES-FROM-PROJECTS.md  RESEARCH-AUDIT.md  archive/
docs/archive/:
  DECISIONS-2026Q2.md

$ ls .claude/devlog/entries/ .claude/devlog/entries/archive/ | head
entries/:
  0011-…  0012-…  0013-…  0014-…  0015-…  0016-…  archive/
entries/archive/:
  0001-…  0002-…  0003-…  …  0010-…

$ wc -l docs/HARNESS-PRINCIPLES.md .claude/CLAUDE.md
   ~80  docs/HARNESS-PRINCIPLES.md
  ~125  .claude/CLAUDE.md   # было 135, -10 строк после убирания ADR refs

$ python3 .claude/devlog/rebuild-index.py
index.json updated: 16 entries  # включая archive (rglob recursive)
```

## Что НЕ сделано (сознательно)

- НЕ переписан `HARNESS-DECISIONS.md` content — moved as-is. Архив frozen, full text сохранён для контекстуальных запросов.
- НЕ архивированы `Harnesses_gude.md`, `PRACTICES-FROM-PROJECTS.md`, `RESEARCH-AUDIT.md` — это research материалы, могут быть archived отдельным проходом если окажутся mostly-superseded.
- НЕ автоматизирован «active vs archive» split в rebuild-index.py (нет фильтра по `entries/archive/`). Path в index достаточен для discrimination; если станет mешать — отдельный фикс.
- НЕ удалён ни один archive файл. Wipe не выбран — теряет «почему отказались» context.
- НЕ retire ADR-018 (tight format spec) — спецификация перенесена в `HARNESS-PRINCIPLES.md` Decision log section.

## Открытые вопросы

1. **Research files в archive?** — `Harnesses_gude.md` / `PRACTICES-FROM-PROJECTS.md` / `RESEARCH-AUDIT.md` — большие (44/70/26 KB), sourced для archived ADR'ов. Trigger для архивирования: при следующем уменьшении docs/ или если ни один из них не цитировался в active layer >3 месяцев.
2. **rebuild-index.py archive flag** — добавить optional CLI flag `--exclude-archive` если index с archive entries окажется шумным для consumers. Trigger: первая жалоба от script / UI consumer.
3. **First decision в новом формате** — D-022 будет первой проверкой что tight format в `HARNESS-PRINCIPLES.md` Decision log работает (не превращается обратно в legacy verbosity). Trigger: следующее non-trivial harness change.

## Related

- #14 (`adr-018-019-tight-format-tiered-benchmark`) — ADR-018 tight format установил формат, D-021 систематизирует место (active layer вместо append к ADR log).
- #15 (`tier-0-1-dogfood-adr-020-fixes`) — последний entry в old append-only mode; D-021 переключает на live editable.
- archive/0010 (`adr-15-retire-adr-005-implementation-warm-context-banned`) — пример supersedure в legacy mode (full new ADR с retirement); post-D-021 такой patterns делается inline в PRINCIPLES.md Decision log.
