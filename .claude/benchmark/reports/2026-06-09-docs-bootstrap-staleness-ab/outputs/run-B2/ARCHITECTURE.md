---
owner: "@nikitaCodeSave"
last-updated: 2026-06-09
status: active
---

# Architecture

Full-stack приложение: FastAPI-бэкенд (Python/SQLModel/PostgreSQL) + React-SPA
(TypeScript/Vite), связанные авто-генерируемым из OpenAPI клиентом. Раздаётся через
Docker Compose за Traefik. Это также **Copier-шаблон** — репозиторий одновременно живой
проект и генератор новых проектов (см. `copier.yml`, `.copier/`, `hooks/`).

## Компоненты

| Компонент | Технологии | Точка входа | Назначение |
|---|---|---|---|
| **backend** | FastAPI, SQLModel, Pydantic v2, Alembic | `backend/app/main.py` → `app.api.main.api_router` | REST API под `/api/v1`, аутентификация, CRUD |
| **frontend** | React 19, TypeScript, Vite, TanStack Router/Query, shadcn/ui, Tailwind v4 | `frontend/src/main.tsx` | SPA-дашборд, потребляет API через сгенерированный клиент |
| **db** | PostgreSQL 18 | — | единственное хранилище состояния |
| **prestart** | тот же образ, что backend | `backend/scripts/prestart.sh` | ждёт БД → `alembic upgrade head` → создаёт первого суперюзера |
| **proxy** | Traefik | `compose.traefik.yml` | reverse-proxy, TLS (Let's Encrypt), маршрутизация по поддоменам |
| **adminer** | Adminer | — | веб-UI для инспекции БД |

### Бэкенд (слои)

```
api/routes/*.py   — HTTP-эндпоинты (login, users, items, utils, private)
   │  зависят от
api/deps.py        — DI: get_db (Session), get_current_user, get_current_active_superuser
   │
crud.py            — операции с БД (create_user, authenticate, create_item, ...)
core/security.py   — хеширование паролей (pwdlib: Argon2+bcrypt), JWT (HS256)
core/config.py     — Settings (pydantic-settings, читает ../.env)
core/db.py         — engine + init_db (сидинг первого суперюзера)
models.py          — SQLModel-модели + Pydantic-схемы (User, Item, Token, ...)
utils.py           — email (jinja2-шаблоны + lib `emails`), reset-токены
```

Маршрут `private` (`/api/v1/private/*`) подключается **только при `ENVIRONMENT=local`**
(`api/main.py`) — используется e2e-тестами для прямого создания пользователей.

### Фронтенд

- **Роутинг** — TanStack Router, file-based. `routeTree.gen.ts` генерируется автоматически
  (router-plugin), коммитить вручную не нужно.
- **`src/client/`** — **сгенерированный** OpenAPI-клиент (`@hey-api/openapi-ts`, см.
  `openapi-ts.config.ts`). Сервисы вида `LoginService`, `UsersService`, `ItemsService`.
  **Не редактировать руками** — регенерируется из `openapi.json` бэкенда.
- **Серверное состояние** — TanStack Query (`useQuery`/`useMutation`).
- **Аутентификация** — JWT в `localStorage` под ключом `access_token`
  (`hooks/useAuth.ts`). `main.tsx` ставит токен в `OpenAPI.TOKEN` и на ответах 401/403
  чистит токен и редиректит на `/login`.

## Поток данных

### Логин
```
LoginForm → LoginService.loginAccessToken
  → POST /api/v1/login/access-token (OAuth2PasswordRequestForm)
  → crud.authenticate (verify_password, constant-time даже для несуществующего email)
  → security.create_access_token (JWT HS256, exp = ACCESS_TOKEN_EXPIRE_MINUTES)
  → { access_token } → localStorage["access_token"]
```
Последующие запросы шлют `Authorization: Bearer <jwt>`; `deps.get_current_user`
декодирует JWT, грузит `User` по `sub` (UUID), проверяет `is_active`.

### Авторизация
Два уровня поверх `get_current_user`:
- **owner-scoping** — `items`: не-суперюзер видит/правит только свои записи
  (`owner_id == current_user.id`), суперюзер — все.
- **superuser-only** — управление пользователями, `utils/test-email`
  (через `get_current_active_superuser`).

### Восстановление пароля
`POST /password-recovery/{email}` → генерируется JWT-reset-токен (`utils.py`) →
письмо через SMTP (jinja2-шаблон) → `POST /reset-password/` с токеном меняет пароль.
Эндпоинты восстановления намеренно дают одинаковый ответ независимо от существования
email (защита от user-enumeration).

## Внешние сервисы

| Сервис | Когда | Конфиг |
|---|---|---|
| **PostgreSQL** | всегда | `POSTGRES_*` → `SQLALCHEMY_DATABASE_URI` (драйвер `psycopg`) |
| **SMTP** | если заданы `SMTP_HOST` + `EMAILS_FROM_EMAIL` (`emails_enabled`) | `SMTP_*`, `EMAILS_FROM_*` |
| **Sentry** | если `SENTRY_DSN` и `ENVIRONMENT != local` | `SENTRY_DSN` |
| **Traefik / Let's Encrypt** | production/staging | `compose.traefik.yml`, лейблы в `compose.yml` |
| **Mailcatcher** | локальная разработка (перехват писем) | `compose.override.yml` |

## Конфигурация

Единый `.env` в корне читается и Docker Compose, и бэкендом
(`SettingsConfigDict(env_file="../.env")`). `config.py` принудительно запрещает
дефолтные секреты (`changethis`) вне `local` (валидатор `_enforce_non_default_secrets`).

## Развёртывание

Docker Compose, три окружения (`local`/`staging`/`production`). Образы backend/frontend
собираются из `*/Dockerfile`; маршрутизация Traefik по поддоменам
(`api.`, `dashboard.`, `adminer.`). CI/CD — GitHub Actions (`.github/workflows/`):
тесты бэкенда, Playwright, docker-compose smoke, деплой staging/production.
Детали — `deployment.md`.

## Связанные документы
- [CODE-MAP.md](./CODE-MAP.md) — где что лежит
- [GLOSSARY.md](./GLOSSARY.md) — термины предметной области
- [CONVENTIONS.md](./CONVENTIONS.md) — паттерны, специфичные для проекта
- `development.md` / `deployment.md` — операционные процедуры
