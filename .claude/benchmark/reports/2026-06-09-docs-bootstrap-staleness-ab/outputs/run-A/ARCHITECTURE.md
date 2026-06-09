---
owner: "@nikitaCodeSave"
last-updated: 2026-06-09
status: active
---

# Architecture

Full-stack template: FastAPI backend + React SPA frontend, PostgreSQL storage,
served behind a Traefik reverse proxy. Monorepo — `backend/` and `frontend/`
are deployed as separate Docker images but share one `.env` and one OpenAPI
contract.

## Components

| Component | Tech | Path | Responsibility |
|---|---|---|---|
| **Backend API** | FastAPI + SQLModel (Pydantic v2), Python ≥3.10 | `backend/app/` | REST API under `/api/v1`, auth, business logic, ORM |
| **Frontend SPA** | React 19 + TypeScript, Vite, TanStack Router/Query, Tailwind + shadcn/ui | `frontend/src/` | Dashboard UI; talks to backend only via the generated client |
| **Database** | PostgreSQL 18 | `compose.yml` `db` service | Persists `user` and `item` tables |
| **Migrations** | Alembic | `backend/app/alembic/` | Schema versioning; applied by `prestart` before backend boots |
| **Reverse proxy** | Traefik (external) | `compose.traefik.yml` | TLS termination (Let's Encrypt), host-based routing |
| **DB admin UI** | Adminer | `compose.yml` `adminer` service | Web DB inspection |

## Request flow

```
Browser ──▶ Traefik ──┬─▶ frontend  (dashboard.${DOMAIN})  — Nginx-served static SPA
                      └─▶ backend   (api.${DOMAIN})        — FastAPI / Uvicorn
                                         │
                                         ├─▶ PostgreSQL (SQLModel/psycopg)
                                         └─▶ SMTP (password recovery / test emails)
```

- The SPA calls the API through a **typed client generated from the backend's
  OpenAPI schema** (`frontend/src/client/`, see [CONVENTIONS](CONVENTIONS.md)).
  The browser never hand-writes fetch calls.
- All API routes are mounted under `settings.API_V1_STR` (`/api/v1`) in
  `backend/app/main.py`. Router aggregation lives in `backend/app/api/main.py`.

## Backend internal structure (`backend/app/`)

| Layer | File(s) | Role |
|---|---|---|
| App entry | `main.py` | Builds `FastAPI`, CORS, Sentry init, custom operation-id function |
| Routing | `api/main.py`, `api/routes/*.py` | One router per domain: `login`, `users`, `items`, `utils`, `private` |
| Dependencies | `api/deps.py` | `SessionDep`, `CurrentUser`, superuser guard, JWT decode |
| Models | `models.py` | SQLModel tables + Pydantic request/response schemas (single source of truth) |
| Persistence | `crud.py`, `core/db.py` | CRUD helpers + engine/`init_db` (seeds first superuser) |
| Security | `core/security.py` | JWT signing (HS256), password hashing (Argon2 + bcrypt via `pwdlib`) |
| Config | `core/config.py` | `pydantic-settings` reading repo-root `../.env` |
| Email | `utils.py`, `email-templates/` | MJML→HTML templates rendered with Jinja2, sent via `emails` |
| Startup scripts | `backend_pre_start.py`, `tests_pre_start.py`, `initial_data.py` | DB-readiness wait (tenacity) + seeding |

### Auth model

- **Login** (`POST /api/v1/login/access-token`) verifies credentials via
  `crud.authenticate` and returns a JWT. Token lifetime:
  `ACCESS_TOKEN_EXPIRE_MINUTES` (default 8 days).
- Protected routes depend on `get_current_user` (decodes JWT, loads `User`,
  rejects inactive). Admin routes additionally depend on
  `get_current_active_superuser`.
- Password reset uses a separate short-lived JWT (`EMAIL_RESET_TOKEN_EXPIRE_HOURS`,
  default 48h) emailed as a link to `FRONTEND_HOST/reset-password?token=…`.
- Security hardening present in code: constant-time auth via a dummy Argon2 hash
  when the user is missing (`crud.DUMMY_HASH`) to thwart timing attacks; identical
  responses on password-recovery to prevent email enumeration; transparent hash
  upgrade on login (`verify_and_update`).

## Data model

Two tables, owner/owned relationship with cascade delete:

- `User` (`id: UUID`, `email` unique, `hashed_password`, `is_active`,
  `is_superuser`, `full_name`, `created_at`) — `1 ─< items`.
- `Item` (`id: UUID`, `title`, `description`, `owner_id → user.id ON DELETE
  CASCADE`, `created_at`).

`models.py` defines a family per entity (`*Base` / `*Create` / `*Update` /
`*Public` / table) — see [CONVENTIONS](CONVENTIONS.md). Schema changes go through
Alembic (`backend/app/alembic/versions/`), **not** `create_all`.

## Frontend internal structure (`frontend/src/`)

| Area | Path | Role |
|---|---|---|
| Entry | `main.tsx` | Wires QueryClient, Router, theme; sets `OpenAPI.BASE`/`TOKEN` |
| Generated client | `client/` | Auto-generated SDK + types from `openapi.json` (do not hand-edit) |
| Routes | `routes/` | File-based TanStack routing; `_layout/` = authenticated shell |
| Feature components | `components/{Admin,Items,UserSettings,Sidebar,Common}/` | Domain UI |
| Primitives | `components/ui/` | shadcn/ui generated primitives |
| Hooks | `hooks/` | `useAuth` (login/signup/logout + `currentUser` query), toasts, clipboard |

Auth on the client is a JWT in `localStorage` under `access_token`. A global
QueryClient error handler clears the token and redirects to `/login` on 401/403
(`main.tsx`).

## External services

| Service | Used for | Config | Optional? |
|---|---|---|---|
| PostgreSQL | Primary datastore | `POSTGRES_*` | Required |
| SMTP server | Password-recovery & test emails | `SMTP_*`, `EMAILS_FROM_*` | Optional — features disabled if `SMTP_HOST` unset (`emails_enabled`) |
| Sentry | Error tracking | `SENTRY_DSN` | Optional; only initialised when `ENVIRONMENT != local` |
| Traefik | TLS + routing in deployment | `compose.traefik.yml`, `DOMAIN`, `STACK_NAME` | Required for prod deploy |
| Mailcatcher | Local SMTP capture | `compose.override.yml` | Local dev only |

## Deployment topology

`compose.yml` defines `db`, `adminer`, `prestart`, `backend`, `frontend`.
Boot order is enforced: `db` (healthcheck) → `prestart` (runs
`scripts/prestart.sh`: waits for DB, runs Alembic migrations, seeds first
superuser) → `backend`. Traefik labels route `api.`, `dashboard.`, `adminer.`
subdomains. See root `deployment.md` for the full production procedure and
`development.md` for local setup.

## Conventions & glossary

- Project-specific conventions (generated client, model family pattern, custom
  operation IDs): [CONVENTIONS.md](CONVENTIONS.md).
- Domain terms: [GLOSSARY.md](GLOSSARY.md).
- Where-to-find-X: [CODE-MAP.md](CODE-MAP.md).
