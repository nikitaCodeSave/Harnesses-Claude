---
owner: "@nikitaCodeSave"
last-updated: 2026-06-09
status: active
---

# Conventions

Только **специфичные для этого проекта** паттерны — то, что не выводится из общих
best-practices и где легко ошибиться. Базовый стиль обеспечивают ruff/mypy (бэкенд) и
Biome (фронтенд) автоматически; здесь — лишь расхождения и неочевидные договорённости.

## Бэкенд

### Семейство схем на сущность (SQLModel)
Каждая доменная сущность описывается **семейством классов**, а не одной моделью
(`backend/app/models.py`):

- `XBase` — общие поля.
- `XCreate` / `XUpdate` (+ при нужде `XRegister`, `XUpdateMe`) — входные схемы API.
- `X(table=True)` — таблица БД (имя таблицы = lowercase имени класса).
- `XPublic` — выходная схема (исключает чувствительные поля, напр. `hashed_password`).
- `XsPublic` — список: `{ data: list[XPublic], count: int }`.

Добавляя поле, реши, в какие классы семейства оно входит. Не возвращай table-модель из
API напрямую — только `XPublic`.

### CRUD отделён от роутов
Операции с БД, переиспользуемые между эндпоинтами (создание/аутентификация/обновление
пользователя, создание item), живут в `crud.py` и принимают `session` keyword-only
(`def create_user(*, session, user_create)`). Роуты вызывают `crud.*`; одноразовую
inline-логику роут может делать сам (см. `items.py`).

### Зависимости как типы-алиасы
DI оформлен через `Annotated`-алиасы в `api/deps.py`, используй их в сигнатурах:
- `SessionDep` — сессия БД.
- `CurrentUser` — аутентифицированный пользователь (по JWT).
- `Depends(get_current_active_superuser)` — гейт «только суперюзер».

### Проверки доступа — в обработчике
Owner-scoping и superuser-only проверяются **внутри** обработчика явными `if` +
`HTTPException` (см. `items.py`), а не декораторами. Соблюдай те же коды: `404` — не
найдено, `403` — недостаточно прав, `400` — неактивный/некорректный ввод.

### Конфигурация — только через Settings
Любая env-переменная объявляется в `Settings` (`core/config.py`); не читай `os.environ`
по месту. Вычисляемые значения — `@computed_field` (`SQLALCHEMY_DATABASE_URI`,
`all_cors_origins`, `emails_enabled`). Секреты со значением `changethis` запрещены вне
`ENVIRONMENT=local` (валидатор кидает ошибку на старте).

### Безопасность по умолчанию
- Пароли — только через `core/security.py` (`get_password_hash` / `verify_password`),
  никогда не хешируй вручную.
- Эндпоинты, завязанные на существование email (login, recovery, reset), **обязаны**
  давать одинаковый ответ для существующего и несуществующего пользователя
  (анти-enumeration; см. `crud.authenticate` с `DUMMY_HASH` и `login.py`).

### Миграции
Схема меняется **только** через Alembic. После правки `models.py`:
`alembic revision --autogenerate -m "..."`, проверь сгенерированный файл в
`alembic/versions/`. БД в проде создаётся миграциями, не `create_all` (см. `core/db.py`).

### Первичные ключи — UUID
Все таблицы используют `uuid.uuid4` PK (`default_factory`), не автоинкремент-int.

## Фронтенд

### Сгенерированный код не редактируется руками
- `src/client/**` — клиент API (`@hey-api/openapi-ts`). Меняется через
  `scripts/generate-client.sh` после изменения API. Импорт из `@/client`.
- `src/routeTree.gen.ts` — дерево роутов (TanStack Router plugin).

Правки в этих файлах будут затёрты при регенерации.

### API — только через сервисы клиента
Никаких ручных `fetch`/`axios` к бэкенду — вызывай сгенерированные сервисы
(`LoginService`, `UsersService`, `ItemsService`) внутри TanStack Query
(`useQuery`/`useMutation`). Серверное состояние не дублируется в локальном стейте.

### Роутинг — file-based
Страница = файл в `src/routes/`. Защищённые страницы — под `_layout/` (layout требует
логина). Публичные (`login`, `signup`, `recover-password`, `reset-password`) — в корне
`routes/`.

### Аутентификация
Токен — в `localStorage["access_token"]`; доступ к нему только через `useAuth` и
конфиг `OpenAPI.TOKEN` в `main.tsx`. Глобальная обработка 401/403 (чистка токена +
редирект на `/login`) централизована в `QueryCache`/`MutationCache` (`main.tsx`) — не
дублируй её в компонентах.

### UI-компоненты
Примитивы — shadcn/ui в `components/ui/` (добавляются через CLI shadcn, см.
`components.json`). Фичевые компоненты — в `components/<Feature>/`. Классы Tailwind
комбинируй через `cn()` из `src/lib/utils.ts`.

## Инструменты (расхождения от типового стека)
- Python-зависимости — **uv** (не pip/poetry); фронтенд — **bun** (не npm).
- Форматтер/линтер фронтенда — **Biome** (не ESLint+Prettier).
- Хеши паролей — **pwdlib** с Argon2 (не passlib/bcrypt-напрямую).

## Связанные документы
- [ARCHITECTURE.md](./ARCHITECTURE.md) · [CODE-MAP.md](./CODE-MAP.md) · [GLOSSARY.md](./GLOSSARY.md)
- Дисциплина поддержки доков — `.claude/rules/docs-discipline.md`
