---
id: 1
date: 2026-05-09
title: "Bootstrap devlog scaffold"
tags: [feature, devlog, harness]
status: complete
---

# Bootstrap devlog scaffold

## Контекст

Harness задумывался как минимальная стартовая обвязка для новых проектов под Opus 4.7. Devlog нужен с первой сессии — без него каждая последующая сессия Claude Code читает код «без памяти команды», теряет мотивацию решений и трактует squash-мерджи как однострочные изменения.

До этого автор пробовал два формата в реальных проектах:
- `devlog/changelog.json` (HH_parser, AI_analyst_migration) — монолитный JSON. Простой, но растёт линейно: после 200 записей контекст-бюджет на чтение неоправдан.
- `logs/index.json + logs/entries/*.md` (dialog_analyzer) — индекс + детали. Перспективно, но дуальная writable-структура давала рассинхронизацию (запись в index есть, файла нет; или наоборот).

## Изменения

Третья итерация — `index.json` как **производное** от entries. Источник правды один: frontmatter в `entries/*.md`. `index.json` регенерируется через `rebuild-index.py`. Невозможна рассинхронизация.

Минималистичная схема frontmatter:
- **required**: `id`, `date`, `title`
- **optional**: `tags`, `status` (default `complete`), `supersedes`

Поля `motivation`, `scope`, `summary`, `breaking`, `related`, которые автор использовал в предыдущих итерациях, **выкинуты из frontmatter** — они живут в body markdown. Это даёт свободу формы (длинные описания, code blocks, trade-offs без эскейпа) и убирает дублирование «кратко в поле + детально в body».

Имя файла обязано быть `NNNN-slug.md`, где `slug = slugify(title)`. Проверяется индексером — если расходится, скрипт падает с подсказкой правильного имени. Это убирает разнобой slug-неймига.

Иммутабельность реализована через `supersedes: <id>` — новая запись ссылается на старую, старая не редактируется. Записи фиксируют состояние на момент события.

## Затронутые файлы

- `.claude/devlog/rebuild-index.py` — индексер: парсит frontmatter, валидирует имя файла и id, генерирует `index.json`
- `.claude/devlog/index.json` — авто-генерируемый
- `.claude/devlog/README.md` — инструкция (схема, slug-правило, supersedes, регенерация, jq-примеры)
- `.claude/devlog/entries/0001-bootstrap-devlog-scaffold.md` — эта запись
- `.claude/devlog/entries/.gitkeep` — для git
- `.claude/CLAUDE.md` — добавлены ссылки на devlog и foundational principle про минимум обвязки

## Проверка

```bash
python3 .claude/devlog/rebuild-index.py
# index.json updated: 1 entries
```

Содержимое `index.json` после запуска должно содержать одну запись с `id: 1`, `path: "entries/0001-bootstrap-devlog-scaffold.md"`.

## Связанные решения

См. `docs/PRACTICES-FROM-PROJECTS.md` раздел 11.2 — обоснование выбора схемы (после ultrathink-сессии 2026-05-09).
