---
name: devlog
description: "Зафиксировать значимое изменение в .claude/devlog/ после завершения фичи, багфикса, рефакторинга, изменения конфига/CLI/API, добавления тестов или принятия архитектурного решения. Создаёт entries/NNNN-slug.md с YAML frontmatter и регенерирует index.json. Trigger on: '/devlog', 'запиши в devlog', 'обнови changelog', 'зафиксируй изменения', а также автоматически после значимых правок кода."
argument-hint: "[краткое описание изменения, опционально]"
allowed-tools: Read, Write, Bash(python3 .claude/devlog/rebuild-index.py), Bash(ls .claude/devlog/entries/*), Bash(git diff:*), Bash(git log:*), Bash(git status:*)
---

# Навык: ведение devlog

Добавляет запись в `.claude/devlog/entries/` после значимых изменений в проекте. Источник правды — markdown с frontmatter; `index.json` генерируется скриптом и не редактируется вручную.

## Когда использовать

- После завершения фичи, исправления бага, рефакторинга
- После изменения конфигурации, API-контракта, CLI-интерфейса, auth flow
- После принятия архитектурного решения
- Когда пользователь явно просит зафиксировать изменения

**НЕ** использовать для:
- Опечаток, форматирования, комментариев
- Промежуточных состояний (незавершённые изменения)
- Чтения кода, research, ответов без правок

## Алгоритм

### 1. Определи scope изменений

Используй один из вариантов:
- Незакоммиченные: `git diff --name-only` + `git diff --staged --name-only`
- В feature branch: `git diff main...HEAD --name-only`
- На main: `git diff HEAD~1 --name-only`
- Если пользователь указал конкретные изменения — используй их.

### 2. Определи следующий id

```bash
ls .claude/devlog/entries/ | grep -E '^[0-9]{4}-' | sort | tail -1
```

Возьми число из имени последнего файла + 1. Zero-pad до 4 цифр (0001, 0002, ..., 0017).

### 3. Сформулируй title и slug

- `title` — короткий заголовок (< 80 символов), глагол в прошедшем времени + что сделано. Пример: "Добавлена фильтрация по ключевым словам".
- `slug` — детерминированно из title через `slugify()`:
  1. lowercase
  2. все символы кроме `[a-z0-9]` → `-`
  3. сжать множественные `-` в один
  4. trim `-` по краям
  5. обрезать до 60 символов, trim хвостовой `-`

Имя файла: `NNNN-{slug}.md`. Если ошибся — `rebuild-index.py` подскажет правильное имя в ошибке.

### 4. Создай entry-файл

Путь: `.claude/devlog/entries/NNNN-slug.md`.

```markdown
---
id: <NNNN без zero-pad, как int>
date: <YYYY-MM-DD>
title: "<title>"
tags: [<тип>, <область>]
status: complete
---

# <title>

## Контекст
Какая проблема решалась или какая цель достигается. 2-4 предложения.

## Изменения
Что конкретно сделано. Ключевые решения и trade-offs. Code blocks где уместно.

## Затронутые файлы
- `path/to/file.py` — что изменилось

## Проверка
Команды, тесты, ручная проверка.

## Related
- #<id> — кратко о связи (если есть связанные записи)
```

**Tags** — комбинация типа и области:

| Тип | Когда |
|---|---|
| `feature` | Новая функциональность |
| `bugfix` | Исправление бага |
| `refactor` | Реструктуризация без изменения поведения |
| `config` | Изменение конфига, env vars, auth flow |
| `docs` | Значимые изменения документации |
| `security` | Уязвимость, улучшение безопасности |
| `test` | Добавление/изменение тестов |
| `cleanup` | Удаление мёртвого кода |
| `adr` | Архитектурное решение (контекст / motivation / consequences / alternatives) |

Область — свободная (например: `api`, `db`, `frontend`, `cli`, `prompts`, `harness`).

### 5. Регенерируй index.json

```bash
python3 .claude/devlog/rebuild-index.py
```

- `exit 0` + `index.json updated: N entries` — успех
- `exit 1` + ошибки в stderr — исправь и запусти снова. Типичные ошибки:
  - `required field 'X' missing` — добавь поле в frontmatter
  - `frontmatter id N != filename id M` — переименуй файл или поправь id
  - `filename slug 'X' != slugify(title)='Y'` — переименуй файл в `NNNN-Y.md`
  - `duplicate id N` — два файла с одним id, исправь нумерацию

### 6. Отчёт пользователю

```
Devlog обновлён: #<id> — <title>
Tags: <tags> | Файл: entries/NNNN-slug.md
Index: <N> записей
```

## Иммутабельность

Если изменение **отменяет или заменяет** существующую запись — НЕ редактируй старую. Создай новую с `supersedes: <id_старой>` в frontmatter. В body новой записи объясни, что именно изменилось и почему.

Допустимы только технические правки старых записей: опечатки, битые ссылки, несоответствие формата.

## Связь с другими артефактами

- **`.claude/docs/principles.md`** — harness principles (current state, evidence-based). Devlog-запись с tag `adr` ссылается на принципы по name (e.g., «Subagent spawn policy», «Skills frontmatter»).
- **`.claude/devlog/README.md`** — пользовательская инструкция (для команды), читать при первом знакомстве с devlog проекта.
