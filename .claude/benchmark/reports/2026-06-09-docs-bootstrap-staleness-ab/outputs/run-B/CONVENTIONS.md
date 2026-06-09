---
owner: "@nikitaCodeSave"
last-updated: 2026-06-09
status: active
---

# Conventions

Только **проектные паттерны и отклонения**, которые не очевидны и не выводятся из
общих best-practices конкретного стека. Базовые правила (PEP 8, ruff, biome,
mypy strict) задаются конфигами и здесь не повторяются — см. `backend/pyproject.toml`
(ruff/mypy strict) и `frontend/biome.json`.

## Backend

### Разделение SQLModel-моделей по роли
Каждая сущность в `app/models.py` представлена семейством классов, а не одним:

- `XBase` — общие поля.
- `XCreate` — то, что принимается на создание (например `UserCreate` добавляет
  `password`).
- `XUpdate` — частичное обновление, все поля Optional.
- `X` (`table=True`) — собственно таблица; добавляет серверные поля
  (`hashed_password`, `id`, `created_at`).
- `XPublic` — то, что отдаётся наружу (никогда не содержит `hashed_password`).
- `XsPublic` — обёртка-листинг `{ data: [...], count: int }`.

Правило: **`hashed_password` и прочие секреты не попадают в `*Public`**, наружу
никогда не возвращается ORM-объект напрямую без `response_model`.

### CRUD изолирован от роутеров
Доступ к данным живёт в `app/crud.py`, а не в маршрутах. Роутеры собирают
зависимости, проверяют права и вызывают `crud.*`. Простые однострочные запросы
(`session.get`, `session.exec`) допустимы прямо в роутере, но всё, что про
создание/мутацию пользователей/items, идёт через `crud`.

### UUID как первичные ключи
Все PK — `uuid.UUID` с `default_factory=uuid.uuid4`, не autoincrement int.
Обоснование — [ADR/0001-uuid-primary-keys.md](ADR/0001-uuid-primary-keys.md).

### Хеширование паролей — цепочка хешеров
`app/core/security.py` использует `pwdlib.PasswordHash(Argon2Hasher, BcryptHasher)`.
Argon2 — основной; bcrypt оставлен для верификации старых хешей. `verify_password`
возвращает кортеж `(verified, updated_hash)`; вызывающий код **обязан** сохранить
`updated_hash`, если он не `None` (прозрачная миграция хеша при логине — см.
`crud.authenticate`).

### Защита от timing/enumeration атак
При логине/recovery нельзя по тайму ответа или тексту ошибки понять, существует
ли email:
- несуществующий юзер → всё равно вызываем `verify_password(..., DUMMY_HASH)`
  (`crud.py`);
- `recover_password` всегда возвращает один и тот же текст;
- `reset_password` для несуществующего юзера отдаёт ту же ошибку, что и для
  невалидного токена.
Сохраняй этот паттерн при добавлении auth-эндпоинтов.

### Env-gated маршруты
Роутеры могут подключаться условно. `private` подключается только при
`ENVIRONMENT == "local"` (`app/api/main.py`). Это механизм для тест-/seed-only
эндпоинтов — не для фич-флагов в проде.

### Кастомный operation_id
`custom_generate_unique_id` в `main.py` задаёт operation_id = `{tag}-{name}`.
Из-за этого **первый тег роутера значим** — он становится префиксом имени метода
в сгенерированном фронт-клиенте (`LoginService`, `UsersService`, …). Всегда
задавай осмысленный `tags=[...]` у нового роутера.

### Конфигурация
Все настройки — через `Settings` (pydantic-settings) в `app/core/config.py`,
читающий корневой `../.env`. Не читай `os.environ` напрямую. Секреты со значением
`"changethis"` валятся при старте в non-local окружении (`_enforce_non_default_secrets`).

## Frontend

### Клиент API не пишется руками
`frontend/src/client/**` целиком генерируется из OpenAPI-схемы backend'а
(`npm run generate-client`, openapi-ts). Менять контракт → менять
Pydantic/SQLModel-модели backend'а и перегенерировать. То же для
`routeTree.gen.ts` (TanStack Router). Эти файлы — артефакты, не источник.

### Серверное состояние — только TanStack Query
Данные с API не складываются в локальный/контекстный state вручную: запросы и
мутации идут через `useQuery`/`useMutation` (см. `hooks/useAuth.ts` как образец —
включая `invalidateQueries` в `onSettled` и `handleError` в `onError`).

### Файловый роутинг
Маршруты определяются файлами в `src/routes/` (TanStack Router file-based).
Префикс `_layout` — pathless-layout для защищённых страниц; `__root` — корневой
layout. Новый маршрут = новый файл, не ручная регистрация.

### UI-примитивы — shadcn/ui
Базовые компоненты лежат в `src/components/ui/` (сгенерированы shadcn-стилем,
copy-in, не npm-зависимость). Кастомизируй их на месте; не дублируй примитив в
доменной папке.
