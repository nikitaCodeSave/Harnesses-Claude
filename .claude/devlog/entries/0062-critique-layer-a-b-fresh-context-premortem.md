---
id: 62
date: 2026-05-30
title: "Critique-layer A/B: fresh-context — это рычаг, не premortem-ритуал"
tags: [benchmark, harness, measurement, critique, discovery-critic]
status: complete
---

# Critique-layer A/B: fresh-context — это рычаг, не premortem-ритуал

## Контекст
Бриф по практикам 4.8 советует «убирать скаффолдинг, который модели больше не нужен»
и A/B-тестить critique/discovery-обвязку. Вопрос: **субсумирует ли нативный self-check
Opus 4.8 слой `discovery-critic` / `/critique` / `discovery-gate.sh`**. Дизайн (по выбору
оператора): seeded-defect detection — фикстура с посаженными дефектами, recall как оракул.
Масштаб: после применения глобального simplicity-baseline урезан с «полного workflow на ~24
агента» до дешёвого теста на прямых Agent-вызовах (foundational principle: минимум обвязки).

## Установка
Фикстура `.scratch/critique-ab/untrusted_sql_shaping.py` (на мотивах реального `runner.py`:
shaping недоверенного agent-SQL), 8 посаженных дефектов по 7 категориям. Все агенты — Opus 4.8.

## Результаты (n=3 на arm, single fixture — НЕ значимо статистически)
1. **Пилот, in-context критик-ритуал** (arm A native single-pass vs arm B premortem+второй
   проход в том же контексте): recall **идентичен — 17/24 у обоих**. Структура промахов
   совпадает (D2/D7 пропустили все 6 прогонов). **In-context ритуал даёт 0 лифта.**
2. **Полный round, fixed fixture** (D2/D7 сделаны single-file-детектируемыми): native
   single-pass ловит **8/8 во всех 3 прогонах (24/24)**. Посаженный барьер ниже нативного
   потолка 4.8 — recall-headroom'а для критика нет.
3. **Fresh-context независимый критик** (arm C над выхлопом arm A, отдельный контекст = реальный
   `discovery-critic`): нашёл **1 genuinely-novel реальный дефект**, мимо которого прошли ВСЕ 3
   нативных ревью — uncaught-crash через re.sub replacement-template вне try (нарушение контракта
   «never crash»). Поймали 2/3 критиков, **0 ложных срабатываний**.

## Вывод (главный)
**Ценность discovery-critic — в свежем неякорённом контексте, а НЕ в premortem-методологии.**
Это уточняет рекомендацию брифа «убирай скаффолдинг» в evidence-based форму:
- **убрать** in-context «перепроверь себя перед возвратом» — под 4.8 даёт 0 (в harness'е такого
  и не было; grep подтвердил);
- **оставить** `discovery-critic` / `/critique` как opt-in fresh-context Evaluator — заработал
  реальную находку;
- `discovery-gate.sh` остаётся default-off (безвредный reminder вызвать критика);
- `stop-validation.sh` — механический independent-verification хук, согласуется с «judge ≠ author».

Harness **уже** воплощал этот принцип (`discovery-critic.md:8` «separating judge from author is
the lever»; framing-note делает независимый Phase-1 probe первичным). Замер его подтвердил —
инвариантных правок не делаю (single-incident в invariant не превращается), только breadcrumb.

## Реальный баг, найденный критиком (пофикшен)
`runner.py:_rewrite_table` подставлял `cfg.table` как re.sub replacement-template → бэкслэш/`\g<N>`
из env вызывал `re.error` (вне try → uncaught crash) или silent-expansion. Фикс: callable-замена
`lambda _m: self.cfg.table` (literal) + вызов занесён внутрь try. Регресс-тест RED→GREEN
(`test_rewrite_table_literal_replacement`). Реальный risk ~нулевой (cfg.table = env BENCH_TABLE),
но латентный паттерн был настоящий — и его поймал именно fresh-context критик, а не нативный проход.

## Затронутые файлы
- `runner.py` (fix _rewrite_table literal replacement + rewrite внутрь try)
- `test_runner.py` (+test_rewrite_table_literal_replacement; PASS=45 FAIL=0)
- `.claude/agents/discovery-critic.md` (breadcrumb: эмпирическое подтверждение fresh-context-рычага)
- `.scratch/critique-ab/` (фикстура, answer key, 6+3 finding-JSON, RESULTS.md) — артефакты замера

## Related / next
- #61/#52 (single-shot зануляет practice-дельту), foundational principle (минимум обвязки).
- Caveat: n=3, single fixture — directional, не power-результат. Критик добавил ценность только
  потому, что фикстура содержала **непосаженный** реальный баг (re.sub) — что и есть реализм:
  настоящие deliverable'ы содержат неизвестные баги, и свежие глаза ловят то, мимо чего якорится автор.
