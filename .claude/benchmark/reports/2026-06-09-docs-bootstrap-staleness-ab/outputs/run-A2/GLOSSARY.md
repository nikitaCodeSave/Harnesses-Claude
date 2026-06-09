---
owner: @nikitaCodeSave
last-updated: 2026-06-09
---

# Glossary

Domain entities, roles, and stack-specific terms as they appear in this codebase.
First use of any of these in code/docs/commits should match the meaning here.

## Domain entities & roles

| Term | Meaning |
|---|---|
| **User** | Account entity (`backend/app/models.py`). UUID id, unique `email`, `hashed_password`, `is_active`, `is_superuser`, optional `full_name`, `created_at`. Owns Items. |
| **Item** | The example owned resource (`title`, optional `description`, `owner_id` → User). The demo CRUD domain; replace with your real domain when using the template. |
| **Superuser** | User with `is_superuser=True`. Can manage all users and see/modify all items. Enforced via `get_current_active_superuser`. Cannot delete itself. |
| **Active user** | User with `is_active=True`. Inactive users are rejected at auth time (`get_current_user`). |
| **First superuser** | The bootstrap admin seeded on startup from `FIRST_SUPERUSER` / `FIRST_SUPERUSER_PASSWORD` env (`core/db.py init_db`). |
| **Owner / ownership** | `Item.owner_id` ties an item to a User. Non-superusers are scoped to their own items in every items route. |

## Model layering suffixes (SQLModel)

These suffixes recur for every entity (see [CONVENTIONS.md](CONVENTIONS.md)):

| Suffix | Role | Example |
|---|---|---|
| `*Base` | Shared fields (no table) | `UserBase`, `ItemBase` |
| *(table)* | DB table, `table=True`, has id/timestamps | `User`, `Item` |
| `*Create` | API input for creation | `UserCreate`, `ItemCreate` |
| `*Update` | API input for update (fields optional) | `UserUpdate`, `ItemUpdate` |
| `*Register` | Self-signup input (subset of Create) | `UserRegister` |
| `*Public` | API output (omits secrets like `hashed_password`) | `UserPublic`, `ItemPublic` |
| `*sPublic` | Paginated list wrapper: `{ data: [...], count }` | `UsersPublic`, `ItemsPublic` |

## Auth & security terms

| Term | Meaning |
|---|---|
| **Access token** | HS256 JWT with `sub = user.id`, 8-day expiry. Returned by `/login/access-token`, sent as `Authorization: Bearer`. (`core/security.py`) |
| **Password reset token** | Separate short-lived JWT (`sub = email`, default 48h) embedded in recovery email links. (`app/utils.py`) |
| **pwdlib** | Password hashing library used here with **Argon2** (primary) + **bcrypt** (fallback). `verify_and_update` transparently rehashes old hashes on login. |
| **Dummy hash** | Constant `crud.DUMMY_HASH` verified against when an email is unknown, to defeat timing-based user enumeration. |
| **Email enumeration prevention** | Password-recovery and reset endpoints return identical responses regardless of whether the email exists. |
| **`CurrentUser`** | FastAPI dependency type (`Annotated[User, Depends(get_current_user)]`) — "must be a logged-in active user". |
| **`SessionDep`** | FastAPI dependency type for a request-scoped SQLModel `Session`. |

## Stack & tooling terms

| Term | Meaning |
|---|---|
| **SQLModel** | ORM by the FastAPI author combining SQLAlchemy (tables) + Pydantic (validation). One class can be both DB row and API schema. |
| **Pydantic-Settings** | Library backing `Settings` in `core/config.py`; loads/validates config from the top-level `.env`. |
| **Alembic** | DB migration tool. `alembic upgrade head` runs in prestart; revisions in `app/alembic/versions/`. |
| **Prestart** | Pre-boot step (`scripts/prestart.sh` / `prestart` compose service): wait-for-DB → migrate → seed superuser. |
| **OpenAPI / openapi.json** | The API's machine-readable schema (`/api/v1/openapi.json`). The frontend client is generated from it. |
| **Generated client** | `frontend/src/client/*.gen.ts` produced by `@hey-api/openapi-ts`. Never hand-edited. |
| **TanStack Router** | File-based router for the SPA (`frontend/src/routes/`). `_layout` = auth-guarded shell. |
| **TanStack Query** | Server-state library: `useQuery`/`useSuspenseQuery` (reads), `useMutation` (writes). |
| **shadcn/ui** | Copy-in component pattern (Radix primitives + Tailwind) under `frontend/src/components/ui/`. |
| **Traefik** | Reverse proxy / load balancer handling TLS + host routing in production (`compose.traefik.yml`). |
| **Adminer** | Web DB admin UI for Postgres, served at `adminer.${DOMAIN}`. |
| **Mailcatcher** | Local SMTP sink for inspecting outbound email during development. |
| **Copier** | Template engine; this repo is a project template (`copier.yml`, `.copier/`). |
| **Stack name** | `STACK_NAME` env — namespaces Traefik router/service labels for the deployed stack. |
