---
owner: "@nikitaCodeSave"
last-updated: 2026-06-09
status: active
---

# Conventions (project-specific divergences)

> Only patterns where this project deviates from the obvious default are listed.
> Generic style (PEP 8, idiomatic React) is enforced by tooling, not documented here.

## Frontend API client is generated, never authored

- **Default**: hand-write `fetch`/axios calls and request/response types.
- **Our choice**: the entire client in `frontend/src/client/*.gen.ts` is generated
  from the backend's OpenAPI schema by `scripts/generate-client.sh` (`@hey-api/openapi-ts`).
- **Why**: types stay in lockstep with the backend; a schema change that breaks the
  contract surfaces as a TypeScript error.
- **Enforcement**: regenerate after any change to models/routes; never edit `*.gen.ts`
  (and `routeTree.gen.ts`) by hand — edits are overwritten on the next generation.

## One layered model family per entity in a single `models.py`

- **Default**: split ORM models and API (de)serialization schemas into separate modules.
- **Our choice**: each entity defines `*Base` (shared fields) → `*Create` / `*Update`
  (input) → bare table class → `*Public` / `*sPublic` (output), all in `backend/app/models.py`.
- **Why**: SQLModel unifies ORM + Pydantic; one source of truth per field, validation
  (`min_length`, `max_length`) declared once on the base.
- **Enforcement**: add new entities by following the existing User/Item shape; the
  `*Public` type is what the API returns and what the generated client mirrors.

## UUID primary keys, not auto-increment integers

- **Default**: integer autoincrement PKs.
- **Our choice**: `uuid.UUID` PKs with `default_factory=uuid.uuid4`.
- **Why**: non-enumerable IDs, safe to expose in URLs, no cross-table collisions.
  (Migration `d98dd8ec85a3_edit_replace_id_integers...` records the switch.)
- **Enforcement**: new models use the same `id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)`.

## Schema changes go through Alembic, not `create_all`

- **Default**: `SQLModel.metadata.create_all(engine)` at startup.
- **Our choice**: tables are created/altered only by Alembic migrations; `create_all`
  is left commented in `core/db.py`. `init_db` only seeds the first superuser.
- **Why**: reproducible, versioned schema across environments.
- **Enforcement**: after editing `models.py`, generate a migration in `backend/app/alembic/versions/`;
  the `prestart` step applies migrations before the API starts.

## Readable, stable OpenAPI operation IDs

- **Default**: FastAPI's verbose auto-generated operation IDs.
- **Our choice**: `custom_generate_unique_id` → `"{tag}-{route_name}"` (`app/main.py`).
- **Why**: produces clean generated SDK method names (`LoginService.loginAccessToken`)
  and keeps them stable across regenerations.
- **Enforcement**: every route needs exactly one tag (its first tag is used); keep route
  function names meaningful.

## CRUD functions take keyword-only arguments

- **Default**: positional parameters.
- **Our choice**: every function in `crud.py` uses a bare `*` (e.g. `def create_user(*, session, user_create)`).
- **Why**: call sites are self-documenting and resistant to argument-order mistakes.
- **Enforcement**: match the existing signature style for new CRUD helpers.

## Password hashing: Argon2 primary, Bcrypt legacy, rehash-on-verify

- **Default**: a single hashing scheme.
- **Our choice**: `pwdlib.PasswordHash(Argon2Hasher(), BcryptHasher())`; `verify_password`
  returns `verify_and_update(...)` so legacy Bcrypt hashes are transparently upgraded.
- **Why**: migrate to Argon2 without forcing password resets.
- **Enforcement**: persist the updated hash when `verify_and_update` returns a new one.

## JS toolchain: Bun + Biome (not npm + ESLint/Prettier)

- **Default**: npm/yarn with ESLint + Prettier.
- **Our choice**: `bun` for install/run, `biome` for lint+format (`frontend/biome.json`).
- **Why**: single fast tool for both lint and format; Bun for speed.
- **Enforcement**: `biome check` runs in pre-commit; use `bun run ...`, not `npm run`.

## Pre-commit via `prek`, not `pre-commit`

- **Default**: the `pre-commit` tool.
- **Our choice**: `prek` (drop-in modern alternative), config in `.pre-commit-config.yaml`.
- **Why / Enforcement**: install with `uv run prek install -f`; see `development.md`.

## Backend reads `.env` from the repo root, not `backend/`

- **Default**: `.env` next to the app.
- **Our choice**: `Settings` loads `../.env` (one level above `backend/`), shared with Docker Compose.
- **Why**: one config file feeds both the app and the compose stack.
- **Enforcement**: `core/config.py` `env_file="../.env"`; keep secrets in the root `.env`.
