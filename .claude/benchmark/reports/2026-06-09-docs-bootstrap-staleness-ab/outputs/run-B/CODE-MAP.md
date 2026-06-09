---
owner: "@nikitaCodeSave"
last-updated: 2026-06-09
status: active
---

# Code Map

Карта репозитория для быстрой ориентации. Архитектурный обзор — в
[ARCHITECTURE.md](ARCHITECTURE.md).

## Top-level layout

```
.
├── backend/            # FastAPI API + ORM + миграции (Python, uv)
├── frontend/           # React SPA (TypeScript, Vite, bun)
├── compose.yml         # базовый Docker Compose (db, adminer, prestart, backend, frontend)
├── compose.override.yml# dev-оверрайды (порты, mailcatcher, hot-reload)
├── compose.traefik.yml # отдельный стек Traefik для прода
├── .env                # единый источник env-переменных для compose и backend
├── copier.yml / .copier# проект сгенерирован/обновляется через Copier-шаблон
├── hooks/              # хуки Copier-шаблона (не git-хуки)
├── scripts/            # репо-уровневые shell-скрипты (build/deploy/test stack)
├── development.md      # локальный запуск (canonical, не дублируется в docs/)
├── deployment.md       # прод-деплой + Traefik (canonical)
└── docs/               # ← эта документация
```

## backend/

```
backend/
├── app/
│   ├── main.py             # сборка FastAPI app, CORS, Sentry init, mount api_router
│   ├── models.py           # ВСЕ SQLModel-модели (User, Item + Create/Update/Public варианты)
│   ├── crud.py             # функции доступа к данным (create_user, authenticate, …)
│   ├── utils.py            # отправка email, генерация/проверка reset-токенов
│   ├── initial_data.py     # entrypoint сидинга первого суперюзера
│   ├── backend_pre_start.py# ждёт готовности БД перед стартом
│   ├── tests_pre_start.py  # то же для тестового прогона
│   ├── api/
│   │   ├── main.py         # агрегатор роутеров (api_router); /private только в local
│   │   ├── deps.py         # FastAPI-зависимости: SessionDep, CurrentUser, superuser-guard
│   │   └── routes/         # login.py, users.py, items.py, utils.py, private.py
│   ├── core/
│   │   ├── config.py       # Settings (pydantic-settings), читает ../.env
│   │   ├── db.py           # engine + init_db (сидинг суперюзера)
│   │   └── security.py     # JWT (HS256), хеширование паролей (Argon2/Bcrypt)
│   ├── alembic/            # окружение миграций + versions/
│   └── email-templates/    # MJML-исходники (src/) и собранный HTML (build/)
├── tests/                  # pytest: зеркалит app/ (api/routes, crud, scripts, utils)
├── scripts/                # format.sh, lint.sh, prestart.sh, test.sh, tests-start.sh
├── Dockerfile
├── pyproject.toml          # зависимости + конфиг ruff/mypy/pytest
└── alembic.ini
```

## frontend/

```
frontend/
├── src/
│   ├── main.tsx            # bootstrap: QueryClient, RouterProvider, ThemeProvider
│   ├── routes/             # файловый роутинг TanStack Router
│   │   ├── __root.tsx      # корневой layout + devtools + not-found/error
│   │   ├── _layout.tsx     # защищённый layout (sidebar) для авторизованных
│   │   ├── _layout/        # index, items, admin, settings (вложенные страницы)
│   │   ├── login.tsx, signup.tsx, recover-password.tsx, reset-password.tsx
│   │   └── routeTree.gen.ts# АВТОГЕНЕРАЦИЯ TanStack Router (не править руками)
│   ├── client/             # АВТОГЕНЕРАЦИЯ из OpenAPI (openapi-ts) — не править руками
│   │   ├── sdk.gen.ts      # *Service-классы (LoginService, UsersService, …)
│   │   ├── types.gen.ts    # TS-типы из Pydantic-моделей
│   │   ├── schemas.gen.ts
│   │   └── core/           # рантайм HTTP-клиента (request, OpenAPI, ApiError)
│   ├── components/
│   │   ├── ui/             # shadcn/ui примитивы (button, dialog, form, table, …)
│   │   ├── Admin/          # управление юзерами (таблица + Add/Edit/Delete)
│   │   ├── Items/          # CRUD items
│   │   ├── UserSettings/   # профиль, смена пароля, удаление аккаунта
│   │   ├── Sidebar/, Common/, Pending/
│   │   └── theme-provider.tsx
│   ├── hooks/              # useAuth, useCustomToast, useMobile, useCopyToClipboard
│   ├── lib/utils.ts        # cn() и пр. утилиты
│   └── utils.ts            # handleError и пр. для форм/мутаций
├── tests/                  # Playwright E2E
├── package.json            # scripts: dev, build, lint (biome), generate-client, test
└── Dockerfile
```

## Where to find X

| Нужно… | Файл / директория |
|---|---|
| Добавить/изменить таблицу или схему данных | `backend/app/models.py` (+ новая Alembic-миграция) |
| Добавить API-эндпоинт | `backend/app/api/routes/<area>.py` (+ register в `api/main.py`) |
| Логику доступа к данным | `backend/app/crud.py` |
| Правила аутентификации/авторизации | `backend/app/api/deps.py`, `backend/app/core/security.py` |
| Конфиг / env-переменные | `backend/app/core/config.py`, корневой `.env` |
| Хеширование паролей / JWT | `backend/app/core/security.py` |
| Письма (шаблоны / отправка) | `backend/app/utils.py`, `backend/app/email-templates/` |
| Сидинг первого суперюзера | `backend/app/core/db.py` (`init_db`), `initial_data.py` |
| Backend-тесты | `backend/tests/` (зеркалит `app/`) |
| UI-страницу / маршрут | `frontend/src/routes/` |
| Переиспользуемый UI-примитив | `frontend/src/components/ui/` |
| Вызов API из фронта | `frontend/src/client/` (сгенерирован — не править) |
| Состояние авторизации на фронте | `frontend/src/hooks/useAuth.ts` |
| Оркестрацию сервисов | `compose.yml` (+ `.override` dev, `.traefik` prod) |
| Локальный запуск / деплой | корневые `development.md` / `deployment.md` |

## Сгенерированные артефакты (не редактировать вручную)

- `frontend/src/client/**` — из OpenAPI-схемы backend'а (`npm run generate-client`).
- `frontend/src/routes/routeTree.gen.ts` — TanStack Router plugin.
- `backend/app/alembic/versions/*.py` — генерируются `alembic revision`, но
  правятся вручную после генерации.
