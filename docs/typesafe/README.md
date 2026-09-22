# TypeSafe docs — local snapshot

**Выгружено:** 2026-09-19 с `https://docs.typesafe.ai/` (markdown-версии страниц, `.md` к пути).
**Относится к модели:** `jev-1.13.0` (алиасы `jev-latest` и `jev-preview` на дату выгрузки указывали на неё же).
**Версия SDK на момент выгрузки:** `typesafe-sdk==0.7.0`.
**Страница jaggedness помечена в источнике:** *Last reviewed 2026-09-17*.

33 страницы, 548 КБ. Файлы сохранены **байт-в-байт**, как отдаёт сервер: это исходный
MDX (компоненты `<ParamField>`, `<Tabs>`, `<Accordion>` и JS-блок `TypesafeExample`
на некоторых страницах). Ничего не переписывалось и не сокращалось.

Источник истины — живые доки. В консоли (`console.typesafe.ai/docs`) лежат
**устаревшие** примеры: модель `speed_latest`, пакет `typesafe_client`. Не использовать.

## Что где

| Раздел | Файлы |
|---|---|
| Индекс | `llms.txt` — полный список страниц и кукбуков, включая не выгруженные |
| Концепции | `introduction.md`, `concepts/system-one.md`, `concepts/how-to-build-with-system-one.md`, `concepts/state.md`, `concepts/use-case-map.md` |
| Примитивы | `primitives.md`, `primitives/{choice,score,noul,advanced}.md` |
| Уверенность | `confidence.md` |
| HTTP API | `api.md` — контракт `POST /v1/systemone` |
| Модели | `models.md` — версии, алиасы, цены, лимиты |
| Ограничения модели | `model-jaggedness/jev-1.13.md` — 9 failure modes, ссылки на неё нет в самом скилле |
| Миграция | `migrating-to-v1.md` — почему старые примеры не работают |
| Паттерны | `patterns.md`, `patterns/{fan-out,confidence-routing,composite-scoring,intent-routing}.md` |
| Python SDK | `sdk/python.md`, `sdk/python/usage.md`, `sdk/python/changelog.md`, `sdk/python/api/**` |

**Кукбуки не выгружены** — их ~19, список с описаниями есть в `llms.txt`. Кукбук часто
даёт лучшую декомпозицию, чем generic-классификатор: под конкретную задачу выгружать точечно.

## Проверено живым запросом (2026-09-19)

- `GET /v1/models` → 200, перечисляет только алиасы `jev-latest` / `jev-preview`.
- `POST /v1/systemone` с `model: "jev-1.13.0"` → принят, ответ вернул `model = "jev-1.13.0"`.
  Пин версии работает, хотя версионного ID нет в выдаче `/v1/models` (это соответствует
  `models.md`: «Versioned IDs such as `jev-1.13.0` are accepted whether or not they appear in the list»).
- `usage` вернулся с обоими полями: `input_tokens=284 output_tokens=23`.
