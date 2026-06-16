---
id: 54
date: 2026-05-29
title: "Continuity pillar — global SessionStart context hook"
tags: [feature, harness, hooks]
status: complete
---

# Continuity pillar — global SessionStart context hook

## Контекст
Второй столб practice-слоя (после methodology, #53): сделать «что было до» глобальным
дефолтом. Раньше continuity-сёрфинг работал ТОЛЬКО в этом lab-репо через project-level
`.claude/hooks/session-context.sh`. Цель — в ЛЮБОМ проекте Claude при старте видит недавнюю
историю работы без ручного напоминания.

## Дизайн-решение (resolved до кода)
Три continuity-слоя разведены по **оси времени и происхождению** — НЕ дублируют:
- **devlog** — *эпизодическая* история «что изменилось и почему», git-tracked, team-shared, in-repo.
- **progress** — *in-flight* состояние одной long-running задачи; переживает interrupt/compact.
- **авто-память** (`MEMORY.md`) — *атемпоральные* факты; грузится сама.

Continuity-хук сёрфит именно **темпоральный/in-flight** срез (devlog + progress), которого
память по определению не держит → комплементарны, не дубль.

**Git НЕ включён** в хук: built-in система Claude Code уже инжектит branch/uncommitted/recent-commits
при старте. Повтор нарушил бы central principle «harness кодирует ДЕЛЬТУ, не БАЗУ». (Решение
оператора, рекоменд. вариант.)

## Изменения (всё в ГЛОБАЛЬНОМ слое, кроме de-dup)
1. **`~/.claude/hooks/session-context.sh`** (new, SessionStart, project-agnostic) — последние 3
   devlog-записи (`#id title` из frontmatter) + активный `.claude/progress/*.md` (имя + Quick
   state). **Молча `exit 0`**, если нет ни devlog, ни progress (сработает во ВСЕХ проектах,
   включая не-dev). Только чтение, advisory, без сети.
2. **`~/.claude/settings.json`** — SessionStart-хук подключён (бэкап `settings.json.bak-*`,
   JSON провалидирован). Аддитивно к существующим Pre/Post/Stop.
3. **`~/.claude/CLAUDE.md` §6 Continuity** — standing-инструкция о трёх слоях + их ролях
   (привычка = surfacing + лёгкая строка, рекоменд. вариант; без Stop-nudge).
4. **De-dup лабового `.claude/hooks/session-context.sh`** — урезан до **только loop-STATE**
   (его lab-unique часть); devlog+progress убраны (теперь глобальны). Оба хука срабатывают в
   этом репо без пересечения.

## Проверка
- **Reproduce-test** `.claude/benchmark/audit/test-session-context-hook.sh` (поведенческий, 10
  ассертов): empty-проект → silent+exit 0; devlog-only → last-3 с титулами + drop oldest;
  progress-only → имя+quick-state; both → обе секции + валидный JSON `additionalContext`.
- **Mutation-test** (stub-хук через `HOOK=` override) → 7 FAIL / 3 PASS: оракул дискриминирует,
  не псевдо-тест. Реальный хук → 10/10.
- **Dogfood** против этого репо: глобальный хук поднял #51/#52/#53 + progress; лабовый — только
  `Loop: iter-39 ...`; пересечения нет.

## Blast radius / обратимость
Правки в global `~/.claude/` (хук + settings + CLAUDE.md §6) объявлены явно. Хук exit-0/advisory/
silent-когда-нерелевантно. Откат = удалить хук + restore `settings.json.bak-*` + revert §6.

## Затронутые файлы
- `~/.claude/hooks/session-context.sh` (new), `~/.claude/settings.json`, `~/.claude/CLAUDE.md` (§6)
- `.claude/hooks/session-context.sh` (trimmed to loop-STATE)
- `.claude/benchmark/audit/test-session-context-hook.sh` (new)

## Related
- #53 — methodology-столб (этот — второй из трёх: continuity).
- #52 — бенчмарк (ценность harness'а в continuity/методологии, не bootstrap).
- Next: **guardrails** (per-project settings/what-not-to-do) + правильный мульти-сессийный
  бенчмарк practice-слоя (single-shot зануляет ценность continuity).
