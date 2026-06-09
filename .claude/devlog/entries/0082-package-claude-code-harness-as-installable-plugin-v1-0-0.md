---
id: 82
date: 2026-06-10
title: "Package claude-code-harness as installable plugin v1.0.0"
tags: [harness, dogfood, skills, packaging]
status: complete
---

# Package claude-code-harness as installable plugin v1.0.0

## Контекст
Финал dogfood-трека (#78–#81). Исходный запрос оператора — «готовый kit для старта нового
проекта» — имел две части: содержание (доказано dogfood'ом: пустое репо → работающий
NL→SQL SGR-агент за 6 фич, grounded e2e, анти-паттерн избегнут) и форму (упаковка,
отложенная в grill Q5 до эмпирики). Содержание доказано двумя D-циклами → оператор дал
«упаковка kit'а». Форма выбрана каноничная и CLI-only: Claude Code plugin + marketplace.

## Изменения
В `~/.claude` (репозиторий `dot-claude`, commit c4282d4):
- **`skills/claude-code-harness/.claude-plugin/plugin.json`** — манифест плагина v1.0.0,
  сгенерирован нативным `claude plugin init` (skill-dir layout `"skills": ["./"]`, SKILL.md
  не тронут). Версия поднята 0.1.0→1.0.0: kit доказан живым продуктом.
- **`.claude-plugin/marketplace.json`** — `dot-claude` как Claude Code marketplace, экспонирует
  kit (source `./skills/claude-code-harness`, category workflow).
- **`.gitignore`** — whitelist `/.claude-plugin/` (корневой манифест иначе игнорировался
  whitelist-режимом `/*`).
- **README** — два пути доставки: `git clone ~/.claude` (весь слой авто-загрузкой) |
  `claude plugin marketplace add nikitaCodeSave/dot-claude` + `install` (только kit).

## Проверка
- JSON обоих манифестов валиден (`json.load`).
- `claude plugin marketplace add /home/nikita/.claude` → marketplace зарегистрирован и виден
  в `marketplace list`; `plugin details claude-code-harness` → v1.0.0, 0 always-on токенов.
- `marketplace add` записал машинно-абсолютный путь в трекаемый `settings.json` — выявлено и
  откачено (`marketplace remove`); репо-артефакт раздачи = сам `marketplace.json`, не
  локальная регистрация. settings.json остался чист (лишь не-моя перестановка ключа model).
- Граница верификации (честно): manifest + регистрация + details проверены; полная
  установка `install` на чистый второй профиль/машину не гонялась — это требует чистого
  окружения; first-party `init`-генерированная раскладка принята как каноничная.

## Затронутые файлы
- `~/.claude/skills/claude-code-harness/.claude-plugin/plugin.json` — новый
- `~/.claude/.claude-plugin/marketplace.json` — новый
- `~/.claude/.gitignore`, `~/.claude/README.md` — правки
- `.claude/progress/dogfood-sgr-kit.md` — трек закрыт

## Related
- #81 — D.2 (kit-содержание доказано перед упаковкой)
- #78 — план dogfood-трека (упаковка = его финальная цель)
