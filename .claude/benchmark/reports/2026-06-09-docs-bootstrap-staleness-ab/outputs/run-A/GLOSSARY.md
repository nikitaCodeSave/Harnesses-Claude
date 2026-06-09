---
owner: "@nikitaCodeSave"
last-updated: 2026-06-09
status: active
---

# Glossary

Domain and project-specific terms as they appear in this codebase. Generic
framework vocabulary (React, FastAPI, JWT-in-general) is intentionally omitted —
only terms whose meaning is specific to *this* project are listed.

| Term | Meaning in this codebase | Defined / used in |
|---|---|---|
| **User** | Account entity. Has `email` (unique login), `hashed_password`, `is_active`, `is_superuser`, optional `full_name`. Owns Items. | `backend/app/models.py` (`User`) |
| **Item** | The single example business resource. Belongs to one User (`owner_id`), cascade-deleted with its owner. Replace this with real domain entities when building on the template. | `backend/app/models.py` (`Item`) |
| **Superuser** | A `User` with `is_superuser=True`. Bypasses ownership checks and can manage all users/items. Enforced by `get_current_active_superuser`. | `backend/app/api/deps.py` |
| **First superuser** | The bootstrap admin seeded on startup from `FIRST_SUPERUSER` / `FIRST_SUPERUSER_PASSWORD`. Created by `init_db` if absent. | `backend/app/core/db.py` |
| **Current user** | The authenticated `User` resolved from the request's JWT; injected via the `CurrentUser` dependency. | `backend/app/api/deps.py` |
| **Active user** | A `User` with `is_active=True`. Inactive users are rejected at login and on every authenticated request. | `backend/app/api/deps.py`, `routes/login.py` |
| **`*Base` / `*Create` / `*Update` / `*Public` / table model** | The SQLModel "model family" pattern: shared fields in `*Base`, API-input shapes in `*Create`/`*Update`, response shape in `*Public`, the `table=True` class is the DB table. | `backend/app/models.py`; see [CONVENTIONS](CONVENTIONS.md) |
| **`UserUpdateMe` / `UpdatePassword`** | Self-service schemas: a user editing their own profile / password (vs admin `UserUpdate`). | `backend/app/models.py`, `routes/users.py` |
| **Access token** | Short-string JWT (HS256) returned by `/login/access-token`, stored client-side in `localStorage` as `access_token`. Lifetime = `ACCESS_TOKEN_EXPIRE_MINUTES`. | `core/security.py`, `frontend/src/main.tsx` |
| **Password-reset token** | Separate JWT with `nbf`/`exp` claims, valid `EMAIL_RESET_TOKEN_EXPIRE_HOURS`, emailed as a link; distinct from the access token. | `backend/app/utils.py` |
| **Dummy hash** (`DUMMY_HASH`) | A fixed Argon2 hash verified against when an email is not found, so auth takes constant time regardless of user existence (timing-attack defence). | `backend/app/crud.py` |
| **Private routes** | The `/api/v1/private/*` router, registered **only** when `ENVIRONMENT=local`. Used by E2E tests to create users directly. Never exposed in staging/production. | `backend/app/api/routes/private.py`, `api/main.py` |
| **Generated client** | The TypeScript SDK in `frontend/src/client/`, produced from the backend's `openapi.json`. Hand-editing is forbidden — regenerate instead. | `frontend/openapi-ts.config.ts`, `scripts/generate-client.sh` |
| **Service (frontend)** | A generated class grouping endpoints by tag, e.g. `LoginService`, `UsersService`, `ItemsService` (`{tag}Service`). Method names come from FastAPI operation IDs. | `frontend/src/client/sdk.gen.ts` |
| **Operation ID** | `{tag}-{route_name}` string produced by `custom_generate_unique_id`; drives the generated client's method names. | `backend/app/main.py` |
| **Prestart** | The Compose service / `scripts/prestart.sh` step that waits for the DB, runs Alembic migrations, and seeds the first superuser before `backend` starts. | `compose.yml`, `backend/scripts/prestart.sh` |
| **`_layout` (route group)** | TanStack Router pathless layout wrapping all authenticated pages; redirects unauthenticated users to `/login`. | `frontend/src/routes/_layout.tsx` |
| **STACK_NAME / DOMAIN** | Deployment env vars: `DOMAIN` is the base host, `STACK_NAME` namespaces Traefik routers and the Compose stack across staging/production. | `compose.yml`, `deployment.md` |
| **`emails_enabled`** | Computed setting: `True` only when both `SMTP_HOST` and `EMAILS_FROM_EMAIL` are set. Gates all outbound email. | `backend/app/core/config.py` |

## Adding a term

Per `.claude/rules/docs-discipline.md` rule #5, the first use of a new acronym or
domain term in code, commit, or comment should be added here.
