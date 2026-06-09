---
owner: "@nikitaCodeSave"
last-updated: 2026-06-09
status: active
---

# Code Map

Two stacks in one repo: `backend/` (Python/FastAPI) and `frontend/`
(TypeScript/React). Everything else at the root is infra, docs, or tooling.

## Top-level layout

| Path | Purpose | Entry point |
|---|---|---|
| `backend/` | FastAPI API, DB models, migrations, tests | `backend/app/main.py:app` |
| `frontend/` | React SPA + generated API client | `frontend/src/main.tsx` |
| `compose.yml` | Base stack (db, adminer, prestart, backend, frontend) | `docker compose watch` |
| `compose.override.yml` | Local-dev overrides (volumes, ports, local Traefik) | auto-applied locally |
| `compose.traefik.yml` | Production edge proxy (HTTPS, routing) | `docker compose -f ...` |
| `scripts/` | Repo automation (client gen, test runners) | see below |
| `hooks/`, `copier.yml`, `.copier/` | Copier template generation machinery | `copier copy ...` |
| `.github/workflows/` | CI/CD (tests, deploy, Playwright) | GitHub Actions |
| `img/` | README screenshots | — |
| `docs/` | Canonical project docs (this folder) | — |
| `.env` | All runtime config / secrets (see `backend/app/core/config.py`) | — |

## Backend (`backend/app/`)

| Path | Purpose | Entry point |
|---|---|---|
| `main.py` | FastAPI app factory, CORS, Sentry, router mount | `app` |
| `api/main.py` | Aggregates all route routers under `/api/v1` | `api_router` |
| `api/routes/` | HTTP endpoints (one file per resource) | `login.py`, `users.py`, `items.py`, `utils.py`, `private.py` |
| `api/deps.py` | DI: DB session, `get_current_user`, superuser guard | `SessionDep`, `CurrentUser` |
| `core/config.py` | Pydantic-settings `Settings` (env-driven) | `settings` |
| `core/db.py` | SQLModel engine + `init_db` (seed superuser) | `engine`, `init_db` |
| `core/security.py` | Password hashing (pwdlib) + JWT creation | `create_access_token`, `verify_password` |
| `models.py` | All SQLModel models + API schemas (User, Item, Token, …) | — |
| `crud.py` | DB operations for users & items | `create_user`, `authenticate`, … |
| `utils.py` | Email rendering/sending, reset-token helpers | — |
| `alembic/` | Migration env + versioned migrations | `alembic.ini` (in `backend/`) |
| `backend_pre_start.py` / `tests_pre_start.py` | Wait-for-DB readiness checks | run by `prestart` service |
| `initial_data.py` | Seed first superuser via `init_db` | — |
| `email-templates/` | MJML sources + built HTML for emails | — |
| `tests/` | Pytest suite (mirrors `app/` structure) | `pytest` / `scripts/test.sh` |

## Frontend (`frontend/src/`)

| Path | Purpose | Entry point |
|---|---|---|
| `main.tsx` | App bootstrap: router, React Query, theme, auth-error handler | — |
| `routes/` | File-based routes (TanStack Router) | `__root.tsx`, `_layout.tsx`, `login.tsx`, … |
| `routes/_layout/` | Authenticated pages | `index.tsx`, `admin.tsx`, `items.tsx`, `settings.tsx` |
| `routeTree.gen.ts` | Generated route tree (do not edit) | — |
| `client/` | **Generated** OpenAPI SDK (`*.gen.ts`) + core HTTP | `client/index.ts` |
| `components/` | UI: `Admin/`, `Items/`, `UserSettings/`, `Sidebar/`, `Common/`, `Pending/` | — |
| `components/ui/` | shadcn/ui primitives | — |
| `hooks/` | `useAuth`, `useCustomToast`, `useMobile`, `useCopyToClipboard` | — |
| `lib/` | Shared helpers (`utils.ts`) | — |
| `tests/` | Playwright E2E specs | `playwright.config.ts` |

## Where to find X

| Concern | Location |
|---|---|
| Add/modify an API endpoint | `backend/app/api/routes/<resource>.py` + mount in `api/main.py` |
| Add/modify a DB model or API schema | `backend/app/models.py` (then create an Alembic migration) |
| Business / DB logic | `backend/app/crud.py` |
| Auth & current-user resolution | `backend/app/api/deps.py`, `backend/app/core/security.py` |
| App / env configuration | `backend/app/core/config.py` (values from `.env`) |
| DB connection / superuser seed | `backend/app/core/db.py` |
| Regenerate the frontend API client | `scripts/generate-client.sh` (after backend schema changes) |
| Frontend auth state (login/logout/signup) | `frontend/src/hooks/useAuth.ts` |
| Frontend routing | `frontend/src/routes/` (file-based; tree is generated) |
| Email templates | `backend/app/email-templates/src/*.mjml` |
| Backend tests | `backend/tests/` (mirrors `app/`) |
| Local stack URLs/ports | `development.md` |
| Deploy procedure | `deployment.md` |

## Scripts (`scripts/`)

| Script | Purpose |
|---|---|
| `generate-client.sh` | Dump backend OpenAPI → regenerate `frontend/src/client/` |
| `test.sh` | Run backend test suite (in Docker) |
| `test-local.sh` | Run backend tests against a locally-running stack |
| `add_latest_release_date.py` | Tooling for `release-notes.md` |
