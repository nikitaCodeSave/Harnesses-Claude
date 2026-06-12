---
id: 100
date: 2026-06-13
title: "Репликация kit на AI_analyst_migration: n=2 + тест самодостаточности плагина"
tags: [canon, kit, harness-evolution, validation, benchmark]
status: complete
---

# Репликация kit на AI_analyst_migration: n=2 + тест самодостаточности плагина

## Контекст
Второй реальный проект (NL→SQL для банка, Oracle, 149 py) для проверки жалобы «kit ни разу
не зашёл — потеря знаний». Ветка `feature/client-product-migration` (main = архив, не трогать).
Тяжёлый, уже однажды подрезанный harness (11 skills, 3 agents, hooks, GUIDE, features.json).

## Battle-test (3 fresh context) — n=2 успех
- **harness-auditor**: harness ЗРЕЛЫЙ, без структурных дефектов; в основном staleness.
- **cold-impl-migration**: из одного harness'а реализовал queued-фичу F2 (`validate_duplicate_subqueries`)
  — нашёл #137-инфру (`_discover_subqueries`), сам откопал Q24 FP-дисциплину через существующий
  тест, TDD red→green, init.sh 1407 passed. Сильная передача знаний.
- **f2-judge**: CONFIRMED-WITH-DEBT — корректно/честно/red-check воспроизведён; 2 fail-safe FP-поверхности.
- Гипотеза «потеря знаний+низкое качество» опровергнута на ВТОРОМ независимом проекте.

## Ключевая ремарка оператора → тест самодостаточности
Оператор: «правки ИЗ лаборатории в чужие проекты — КОСТЫЛЬ; плагин сам не решил всё». Расщепление:
(а) audit/refresh СВОЕГО harness'а обязан быть нативным; (б) эволюция плагина (D-cycle) — законно
maintainer-функция. Путь разработки уже доказан нативным (оба battle-test). Проверили слой (а):
refresh исполнила НАТИВНАЯ сессия через плагин (`native-refresh-migration`), не лаборатория.

**Результат (commit `2de1b82`, верифицирован независимо):** нативная сессия + плагин успешно
применили H1 de-stale 8→9 (6 файлов), M4 soften compound-gate, L6 retire parallel-execute (+чистка
dangling refs), M2 ship `.claude/docs/` v1.9.0 verbatim. init.sh зелёный. F2 2 FP-фикса (не case-fold
литералы; adjacent-partner match) — 264 passed, uncommitted на experiment/f2-validator (ledger).

## D-CYCLE finding: где плагин НЕ самодостаточен (чинить в kit)
Кандидатный ответ агента: плагин силён на «ЧТО канонические артефакты и ГДЕ» (M2 load-bearing:
путь к выжимке, verbatim, shipped-by re-sync), но **молчит про ПРОЦЕДУРУ refresh-гигиены**:
1. **active-vs-frozen layer при de-stale** — какие из ~20 «8-step» хитов править (active), какие
   заморожены (archive/research/audit-record). Агент решил это из ПРОЕКТНОГО docs-discipline rule #3,
   НЕ из плагина. Менее аккуратная сессия: under-fix (пропустит research:18) или over-fix (испортит
   provenance архива).
2. **dangling-refs после удаления компонента** — плагин говорит «retire skill», но не «потом grep
   dangling refs» (GUIDE skill-count, acceptance-tests). Агент нашёл грепом сам.
→ Реальный disambiguator = явный список файлов оператора, не плагин. Это и есть остаточный костыль.

**Fix в kit (next):** в `audit-checklist.md`/refresh-guidance добавить процедуру — (1) de-stale:
различать active/frozen слои, править только active; (2) удаление компонента: grep dangling refs
(skill-counts, acceptance-tests, индексы) и re-route. Это превратит слой (а) в полностью нативный.

## Git-состояние (ничего не запушено; main не тронут)
- feature/client-product-migration: harness commit `2de1b82` (1 ahead of origin).
- experiment/f2-validator: F2 + 2 FP-фикса uncommitted (ledger: promote после live A/B + оператор).
