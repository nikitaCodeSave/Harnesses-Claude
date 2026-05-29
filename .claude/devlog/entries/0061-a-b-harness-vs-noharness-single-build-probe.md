---
id: 61
date: 2026-05-29
title: "A/B harness vs noharness single-build probe"
tags: [benchmark, harness, measurement]
status: complete
---

# A/B harness vs noharness single-build probe

## Контекст
Оператор: «запускай 1 для быстрой пробы». Полный A/B (#60-обвязка): `claude --print` строит
NL→SQL-аналитик с глобальным практическим слоем `~/.claude` ON (harness) vs OFF (noharness),
судья — v2 на живом Oracle+ollama.

## Две итерации контракта (важная коррекция)
1. Первый прогон: build-промпт требовал stdlib-only/детерминированный (без LLM). Оба агента всё
   равно потянулись к **Anthropic API** (`anthropic` SDK, ключа нет) → идентичный краш → 2/12, ноль
   сигнала. + вскрылся реальный баг: `_shape` падал на 1-колоночном результате (пофикшен, executor
   теперь устойчив к недоверенному SQL агента).
2. Оператор указал: реальный проект — LLM-backed агент к Oracle через ollama; нужны актуальные
   библиотеки. Контракт исправлен: impl генерит SQL через **локальную ollama** (OpenAI-совместимый,
   httpx/urllib; `openai` SDK нет в .venv; Anthropic запрещён). Runner исполняет SQL против bench-Oracle.

## Результат (builds=1, n=1 — НЕ значим статистически)
| Arm | v2 gate_pass | stable |
|---|---|---|
| harness | 4/12 | 12/12 |
| noharness | 5/12 | 12/12 |
| delta | **−1** | — |

## Честная интерпретация
- **Нет преимущества harness на single-shot билде.** delta −1 при n=1 — **шум** (claude-билд
  стохастичен; оракул-то детерминирован 5/5/5, но билд нет).
- **Оба arm построили почти идентичные импл**: пакет `nl2sql/` (agent/llm/parser/validator) + 3
  тест-файла + requirements + solve.py. Methodology-столб (§5) **не дал видимой дельты** в
  структуре/тестах — Opus 4.8 и так нативно пишет структурированный тестируемый код (noharness даже
  чуть богаче: +schema.py, +conftest.py).
- SQL генерит **одна и та же ollama-модель** в обоих arm → модель доминирует счёт, обвязка claude
  сдвигает его маргинально. Оба валят доменные traps (как thin-hint baseline #59).

## Качественное сравнение кода (по запросу оператора)
gate_pass видит только корректность SQL. Гипотеза: harness-arm профессиональнее «вглубь». Глубокое
код-ревью обеих баз (code-comparer subagent + сам верифицировал) → **гипотеза НЕ подтверждена на
n=1, скорее наоборот, маргинально**: arm БЕЗ harness'а дал более глубокую валидацию (исполняемый
guard «SUM по балансу→ошибка» `validator.py:41-54` + тесты; word-boundary DML ловит stacked `DROP`;
parens-balance; env/empty preconditions; strip `<think>`), тогда как harness валидатор минимален
(SELECT/DML-at-start/FROM) и кодирует доменное правило только в промпте. Counter: harness авто-чинит
`LIMIT→FETCH FIRST` (`parser.py:40`) + точнее типы + тест на счётчик вызовов. Обе базы сильные и
архитектурно почти идентичные → разница в пределах шума n=1. Артефакты сохранены: `build-harness/`,
`build-noharness/`. Вывод согласуется с central thesis: Opus 4.8 и так пишет эту глубину нативно.

## Что это подтверждает (central thesis)
Согласуется с #52 и foundational principle: **под Opus 4.8 ценность harness'а — не в single-shot
качестве** (модель уже отличная), **а в continuity/practice-дельте между сессиями**, которую
single-shot A/B по построению не ловит. Это и есть строгий честный замер на качественном оракуле.

## Затронутые файлы
- `reports/2026-05-29-ab-harness-vs-noharness-b1/{results.md,report.json}` (new)
- (контракт-фикс + executor-устойчивость закоммичены ранее: 2c63c91, 1cc5d01)

## Related / next
- #60 (A/B-обвязка), #59 (baseline), #52 (single-shot зануляет practice).
- **Открыто**: мульти-сессийный сценарий (сессия N ← devlog/progress 1..N-1) — единственный, где
  continuity-столб (#54) задействован; туда и должна сместиться ценность harness'а. + `--builds 3+`
  если нужна направленная оценка single-shot.
