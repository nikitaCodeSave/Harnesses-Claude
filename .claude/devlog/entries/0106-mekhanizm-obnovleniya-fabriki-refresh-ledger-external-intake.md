---
id: 106
date: 2026-06-16
title: "Механизм обновления фабрики: refresh-ledger + external-intake в strip-ревизии"
tags: [feature, harness, adr]
status: complete
---

# Механизм обновления фабрики: refresh-ledger + external-intake в strip-ревизии

## Контекст
Канон фабрики (глобальный скилл `claude-code-harness`) стареет по трём внешним осям —
CC-версия, поколение модели, подходы агентной разработки — но процедура эволюции
(`harness-evolution.md`) триггерилась только внутренними сигналами (project journal,
audit-вердикты, операторские поправки). Детекция внешнего дрейфа держалась на том, что
оператор случайно вспомнит — нарушение собственного принципа «механический guard >
prompt-compliance». Нужен систематический external-intake без раздувания обвязки.

## Изменения
Расширен `~/.claude/skills/claude-code-harness/references/harness-evolution.md` (правка
канона, не лабораторного дока):

1. **Refresh-ledger** — provenance-штамп `last-grounded: CC v2.1.173 · Fable 5 + Opus 4.8
   · 2026-06-16` + `sources-checked`. Baseline, чтобы strip-ревизия сверяла дельту, а не
   «всё с нуля». Version-строка `native-capabilities.md` после refresh обязана совпадать
   со штампом. Дельта `claude --version` против ledger — самостоятельный триггер ревизии
   (видна в начале сессии, без отдельной машинерии).
2. **Strip-ревизия → два прохода.** Проход 1 (external-intake): сверка CC-changelog /
   first-party docs+blog / external-sources catalog по дельте от ledger; каждая находка
   через D-цикл-gate (`kit-gap` multi-source · `single-incident` · `noise`) —
   external-сигнал НЕ привилегирован, «вышла статья / появился флаг» в invariant не
   превращается, fold = point-edit reference, не новый слой. Проход 2 (re-test):
   прежняя процедура safe-mode A/B, renumbered.
3. Триггер cadence расширен дельтой CC-версии; «Источники сигналов» получили пункт
   «внешний дрейф»; в конце ревизии — обновить ledger + синхронизировать
   native-capabilities version-строку + devlog + (при сдвиге состава) bump version.

**Решение оператора** (AskUserQuestion): ledger + intake-чеклист **без новой
машинерии**. Отклонены version-detect SessionStart-hook и scheduled Cron/Routine-scan —
как избыточная обвязка под headline-принципом «минимум обвязки даёт максимум
продуктивности». Ритуал исполняется нативно main thread'ом по cadence/version-триггеру.

**Предшествующая сверка доставки (чисто):** все shipped project-docs (`workflow.md`,
`testing.md`, `docs-discipline.md`) несут `shipped-by: v1.9.0` = `plugin.json`. Shipped
`workflow.md` и лабораторный `.claude/docs/workflow.md` — разные документы by design
(самодостаточная дистилляция vs тонкий spine с routing), не копии → ложная тревога о
«дрейфе» снята. Факты консистентны (effort `high`, `ultracode`=trigger-word,
verification ladder). Единственная staleness — lab-internal `builtins-inventory.md`
(2.1.143-snapshot), не отгружается, уже помечен «pending consolidation».

## Затронутые файлы
- `~/.claude/skills/claude-code-harness/references/harness-evolution.md` — refresh-ledger
  секция, external-intake Проход 1, re-test Проход 2, расширенный триггер, last-updated
  2026-06-16 (правка вне репо лаборатории — канон в глобальном скилле)

## Проверка
Перечитан изменённый раздел на связность (ledger → два прохода → ledger-update loop
замкнут). Прозовая процедура, runnable-оракула нет. Версии сверены эмпирически:
`plugin.json` v1.9.0 == 3×`shipped-by` v1.9.0; `native-capabilities.md` v2.1.173 ==
ledger-штамп.

## Related
- #105 — гигиена harness (frontmatter + CLAUDE.md-сверка), предыдущая запись
- #97 — kit v1.8.0 (отгружаемая выжимка + shipped-by re-sync), которую этот механизм
  теперь обслуживает на длинной дистанции
