# Devlog

Хронология значимых изменений в проекте. Источник правды — `entries/*.md`,
`index.json` регенерируется из их frontmatter.

## Зачем

`git log` фиксирует коммиты (что), devlog фиксирует решения (зачем).
Squash-merge схлопывает мотивацию — devlog сохраняет её отдельно.
Читается человеком и LLM как путь развития проекта.

## Структура

```
.claude/devlog/
  index.json                 # АВТО-ГЕНЕРИРУЕТСЯ — не редактировать
  rebuild-index.py           # запускать после добавления записи
  README.md                  # этот файл
  entries/
    0001-bootstrap-...md     # frontmatter + body
    0002-...md
```

## Имя файла

`NNNN-slug.md`, где:
- `NNNN` — числовой id, zero-padded (0001, 0002, ...). Должен совпадать с `id` в frontmatter.
- `slug` — kebab-case, max 60 символов, **детерминированно** получается из `title` через `slugify()` в `rebuild-index.py`. Если slug в имени не совпадает со `slugify(title)` — индексер падает.

Чтобы получить корректное имя: добавь запись с черновым именем, запусти `rebuild-index.py`, переименуй файл в имя из ошибки.

## Frontmatter (схема)

```yaml
---
id: 17                              # required, int, уникальный
date: 2026-05-09                    # required, ISO YYYY-MM-DD
title: "Краткий заголовок"          # required, < 80 символов
tags: [feature, devlog]             # optional, список строк
status: complete                    # optional, default "complete"
supersedes: 12                      # optional, id записи, которую эта заменяет
---
```

`status`:
- `complete` — действующее изменение (default)
- `superseded` — заменено более новой записью (см. `supersedes` в новой)
- `wip` — work in progress (использовать редко; обычно записи делаются после завершения)

## Body (свободная форма)

Под frontmatter — markdown. Рекомендуемые секции:

```markdown
# {title}

## Контекст
Зачем — какая проблема решалась.

## Изменения
Что сделано. Code blocks, примеры, trade-offs.

## Затронутые файлы
- `path/to/file.py` — что изменилось

## Проверка
Команды, тесты, ручная проверка.

## Related
- #12 — кратко о связи
```

Структура body не валидируется — индексер не парсит body. Главное чтобы было читаемо человеком и LLM.

## Когда добавлять запись

**Добавляй**:
- Завершена фича / CLI-команда / endpoint
- Исправлен баг (поведенческий)
- Рефакторинг модуля (переименование, вынос, удаление дублирования)
- Изменение конфигурации, env vars, auth flow, API-контракта
- Изменение пайплайна обработки, промптов, моделей
- Принято архитектурное решение (отметь tag `adr` или сошлись на `.claude/docs/principles.md`)

**НЕ добавляй**:
- Опечатки, форматирование, комментарии
- Промежуточные состояния («wip»)
- Чтение кода / research / ответы без правок
- Косметика git-истории

## Как добавить запись

```bash
# 1. Найди следующий id (max в entries/ + 1):
ls .claude/devlog/entries/ | sort | tail -1

# 2. Создай файл с черновым slug'ом:
$EDITOR .claude/devlog/entries/0017-draft.md

# 3. Заполни frontmatter (id, date, title — обязательно).

# 4. Запусти rebuild — он покажет правильное имя файла:
python3 .claude/devlog/rebuild-index.py

# 5. Если ругается на slug — переименуй файл в имя из ошибки:
mv 0017-draft.md 0017-correct-slug-from-error.md

# 6. Запусти rebuild ещё раз — index.json обновится:
python3 .claude/devlog/rebuild-index.py
```

LLM может пропустить шаг 1-5 и сразу дать готовое имя — она знает функцию slugify из этого README.

## Иммутабельность

Запись фиксирует состояние **на момент события**. Не переписывается задним числом, даже если поведение из неё изменилось.

Если поведение изменилось:
1. Создай **новую** запись.
2. В новой записи: `supersedes: <id_старой>` в frontmatter.
3. В старой записи (опционально): `status: superseded` — индексер не требует, но удобно для фильтрации.

Допустимы только технические правки старых записей: опечатки, битые ссылки, несоответствие формата. **Суть события не редактируется.**

## Регенерация index.json

```bash
python3 .claude/devlog/rebuild-index.py
```

- `exit 0` — всё ок, index.json обновлён
- `exit 1` — ошибки в entries (показаны в stderr): отсутствуют поля, несовпадение id/имени файла, дубли id, slug разошёлся со slugify(title)

Скрипт идемпотентен — можно запускать сколько угодно раз. Подходит как pre-commit hook.

## Поиск

```bash
# Хронология
jq -r '.entries[] | "\(.date)  #\(.id)  \(.title)"' .claude/devlog/index.json

# По тегу
jq '.entries[] | select(.tags[]? == "bugfix")' .claude/devlog/index.json

# Записи за дату
jq '.entries[] | select(.date == "2026-05-09")' .claude/devlog/index.json

# Только действующие (без superseded)
jq '.entries[] | select(.status != "superseded")' .claude/devlog/index.json
```
