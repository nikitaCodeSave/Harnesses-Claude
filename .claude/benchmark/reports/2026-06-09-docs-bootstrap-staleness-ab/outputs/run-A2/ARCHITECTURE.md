---
owner: @nikitaCodeSave
last-updated: 2026-06-09
---

# Architecture

Full-stack template: a **FastAPI** + **SQLModel** + **PostgreSQL** backend exposing a
versioned JSON API, a **React 19 + TanStack** SPA frontend whose API client is
**generated from the backend's OpenAPI schema**, and a **Traefik**-fronted Docker
Compose deployment. This document describes the runtime components, how a request
flows through them, and the external services involved.

## Components

| Component | Tech | Source | Role |
|---|---|---|---|
| **API** | FastAPI 0.114+, Python ≥3.10 | `backend/app/` | REST API under `/api/v1`, OpenAPI at `/api/v1/openapi.json` |
| **ORM models** | SQLModel (SQLAlchemy + Pydantic) | `backend/app/models.py` | Single source of truth for DB tables *and* API schemas |
| **DB** | PostgreSQL 18 | `db` service (`compose.yml`) | Persistent store, volume `app-db-data` |
| **Migrations** | Alembic | `backend/app/alembic/` | Schema versioning, run by `prestart` |
| **Frontend** | React 19, Vite 7, TanStack Router/Query | `frontend/src/` | SPA dashboard, served as static build via nginx in prod |
| **API client** | `@hey-api/openapi-ts` (generated) | `frontend/src/client/` | Typed SDK regenerated from backend OpenAPI |
| **Reverse proxy** | Traefik | `compose.traefik.yml` | TLS termination, host-based routing, Let's Encrypt |
| **DB admin UI** | Adminer | `adminer` service | Browse/query Postgres |
| **Mail testing** | Mailcatcher | `compose.override.yml` (dev) | Captures outbound email locally |

### Backend internal layout

```
app/main.py            FastAPI app: CORS, Sentry init, mounts api_router at /api/v1
 └─ app/api/main.py    aggregates routers; mounts `private` only when ENVIRONMENT=local
     └─ app/api/routes/   login, users, items, utils, private  (one router per domain)
         ├─ app/api/deps.py    DI: get_db → SessionDep, get_current_user → CurrentUser,
         │                     get_current_active_superuser  (FastAPI Depends + JWT decode)
         ├─ app/crud.py        DB operations for User/Item (create_user, authenticate, …)
         ├─ app/models.py      SQLModel tables + request/response schemas
         ├─ app/core/config.py Pydantic-Settings, reads ../.env
         ├─ app/core/security.py  JWT (HS256) + password hashing (Argon2/bcrypt via pwdlib)
         ├─ app/core/db.py     engine + init_db (seeds FIRST_SUPERUSER)
         └─ app/utils.py       email rendering (Jinja2) + SMTP send, reset-token JWTs
```

Routers are thin: they handle HTTP concerns + authorization and delegate persistence to
`crud.py` (users/login) or operate on the session directly (`items.py`). Authorization is
expressed as FastAPI dependencies — `CurrentUser` for "logged in", and
`Depends(get_current_active_superuser)` (route-level) for admin-only endpoints.

## Data flow — request lifecycle

1. **Auth.** Client POSTs form-encoded credentials to `POST /api/v1/login/access-token`.
   `crud.authenticate()` looks up the user by email and verifies the password with pwdlib
   (`verify_and_update` — transparently re-hashes legacy hashes on successful login). On
   success, `security.create_access_token()` returns a **HS256 JWT** with `sub = user.id`
   and an 8-day expiry (`ACCESS_TOKEN_EXPIRE_MINUTES`).
2. **Authenticated request.** Client sends `Authorization: Bearer <jwt>`.
   `get_current_user` (in `deps.py`) decodes the JWT, loads the `User` by id, and rejects
   inactive users. Endpoints declare `CurrentUser` to require it.
3. **Authorization.** Ownership is enforced in-handler: non-superusers see/modify only rows
   where `owner_id == current_user.id` (see `items.py read_items`/`read_item`); superusers
   see all. Admin user management requires the superuser dependency.
4. **Persistence.** Handlers use the request-scoped `Session` (`SessionDep`) to query via
   SQLModel `select(...)` and commit. Responses are serialized through `*Public` models
   (`response_model=`), which omit secrets such as `hashed_password`.

### Frontend ↔ backend

- The frontend never hand-writes API calls. `frontend/src/client/` (`sdk.gen.ts`,
  `types.gen.ts`, `schemas.gen.ts`) is **generated** from the backend OpenAPI document by
  `@hey-api/openapi-ts` (config: `frontend/openapi-ts.config.ts`, run via the
  `generate-client` npm script). Backend schema change → regenerate → typed client updates.
- Base URL is `VITE_API_URL` (build-time, set to `https://api.${DOMAIN}` in prod). The
  generated client injects the bearer token from `localStorage["access_token"]`.
- Data access uses **TanStack Query** (`useQuery`/`useSuspenseQuery` for reads,
  `useMutation` for writes) wrapping the generated service methods. Routing is **TanStack
  Router** file-based (`frontend/src/routes/`); the `_layout` route guards authenticated
  pages by redirecting to `/login` when no token is present. On a 401/403 the query cache
  error handler clears the token and redirects to login.
- Auth state lives in `frontend/src/hooks/useAuth.ts`: `login` stores the token,
  `logout` removes it, and the current user is fetched via `UsersService.readUserMe`.

## Domain model

Two tables, both with `uuid` primary keys and timezone-aware `created_at` (see
`backend/app/models.py`):

- **User** — `email` (unique, indexed), `hashed_password`, `is_active`, `is_superuser`,
  `full_name`. Owns items.
- **Item** — `title`, `description`, `owner_id` → `user.id`. Deleting a user cascades to
  their items (`ondelete="CASCADE"` + `cascade_delete=True` relationship; reinforced by the
  `1a31ce608336` migration).

SQLModel classes are layered: a shared `*Base`, input models (`*Create`/`*Update`/
`*Register`), the `table=True` DB model, and `*Public` output models. See
[CONVENTIONS.md](CONVENTIONS.md#sqlmodel-schema-layering).

## External services & integrations

- **PostgreSQL** — required. Connection built from `POSTGRES_*` env into a
  `postgresql+psycopg` DSN (`config.py SQLALCHEMY_DATABASE_URI`).
- **SMTP / email** — optional. Active only when `SMTP_HOST` **and** `EMAILS_FROM_EMAIL` are
  set (`settings.emails_enabled`). Used for password-recovery and new-account emails;
  templates are MJML-authored, built to HTML under `backend/app/email-templates/build/`,
  rendered with Jinja2. Reset links carry a short-lived JWT (`EMAIL_RESET_TOKEN_EXPIRE_HOURS`,
  default 48h).
- **Sentry** — optional. Initialized in `main.py` only when `SENTRY_DSN` is set and
  `ENVIRONMENT != local`.
- **Traefik** — prod edge. Routes `api.${DOMAIN}` → backend, `dashboard.${DOMAIN}` →
  frontend, `adminer.${DOMAIN}` → Adminer; issues TLS certs via the `le` resolver.

## Configuration & startup

- All config is environment-driven via Pydantic-Settings (`config.py`), read from the
  **top-level `.env`** (one level above `backend/`). `Settings` refuses to start in
  staging/production if `SECRET_KEY`, `POSTGRES_PASSWORD`, or `FIRST_SUPERUSER_PASSWORD`
  are still `"changethis"` (warns in local).
- **Prestart** (`backend/scripts/prestart.sh`, the `prestart` compose service): waits for the
  DB (`backend_pre_start.py`, tenacity retry) → `alembic upgrade head` → `initial_data.py`
  (`init_db` seeds the `FIRST_SUPERUSER`). The `backend` service starts only after prestart
  completes successfully and the DB healthcheck passes.

## Security notes (intentional design)

- Login uses a **constant-time dummy hash** (`crud.DUMMY_HASH`) when the email is unknown,
  to resist timing-based user enumeration.
- Password recovery (`login.py recover_password`) always returns the same message whether or
  not the email exists; reset with an unknown user returns the generic "Invalid token".
- `*Public` response models guarantee `hashed_password` is never serialized.
- The `private` router (test-only user creation) is mounted **only** when
  `ENVIRONMENT=local`.

## Related docs

- [CODE-MAP.md](CODE-MAP.md) — where to find things.
- [GLOSSARY.md](GLOSSARY.md) — domain & stack terms.
- [CONVENTIONS.md](CONVENTIONS.md) — patterns to follow when extending.
- `development.md`, `deployment.md`, `backend/README.md`, `frontend/README.md` — setup & ops.
