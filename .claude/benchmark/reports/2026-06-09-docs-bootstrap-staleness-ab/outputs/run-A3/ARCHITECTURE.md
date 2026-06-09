---
owner: "@nikitaCodeSave"
last-updated: 2026-06-09
status: active
---

# Architecture

## Overview

Full-stack web application starter: a JSON REST API (FastAPI/Python) backed by
PostgreSQL, plus a single-page React/TypeScript dashboard. The two halves are
decoupled — the frontend talks to the backend only over HTTP, using a
**TypeScript client generated from the backend's OpenAPI schema** (see Data
flow). Authentication is JWT bearer-token based. Local dev and production both
run under Docker Compose with Traefik as the edge proxy.

## Components

| Component | Purpose | Tech | Source |
|---|---|---|---|
| Backend API | REST API: auth, users, items, utils | FastAPI + SQLModel + Pydantic | `backend/app/` |
| Database | Persistent store for `user` / `item` tables | PostgreSQL 18 | service `db` in `compose.yml` |
| Migrations | Schema versioning | Alembic | `backend/app/alembic/` |
| Prestart | Wait-for-DB + run migrations + seed superuser | Python script | `backend/app/backend_pre_start.py`, `initial_data.py` |
| Frontend | SPA dashboard (login, admin, items, settings) | React 18 + Vite + TS | `frontend/src/` |
| API client | Auto-generated typed SDK consumed by frontend | `@hey-api/openapi-ts` | `frontend/src/client/` (generated) |
| Edge proxy | TLS termination + subdomain routing | Traefik | `compose.traefik.yml`, `compose.override.yml` |
| DB admin UI | Browse/edit DB in dev | Adminer | service `adminer` |
| Mail (dev) | Catches outbound email locally | Mailcatcher | development.md |
| E2E tests | Browser tests of the SPA | Playwright | `frontend/tests/` |

## Data flow

### Request / auth path

```
Browser (SPA)
  │  Authorization: Bearer <JWT>
  ▼
Traefik (prod) ──► FastAPI app (app/main.py)
                     │  CORSMiddleware (all_cors_origins)
                     │  router prefix = /api/v1   (settings.API_V1_STR)
                     ▼
                   app/api/main.py  (api_router)
                     ├─ login.router    /login/...        (token issue/recover/reset)
                     ├─ users.router    /users/...        (CRUD, /me)
                     ├─ items.router    /items/...         (owner-scoped CRUD)
                     ├─ utils.router    /utils/...         (health-check, test-email)
                     └─ private.router  /private/...       (local env only)
                     ▼
                   deps.get_current_user
                     │  jwt.decode(token, SECRET_KEY, HS256)
                     │  → TokenPayload.sub = user UUID
                     │  → Session.get(User, sub); check is_active
                     ▼
                   crud.py  ──►  SQLModel Session  ──►  PostgreSQL
```

Token issue: `POST /api/v1/login/access-token` takes OAuth2 password-form
credentials, `crud.authenticate` verifies the password hash (pwdlib: Argon2
primary, Bcrypt legacy with `verify_and_update`), and returns a JWT signed with
`SECRET_KEY` (HS256), expiring after `ACCESS_TOKEN_EXPIRE_MINUTES` (default 8
days). The SPA stores it in `localStorage` under `access_token`; a 401/403
clears it and redirects to `/login` (`frontend/src/main.tsx`).

### Schema → client generation (build-time, not runtime)

```
backend app  ──►  openapi.json  ──►  @hey-api/openapi-ts  ──►  frontend/src/client/*.gen.ts
 (FastAPI)        scripts/generate-client.sh                    (types, SDK, schemas)
```

The frontend never hand-writes API calls or types — they are regenerated from
the backend schema by `scripts/generate-client.sh`. Operation IDs are made
stable/readable by `custom_generate_unique_id` in `app/main.py`
(`{tag}-{route_name}`), which is why generated SDK methods read like
`LoginService.loginAccessToken`. See `docs/CONVENTIONS.md`.

## External services

| Service | Purpose | Configured via | Failure mode |
|---|---|---|---|
| PostgreSQL | Primary datastore | `POSTGRES_*` env → `SQLALCHEMY_DATABASE_URI` | API cannot start serving data; prestart blocks until reachable |
| SMTP | Password-recovery & account emails | `SMTP_*`, `EMAILS_FROM_*` | `emails_enabled` is False → email features silently no-op |
| Sentry | Error monitoring (non-local only) | `SENTRY_DSN` | Disabled if unset or `ENVIRONMENT=local` |
| Traefik | HTTPS + subdomain routing | `compose.traefik.yml` labels | Services unreachable from outside; internal compose network still works |

## Deployment

Docker Compose for both dev and prod. Environment is selected by `ENVIRONMENT`
(`local` | `staging` | `production`) and `DOMAIN`.

| Environment | Proxy | Frontend | Backend | Extras |
|---|---|---|---|---|
| local | included Traefik (`compose.override.yml`) | Vite dev server `:5173` | `:8000` | Adminer `:8080`, Mailcatcher `:1080`, Traefik UI `:8090` |
| staging / production | external Traefik (`compose.traefik.yml`) | `dashboard.${DOMAIN}` | `api.${DOMAIN}` | Sentry, HTTPS via Let's Encrypt |

CI/CD: GitHub Actions (`.github/workflows/`) — backend tests, Docker Compose
tests, Playwright, and deploy-staging / deploy-production. Full procedure in
`deployment.md`.

## Constraints

- **Auth is stateless**: JWTs are not stored server-side and cannot be revoked
  before expiry — only the client-side `localStorage` token is cleared on logout.
- **`private` router exists only in `ENVIRONMENT=local`** (test helper to create
  users without auth); it must never be enabled in production.
- **Schema secrets are enforced at startup**: `SECRET_KEY`, `POSTGRES_PASSWORD`,
  and `FIRST_SUPERUSER_PASSWORD` set to `"changethis"` raise on non-local
  environments (`config.py` `_enforce_non_default_secrets`).
- **Frontend client is generated, not authored** — never edit `frontend/src/client/*.gen.ts` by hand.

## See also

- `docs/CODE-MAP.md` — where each concern lives in the tree.
- `docs/GLOSSARY.md` — domain terms used above.
- `docs/CONVENTIONS.md` — project-specific patterns (layered models, generated client, UUID PKs).
- `development.md` / `deployment.md` — operational how-to (not duplicated here).
