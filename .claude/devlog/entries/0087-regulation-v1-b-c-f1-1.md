---
id: 87
date: 2026-06-10
title: "Regulation v1: B C F1.1"
tags: [harness, regulation, cleanup, workflow]
status: complete
---

# Regulation v1: операторские хвосты закрыты по делегации — корзины B/C, F1.1, push

## Контекст
После релиза v1.3.0 (#86) оставались хвосты, зарезервированные за оператором. Оператор
делегировал «оставшиеся размышления и решения от моего лица» — решения приняты и исполнены
в той же сессии (Workflow №4: 5 последовательных стейджей на migration ∥ debt-фикс
prompt-regress; 6 агентов, ~417k токенов).

## Решения (от лица оператора)
- **Красный тест migration**: протух тест, не код — `bbf49e7` намеренно менял
  `response_temperature` 0.7→0.5; актуализирован тест (`cd2db92`), init.sh GREEN 1398 passed.
- **Корзина B: 12/13 одобрено, G16 (devlog-миграция) отклонена** — отчёт сам констатирует
  «формат работает»; QoL не оправдывает риск для живого store на 138 записей.
- **Корзина C**: D1/D4/D5 retire с переносом контента; D2 retire после G9 (эмпирическая
  проверка = первая реальная задача через обновлённый /implement, файлы git-recoverable);
  D3 — DEPRECATED-метка, удаление после цикла без использования; D6 cleanup.
- **Push migration НЕ делать** — прод-репо рабочего бота, не входил в хвосты.
- **Track A/B (SGR/prod security R7) не реоткрывать** — прежняя приоритизация оператора.

## Изменения
- **dot-claude / lab push**: main + теги `claude-code-harness--v1.2.0/v1.3.0` на GitHub.
- **migration (4 коммита, только harness-поверхность)**: `8755bb1` корзина A; `cd2db92`
  тест-фикс; `6525025` корзины B+C (G6-G18 кроме G16; D1-D6; G12: GUIDE 546→139 строк,
  CLAUDE.md 72; agents 7→3 — security-auditor/spec-reviewer/tdd-test-writer; skills 13→11,
  parallel-execute deprecated; новые rules/docs-sync.md, progress/d2-tdd-agents-retired.md);
  `ac8780a` closure-секция gap-report. Verifier: оракул GREEN, ноль живых битых ссылок,
  JSON-конфиги валидны. Операторские незакоммиченные файлы не тронуты.
- **prompt-regress**: major-долг Evaluator'а закрыт строгим TDD — SQL-presence priority
  в `compute_subq_verdict` (асимметрия наличия SQL решает вердикт до общих error-правил;
  4-col CI-gate больше не нем); 22/22 тестов, compat-guard сохранил поведение smoke;
  коммиты `523772d` RED → `cc82b03` GREEN → `62c0384` docs.

## Затронутые файлы
- `~/PROJECTS/AI_analyst_for_work/AI_analyst_migration` — 4 harness-коммита (см. выше)
- `~/PROJECTS/prompt-regress` — 3 коммита F1.1
- lab: GAP-REPORT closure, progress/standard-v1.md, эта запись

## Проверка
- migration: `./init.sh` EXIT=0 (1398 passed, 4 skipped); verifier-grep — упоминания
  удалённых компонентов только в archive/audit/progress (история); jq на 3 JSON-конфигах.
- prompt-regress: RED подтверждён падением до реализации; 22/22; init.sh зелёный.
- DoD Регламента v1: **6/6** — п.4 (легаси к канону, оракул зелёный до/после) теперь закрыт
  полностью. Хвост: docstring `application/agent.py:5` («8-шагового») — следующий
  code-touch PR; push migration — оператор.

## Related
- #86 — релиз v1.3.0 (T2-T4)
- #85 — T1 + упаковка
