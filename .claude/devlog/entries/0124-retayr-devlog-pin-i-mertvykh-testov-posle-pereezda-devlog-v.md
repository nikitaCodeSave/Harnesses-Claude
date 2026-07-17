---
id: 124
date: 2026-07-17
title: "Ретайр devlog-pin и мёртвых тестов после переезда devlog в плагин"
tags: [cleanup, harness, devlog, docs]
status: complete
---

# Ретайр devlog-pin и мёртвых тестов после переезда devlog в плагин

## Контекст
Проверка установки плагина вскрыла хвосты миграции devlog в `devlog@skills-dir` (16.07): репо продолжал держать собственную копию `rebuild-index.py` от 11.06, а 306 строк тестов защищали SessionStart-хук, которого больше нет. Доки описывали оба как живые.

Плагин не переустанавливался — установка корректна: `claude-code-harness@skills-dir` + `devlog@skills-dir`, оба v1.17.3, symlink'ами на source-of-truth репо, дублей глобального слоя нет. Чинился только drift, который миграция оставила в лаборатории.

## Изменения

**Ретайр project-pin `rebuild-index.py`.** Копия отставала от плагинной на месяц и по правилу SKILL.md («при наличии project-копии используй её») перебивала канон. Плагинный `devlog-reindex` даёт идентичный вывод на 122 из 123 записей; разошлась одна (#103) — плагин перешёл на language-agnostic preview (первая `##`-секция вместо hardcoded `## Контекст`), а #103 начинается с `## Откачено`. Приняли плагинный вывод как канон, конвент дописан в `devlog/README.md`.

**Ретайр тестов ретайрнутого хука.** `test-session-context.sh` (243 строки) + `test-session-context-hook.sh` (63) целились в `~/.claude/hooks/session-context.sh` — файл удалён 15.07, тесты давали 28 FAIL и ничего не защищали. Покрытие не потеряно: boundedness, CLOSED-маркер, odd filenames и progress-поведение живут в `test-session-start-digest.sh` рядом с хуком (38 PASS); два tldr-класса (stale shadowing, unbounded 10 MB fast path) устранены конструктивно — новый хук читает только `entries/`.

**Layer A check #4 перенацелен.** `static-checks.sh` резолвит `devlog-reindex` на PATH с фолбэком на bundle-путь — плагин кладёт команду в PATH Bash-инструмента, но не в обычный терминал.

**Доки пересинхронизированы.** Устранены dangling-ссылки на pin (6 доков) и на два хука, которых нет (`session-context`, `test-quality-reminder`): активны ровно два внешних — `system-guard` (глобальный) и `session-start-digest` (плагин).

**Мусор в `settings.local.json`.** 17 allow-записей → 1: остальные ссылались на ретайрнутый loop-кластер, несуществующие хуки и одноразовые debug-команды.

**Дубль в соседнем проекте.** Удалён `AI_analyst_migration_battletest/.claude/skills/devlog/` — копия, перекрытая плагином. Сам worktree (живая ветка `feature/client-product-migration`, 3 незапушенных коммита) не тронут: оператор подтвердил scope до удаления.

## Затронутые файлы
- `.claude/devlog/rebuild-index.py` — удалён (267 строк)
- `.claude/benchmark/audit/test-session-context{,-hook}.sh` — удалены (306 строк)
- `.claude/benchmark/static-checks.sh` — check #4 на `devlog-reindex` + фолбэк
- `.claude/devlog/README.md` — источник скрипта + language-agnostic preview-конвент
- `.claude/CLAUDE.md`, `.claude/docs/{principles,harness-architecture,memory-layers,benchmark}.md`, `.claude/skills/update-plan-progress/SKILL.md`, `README.md` — pin + hook-инвентарь
- `.claude/settings.local.json` — 17 allow → 1

## Проверка
- `static-checks.sh` — 12/12 PASS; фолбэк проверен в `env -i` без plugin-PATH → 123 entries, valid
- `test-system-guard.sh` — 109 PASS / 0 FAIL
- kit `test-session-start-digest.sh` — 38 PASS / 0 FAIL; `pytest test_rebuild_index.py` — 7 passed
- grep live-слоя на `rebuild-index` и на ретайрнутые хуки — чисто (archive и devlog-записи не тронуты per docs-discipline rule #3)

## Related
- #123 — предыдущий system-guard-трек; его тесты остались единственным audit-набором в `benchmark/audit/`
- #121 — drift-remediation kit v1.15.0, тот же класс: миграция оставляет хвосты в лаборатории
