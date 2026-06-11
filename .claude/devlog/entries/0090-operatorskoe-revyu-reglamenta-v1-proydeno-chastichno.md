---
id: 90
date: 2026-06-11
title: "Операторское ревью Регламента v1 пройдено частично"
tags: [docs, harness]
status: complete
---

# Операторское ревью Регламента v1 пройдено частично

## Контекст
Трек «Регламент v1» закрыт агентом (devlog #86/#87); оставался ручной операторский чеклист `.claude/progress/operator-review.md` — шаги 1–3 обязательные, 10 вопросов В1–В10. Оператор прошёл их 2026-06-11; часть вопросов закрыта решениями, часть осознанно отложена до практики. Файл ревью усечён до открытых хвостов, не удалён.

## Изменения
**Шаг 1 (AI_analyst_migration) — закрыт.** Оператор внёс правки: `d2ee0c8` — ослабление read-deny по В2; `91879dd` — devlog forward-only стандартизация. Ключевое решение: **`main` в migration — архивный слепок, в него не пушить и не мержить; вся живая работа в `feature/client-product-migration`**. Чеклист ошибочно предлагал `git push origin main` и считал ahead от origin/main — исправлено; feature-ветка запушена целиком. Решение сохранено в auto-memory (`project_migration_main_is_archive.md`).

**Шаг 2 (канон `~/.claude`) — закрыт частично.** Вопрос оператора «скилл `claude-code-harness` лежит в папке навыков, но оформлен как плагин — корректно ли?» разобран и закрыт: каталог намеренно несёт две роли — user-skill (SKILL.md из skills-dir) + плагин через `.claude-plugin/plugin.json`, автоматически смонтированный как `claude-code-harness@skills-dir` (несёт команду `external-audit` + 3 аудит-агента). Verified live: `claude plugin details` → v1.3.0 (на момент проверки), Agents 3, ~486 tok always-on; расхождение «Skills 1 vs 2 из чеклиста» — корневой скилл не дублируется плагином на машине оператора (на чистом профиле — Skills 2, см. T1-REPORT). Содержательный акцепт playbook (В7/В8) отложен до практики.

**Шаг 3 (prompt-regress) — закрыт.** Тулза прогнана оператором на реальных CSV; ценность подтверждена: порт/обобщение ad-hoc `dev/validation/`-скриптов донора в офлайн-тестируемый regression-оракул с CI exit-code. В9/В10 — приняты дефолты (траектория F2–F4 как есть; GitHub-remote не создаём).

**Открытые хвосты** (живут в усечённом `operator-review.md`):
- Watch D2 + В7/В8 — закрываются первой реальной задачей через обновлённый `/implement` в migration (хуже без TDD-тройки → `git revert 6525025`).
- Docstring `application/agent.py:5` («8-шагового pipeline») — одна строка в следующем PR, трогающем код.
- Push kit v1.4.0 из `~/.claude` — за оператором (см. #89).

## Затронутые файлы
- `.claude/progress/operator-review.md` — усечён до открытых хвостов
- `~/PROJECTS/AI_analyst_for_work/AI_analyst_migration` — push feature-ветки (91879dd), без правок файлов
- `~/.claude/projects/.../memory/project_migration_main_is_archive.md` — новая memory-запись

## Проверка
- `git push origin feature/client-product-migration` → `d2ee0c8..91879dd`, ветка синхронизирована с origin; main не тронут.
- `claude plugin details claude-code-harness` → плагин доставляется из skills-dir, команда и 3 агента доступны в живой сессии.
- `promptdiff compare` на реальных CSV донора — отчёт сгенерирован (прогон оператора).

## Related
- #86 — релиз Регламента v1, предмет ревью
- #87 — пять решений от лица оператора; В1–В6 их подтвердили (В2 — с ослаблением read-deny)
- #89 — kit v1.4.0; push за оператором
