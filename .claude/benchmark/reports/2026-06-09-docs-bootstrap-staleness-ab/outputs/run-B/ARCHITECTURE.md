---
owner: "@nikitaCodeSave"
last-updated: 2026-06-09
status: active
---

# Architecture

Full-stack приложение: FastAPI backend + React SPA frontend, общающиеся через
типизированный REST API под `/api/v1`. Всё оркестрируется Docker Compose;
в проде перед сервисами стоит Traefik (TLS + роутинг по поддоменам).

## Компоненты

| Компонент | Стек | Точка входа | Роль |
|---|---|---|---|
| **backend** | FastAPI · SQLModel · Pydantic v2 · Alembic | `backend/app/main.py` → `app` | REST API, бизнес-логика, ORM, аутентификация |
| **frontend** | React 19 · TanStack Router/Query · Tailwind 4 · shadcn/ui · Vite | `frontend/src/main.tsx` | SPA-дашборд, потребляет API через сгенерированный клиент |
| **db** | PostgreSQL 18 | `compose.yml` service `db` | Хранилище; схема версионируется Alembic-миграциями |
| **prestart** | один-shot контейнер | `backend/scripts/prestart.sh` | Ждёт healthy БД, прогоняет миграции, сидит первого суперюзера |
| **adminer** | Adminer | `compose.yml` service `adminer` | Web-UI для инспекции БД (за Traefik) |

Backend и frontend собираются из одного репо, но это **независимо деплоящиеся**
образы (`DOCKER_IMAGE_BACKEND`, `DOCKER_IMAGE_FRONTEND`).

## Поток данных

```
Браузер
  │  (TanStack Router рендерит маршруты из frontend/src/routes/)
  ▼
frontend/src/client  ← сгенерирован из OpenAPI-схемы backend'а (openapi-ts)
  │  HTTP + Bearer JWT (access_token в localStorage)
  ▼
Traefik (только prod)  ── api.${DOMAIN} → backend, dashboard.${DOMAIN} → frontend
  ▼
FastAPI app (main.py)
  │  CORS middleware → api_router (prefix /api/v1)
  ▼
app/api/routes/*  ── зависимости из app/api/deps.py (SessionDep, CurrentUser, superuser-guard)
  ▼
app/crud.py  ── функции работы с моделями
  ▼
SQLModel ORM (app/models.py) → engine (app/core/db.py) → PostgreSQL
```

### Слой API-маршрутов

Все роутеры собираются в `app/api/main.py` под `api_router`:

- `login` — `/login/access-token` (OAuth2 password flow), `/login/test-token`,
  password recovery/reset.
- `users` — CRUD пользователей; листинг/создание/удаление чужих юзеров требуют
  суперюзера, `/users/me*` работают со своим аккаунтом, `/users/signup` —
  публичная регистрация.
- `items` — CRUD «items»; не-суперюзер видит только свои (фильтр по `owner_id`).
- `utils` — `/utils/health-check/` (используется healthcheck'ом контейнера),
  `/utils/test-email/` (суперюзер).
- `private` — **подключается только при `ENVIRONMENT == "local"`**
  (`app/api/main.py:13`); даёт незащищённое создание юзера для E2E/seed-сценариев.

### Аутентификация и авторизация

- JWT, алгоритм HS256, подпись через `settings.SECRET_KEY`
  (`app/core/security.py`). Срок жизни токена — `ACCESS_TOKEN_EXPIRE_MINUTES`
  (дефолт 8 дней).
- Пароли хешируются `pwdlib` с цепочкой хешеров **Argon2 → Bcrypt**; при логине
  старые bcrypt-хеши прозрачно апгрейдятся до Argon2
  (`verify_and_update` в `crud.authenticate`).
- Тайминг-атаки на enumeration предотвращаются: при отсутствии пользователя
  всё равно выполняется `verify_password` против `DUMMY_HASH` (`crud.py:42`).
- Авторизация — через FastAPI-зависимости: `CurrentUser` (валидный активный
  юзер) и `get_current_active_superuser` (`app/api/deps.py`).

## Внешние сервисы и интеграции

| Сервис | Назначение | Конфиг | Опционален? |
|---|---|---|---|
| **PostgreSQL** | основное хранилище | `POSTGRES_*` env → `SQLALCHEMY_DATABASE_URI` (`postgresql+psycopg`) | нет |
| **SMTP** | письма (восстановление пароля, новый аккаунт) | `SMTP_*`, `EMAILS_FROM_*`; включается, когда заданы `SMTP_HOST` + `EMAILS_FROM_EMAIL` (`settings.emails_enabled`) | да |
| **Sentry** | трекинг ошибок | `SENTRY_DSN`; init только при `ENVIRONMENT != "local"` (`main.py:14`) | да |
| **Traefik** | reverse-proxy, TLS (Let's Encrypt), роутинг | labels в `compose.yml`, сеть `traefik-public` | только prod |
| **MailCatcher** | перехват писем локально | `compose.override.yml` | dev |
| **Adminer** | инспекция БД через браузер | `compose.yml` | dev/ops |

## Граница frontend ↔ backend

Frontend **не пишет API-клиент вручную**. Backend публикует OpenAPI-схему по
`${API_V1_STR}/openapi.json`; `npm run generate-client` (openapi-ts) генерирует
`frontend/src/client/` (`sdk.gen.ts`, `types.gen.ts`, `schemas.gen.ts`). Поэтому
контракт типов между слоями single-source-of-truth = Pydantic/SQLModel-модели
backend'а. Изменил модель/маршрут → перегенерируй клиент (см.
[CONVENTIONS.md](CONVENTIONS.md)).

`custom_generate_unique_id` (`main.py:10`) формирует operation_id как
`{tag}-{name}`, чтобы методы сгенерированного клиента группировались по сервисам
(`LoginService`, `UsersService`, …).

## Жизненный цикл данных при старте

1. `prestart` ждёт healthcheck БД (`pg_isready`).
2. `backend/scripts/prestart.sh` → `backend_pre_start.py` (ретраи подключения),
   `alembic upgrade head`, `initial_data.py` → `init_db` создаёт
   `FIRST_SUPERUSER`, если его нет (`app/core/db.py`).
3. `backend` стартует только после `prestart` (`service_completed_successfully`).

## Схема БД (через SQLModel, `app/models.py`)

- **User**: `id` (UUID PK), `email` (unique), `hashed_password`, `is_active`,
  `is_superuser`, `full_name`, `created_at`. 1→N `items` с `cascade_delete`.
- **Item**: `id` (UUID PK), `title`, `description`, `created_at`,
  `owner_id` (FK → user, `ON DELETE CASCADE`).

UUID-первичные ключи (а не autoincrement int) — осознанное решение, см.
[ADR/0001-uuid-primary-keys.md](ADR/0001-uuid-primary-keys.md).
Модели разделены по ролям (`*Base`/`*Create`/`*Update`/`*Public`) — см.
[CONVENTIONS.md](CONVENTIONS.md).

## Где что искать

Навигация по репозиторию — в [CODE-MAP.md](CODE-MAP.md). Термины предметной
области — в [GLOSSARY.md](GLOSSARY.md). Локальный запуск и деплой описаны в
корневых `development.md` и `deployment.md` (этот doc их не дублирует).
