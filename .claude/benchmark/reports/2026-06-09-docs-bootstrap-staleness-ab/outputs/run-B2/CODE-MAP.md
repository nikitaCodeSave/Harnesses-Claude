---
owner: "@nikitaCodeSave"
last-updated: 2026-06-09
status: active
---

# Code Map

Навигация по репозиторию: top-level layout + «где найти X». Детали взаимодействия
компонентов — в [ARCHITECTURE.md](./ARCHITECTURE.md).

## Top-level

```
backend/            FastAPI-приложение (Python, uv)
frontend/           React-SPA (TypeScript, Vite, bun)
docs/               эта документация
scripts/            корневые скрипты (генерация клиента, локальные тесты)
hooks/              post_gen_project.py — Copier post-generation hook
.copier/            артефакты Copier-шаблона (update_dotenv.py, answers)
img/                скриншоты для README
compose*.yml        Docker Compose (base / override=local / traefik=prod)
copier.yml          определение Copier-шаблона (вопросы при генерации проекта)
.env                единый источник конфигурации (БД, секреты, SMTP, домен)
development.md      локальная разработка (compose, домены, .env)
deployment.md       продакшен-деплой (Traefik, секреты, CI/CD)
release-notes.md    история изменений
```

## Backend (`backend/`)

```
app/
  main.py                 FastAPI-приложение, CORS, Sentry, монтаж api_router
  api/
    main.py               сборка api_router (login/users/utils/items[/private])
    deps.py               DI: SessionDep, CurrentUser, get_current_active_superuser
    routes/
      login.py            access-token, test-token, password-recovery/reset
      users.py            CRUD пользователей, /users/me, регистрация, смена пароля
      items.py            CRUD items с owner-scoping
      utils.py            test-email, health-check
      private.py          local-only: прямое создание юзера (для e2e)
  core/
    config.py             Settings (pydantic-settings) — ВСЕ env-переменные здесь
    db.py                 engine + init_db (сидинг первого суперюзера)
    security.py           хеш паролей (pwdlib), JWT (create_access_token, ALGORITHM)
  models.py               SQLModel-модели + Pydantic-схемы (см. CONVENTIONS.md)
  crud.py                 операции с БД (create_user, authenticate, create_item, ...)
  utils.py                email-рендеринг/отправка, reset-password токены
  alembic/                миграции БД (env.py + versions/)
  initial_data.py         entrypoint сидинга (вызывает init_db)
  backend_pre_start.py    ожидание готовности БД (tenacity-ретраи)
  email-templates/        MJML-исходники + собранный HTML (build/)
tests/                    pytest: api/, crud/, utils/ + conftest.py (фикстуры)
scripts/                  prestart.sh, test.sh, lint.sh, format.sh
pyproject.toml            зависимости (uv), ruff, mypy
alembic.ini               конфиг Alembic
```

## Frontend (`frontend/`)

```
src/
  main.tsx                bootstrap: QueryClient, Router, ThemeProvider, OpenAPI.TOKEN
  routeTree.gen.ts        АВТОГЕН (TanStack Router plugin) — не править руками
  client/                 АВТОГЕН OpenAPI-клиент (@hey-api) — не править руками
    sdk.gen.ts            сервисы (LoginService, UsersService, ItemsService)
    types.gen.ts          типы из схем OpenAPI
    core/                 транспорт (request, OpenAPI, ApiError)
  routes/                 file-based роуты
    __root.tsx            корневой layout
    login/signup/...      публичные страницы (recover/reset password)
    _layout.tsx           защищённый layout (требует логина)
    _layout/              index, items, admin, settings
  components/
    ui/                   shadcn/ui примитивы
    Admin/ Items/         фичевые компоненты (таблицы, формы, диалоги)
    UserSettings/ Common/ Sidebar/ Pending/
  hooks/                  useAuth, useCustomToast, useMobile, useCopyToClipboard
  lib/utils.ts            cn() и хелперы
tests/                    Playwright e2e (login, sign-up, items, admin, ...)
openapi-ts.config.ts      конфиг генерации клиента
biome.json                линтер/форматтер
playwright.config.ts      e2e-конфиг
```

## Где найти X

| Нужно | Где |
|---|---|
| Добавить env-переменную | `backend/app/core/config.py` (`Settings`) + `.env` |
| Добавить API-эндпоинт | `backend/app/api/routes/<resource>.py` + регистрация в `api/main.py` |
| Добавить/изменить таблицу | `backend/app/models.py` → `alembic revision --autogenerate` |
| Логика хеша паролей / JWT | `backend/app/core/security.py` |
| Правила доступа (owner/superuser) | `backend/app/api/deps.py` + проверки в роутах |
| Email-шаблоны | `backend/app/email-templates/` + `backend/app/utils.py` |
| Пересобрать фронтенд-клиент | `scripts/generate-client.sh` (бэкенд должен отдавать openapi.json) |
| Добавить страницу/роут | `frontend/src/routes/` (file-based) |
| UI-компоненты | `frontend/src/components/` (фичи) / `components/ui/` (примитивы) |
| Хранение токена / логаут | `frontend/src/hooks/useAuth.ts`, `frontend/src/main.tsx` |
| Сервисы запуска контейнеров | `compose.yml` (+ `compose.override.yml` локально) |
| Сидинг первого суперюзера | `backend/app/core/db.py` (`init_db`) |

## Связанные документы
- [ARCHITECTURE.md](./ARCHITECTURE.md) · [GLOSSARY.md](./GLOSSARY.md) · [CONVENTIONS.md](./CONVENTIONS.md)
