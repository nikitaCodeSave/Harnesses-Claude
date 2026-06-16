---
id: 12
date: 2026-05-10
title: "Trim ADR log + retire N>=3 invariant"
tags: [cleanup, harness]
status: complete
---

# Trim ADR log + retire N>=3 invariant

## Контекст

Пользовательский feedback после моего предложения ADR-17 (memory taxonomy):
**HARNESS-DECISIONS.md «выглядит как наиболее мешающийся артефакт, раздут
контекстом и часто мешает принимать решения»**. Это перерасставило
приоритет — сначала разобраться с самим форматом, потом думать про новые
ADR'ы. Заодно подтверждено, что `N≥3 эмпирических промахов` invariant
non-functional: счётчиков нет, mechanism никогда не accumulate'ил
incidents в реальности.

Остальные пункты с предыдущей повестки сняты:
- ADR-18 (MCP policy) — не нужен, MCP по дефолту желательны.
- Sandbox per-project bootstrap template — не нужен, sandbox исключён
  сознательно (ADR-009) и не используется.

## Изменения

**`docs/HARNESS-DECISIONS.md`: 384 → 263 строки (-32%, -121 строка)**.

Удалены полностью:
- `## ADR-001 — v0.1 trimmed agent catalog` — исторический, неактуален с ADR-007.
- `## ADR-005 — Managed Memory/Dreams концепции (SUPERSEDED)` — superseded ADR-15.
- `## ADR-006 — Onboarding всегда интервьюирует (SUPERSEDED)` — superseded ADR-007.
- `## ADR-008 — SessionStart context + effort guidance (sandbox part SUPERSEDED)` — sandbox-часть superseded ADR-009, оставшиеся компоненты (SessionStart hook, effort guidance) живут в файлах harness'а и meta-CLAUDE.md без необходимости в archive ADR.
- Блок `## Active inventory (computed view)` в начале файла — дублировал Reference materials в meta-CLAUDE.md.

Сжаты:
- ADR-014 раздел `**Урок процесса (двойной)**` (2 пункта × ~3 строки) → 1 строка.
- ADR-016 раздел `**Урок процесса (двойной)**` (2 пункта × ~3 строки) → 1 строка.

**Retire N≥3 invariant'а — 6 точек**:
- `.claude/CLAUDE.md` Foundational principle, блок `**Симметричное правило**` (5 строк) → переписан как «Когда компонент должен появиться: эмпирическое доказательство, что Opus 4.7 не делает X нативно ... single-incident в invariant не превращается, см. ADR-014».
- `.claude/CLAUDE.md` Re-evaluation triggers, bullet `**N≥3 эмпирических промахах** одного типа в текущей модели...` → переписан как «**повторяющемся эмпирическом промахе** в текущей модели на одном classes-of-tasks (transcript-доказательство, не ощущение)».
- `docs/HARNESS-DECISIONS.md` ADR-014 Обоснование §1 (`Foundational principle проверен симметричным правилом ... N=1 ... N≥3 не выполнено`) → «Single-incident observation: один эмпирический случай ... Single incident → не invariant».
- `docs/HARNESS-DECISIONS.md` ADR-014 запрет на возврат (`без N≥3 эмпирических промахов (см. симметричное правило)`) → «без empirical evidence что Opus 4.7 регулярно проигрывает контракт-куски в agentic workflow».
- `docs/HARNESS-DECISIONS.md` ADR-15 Обоснование §2 (warm-context, `N=0 эмпирических промахов → не добавляется ... допустим после N≥3`) → «Эмпирических промахов нет → не добавляется. Slash command как тонкий prompt-template — допустим только при подтверждённой повторяющейся потребности».
- `docs/HARNESS-DECISIONS.md` ADR-15 запрет на возврат (`без N≥3 эмпирических случаев`) → «без empirical evidence что (а) auto-loaded источники недостаточны и (б) prompt не покрывает потребность».

**`.claude/CLAUDE.md`: 153 → 151 строка** (минимальный trim — удалён блок «Симметричное правило» 5 строк, заменён на 4 строки про empirical evidence + N≥3 bullet в Re-evaluation triggers заменён эквивалентной строкой про «повторяющийся эмпирический промах»).

## Затронутые файлы

- `docs/HARNESS-DECISIONS.md` — Write полная перезапись (263 строки).
- `.claude/CLAUDE.md` — два Edit'а (Foundational principle + Re-evaluation triggers).

## Проверка

```
$ wc -l docs/HARNESS-DECISIONS.md .claude/CLAUDE.md
  263 docs/HARNESS-DECISIONS.md
  151 .claude/CLAUDE.md

$ grep -i 'n≥3\|n>=3\|n=3\|симметрич' docs/HARNESS-DECISIONS.md .claude/CLAUDE.md
(no matches)
```

Все ссылки на N≥3 / симметричное правило удалены. ADR-references (`ADR-006 superseded`, `Supersedes ADR-008`) оставлены в active ADR'ах как git-archeology — сами ADR-файлы удалены, но контекст истории читаем.

## Что НЕ сделано (сознательно)

- НЕ создан ADR-17 (memory taxonomy) — пользовательский feedback переадресовал
  приоритет на сам формат ADR-лога. Memory taxonomy остаётся открытым
  вопросом, может вернуться отдельно.
- НЕ создан ADR-18 (MCP policy) — пользователь сказал «MCP по дефолту желательны,
  не нужно отдельно напоминать». Implicit policy сохраняется.
- НЕ создан sandbox per-project bootstrap template — sandbox исключён сознательно,
  per-project use-case не требуется.
- НЕ создан новый ADR на эту правку — это maintenance trim существующих ADR'ов
  (формат сжат, retire N≥3 распределён по 6 точкам в трёх ADR'ах), а не новое
  архитектурное решение. Devlog-запись + git history покрывают traceability.

## Related

- #5 (`adr-007-retire-6-skills-2-agents-built-ins`) — родственная retire-операция.
- #8 (`trim-harness-per-opus-4-7-foundational-principle-adr-010-011`) — родственный trim.
- #11 (`adr-016-multi-agent-baseline-pilot-validation`) — последний ADR перед этим trim'ом.
