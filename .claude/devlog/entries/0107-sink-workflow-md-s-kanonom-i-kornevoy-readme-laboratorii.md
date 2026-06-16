---
id: 107
date: 2026-06-16
title: "Синк WORKFLOW.md с каноном и корневой README лаборатории"
tags: [docs, harness]
status: complete
---

# Синк WORKFLOW.md с каноном и корневой README лаборатории

## Контекст
Аудит соответствия WORKFLOW.md полному канону фабрики выявил версионный дрейф (документ
застрял на CC 2.1.169 / моно-Opus, канон ушёл на v2.1.173 / поколение Fable 5 + Opus 4.8)
и одну свежую рассинхронизацию: «Ритуал поверх всего» описывал старую strip-ревизию без
refresh-ledger / external-intake, добавленных в канон записью #106 (doc-with-code долг той
правки). Параллельно репозиторий не имел корневого README — единственная точка входа была
WORKFLOW.md + .claude/CLAUDE.md, что не объясняет постороннему «что это и почему не шаблон».

## Изменения
**WORKFLOW.md — 5 surgical-правок (синк с каноном, scope не расширен):**
1. Шапка + footer-штамп → CC v2.1.173 / поколение Fable 5 + Opus 4.8 / last-updated 2026-06-16.
2. §0 — новая model-строка: Opus 4.8 дефолт, Fable 5 как peer (`/model fable`, ~2× цена,
   thinking всегда ON, `/fast` неприменим, авто-fallback на Opus), blanket-switch без
   доказанного лифта не делать (lab A/B ничья).
3. Spine/WORK — явный bullet «Surgical changes» (§3 baseline был единственным недопредставленным).
4. «Ритуал поверх всего» — сверка дельты от refresh-ledger + два прохода (external-intake /
   re-test); 2.1.169 → 2.1.173 внутри абзаца.

**README.md — новый корневой файл (~140 строк):** идентичность (лаборатория, не шаблон) +
центральный принцип + граница лаборатория/канон/practice-baseline + карта структуры
(каталог-уровень) + Plan→Work→Review + механизм эволюции (D-цикл / strip / refresh-ledger /
external-intake) + constraints (CLI-only / built-ins-first / single-agent) + точки входа.

**Метод сборки README:** 3 параллельных Explore-агента под изоляцию контекста (грани:
идентичность+принцип · карта каталогов · workflow+эволюция), свёртка и написание — main
thread. Не PM→writer→QA конвейер: deliverable owned главным потоком, агенты — только
read-only разведка большого слоёного репо. Дисциплина харнесса применена к самому харнессу.

## Затронутые файлы
- `WORKFLOW.md` — 5 правок (шапка, §0 model-строка, surgical-bullet, Ритуал, footer)
- `README.md` — создан (корневой entry-point репозитория)

## Проверка
WORKFLOW.md: все 5 Edit'ов применились по уникальным якорям. README: факты заземлены тремя
Explore-агентами против диска (структура, devlog-count 106, версии). Перекрёстная сверка:
README/WORKFLOW штампы == native-capabilities.md v2.1.173 == ledger #106. Прозовые доки,
runnable-оракула нет.

## Related
- #106 — refresh-ledger + external-intake (этот синк закрывает его doc-with-code долг в WORKFLOW.md)
- #105 — предыдущая гигиена harness (frontmatter + CLAUDE.md-сверка)
