---
owner: "@nikitaCodeSave"
last-updated: 2026-06-09
status: active
---

# Conventions

Project-specific patterns only — conventions a contributor would get *wrong* by
default. Generic style (PEP 8, formatting) is enforced by tooling (Ruff/mypy on
the backend, Biome on the frontend) and not repeated here.

## 1. The OpenAPI contract is the source of truth (do not hand-write the client)

The frontend never hand-writes API calls. The TypeScript SDK in
`frontend/src/client/` is **generated** from the backend's `openapi.json`.

- Workflow after any backend schema/route change: run `scripts/generate-client.sh`.
  It exports the schema (`app.main.app.openapi()`), writes `frontend/openapi.json`,
  runs `bun run generate-client` (hey-api), then lints.
- Treat `frontend/src/client/` and `frontend/src/routeTree.gen.ts` as generated
  artifacts — **edit the source, regenerate; never patch the output**.

## 2. Operation IDs drive client method names

`backend/app/main.py` sets `generate_unique_id_function` to return
`{tag}-{route_name}`. Consequences you must respect:

- Each router declares a single `tags=[...]` entry; the **tag becomes the client
  `Service` class** (`tags=["items"]` → `ItemsService`).
- The Python **function name becomes the client method** (after stripping the
  service prefix): `def read_items` under tag `items` → `ItemsService.readItems`.
- Renaming a route function or tag is a breaking change to the frontend client.

## 3. Model-family pattern in `models.py`

Every entity is expressed as a family of SQLModel classes, not one class:

- `*Base` — shared fields (validation lives here, e.g. `max_length`).
- `*Create` / `*Register` — API input on creation.
- `*Update` / `*UpdateMe` — API input on update (all fields optional).
- `*Public` — API response shape (`id` always present; never exposes
  `hashed_password`).
- `*Public` collection wrapper carries `data: list[...]` + `count: int`.
- The `table=True` class is the actual DB table.

Add fields to the narrowest class that needs them. Anything returned to clients
must flow through a `*Public` model — table models are never returned directly as
the response schema.

## 4. All models live in one file

`backend/app/models.py` holds **every** SQLModel definition. This is deliberate:
SQLModel must import all models before initialising relationships
(see the comment in `core/db.py` referencing template issue #28). Do not split
models per-domain without addressing that ordering constraint.

## 5. Endpoint dependencies, not inline auth

Authentication/authorization is expressed through FastAPI dependencies, never
ad-hoc checks:

- `SessionDep` for a DB session, `CurrentUser` for the authenticated user.
- Admin-only routes add `dependencies=[Depends(get_current_active_superuser)]`.
- **Ownership scoping is manual and explicit** inside handlers: non-superusers
  see/modify only rows where `owner_id == current_user.id`; superusers bypass.
  See `routes/items.py` for the canonical pattern — replicate it for new
  owned resources.

## 6. Schema changes go through Alembic — never `create_all`

`init_db` deliberately does **not** call `SQLModel.metadata.create_all`. Tables
are created and evolved only via Alembic revisions in
`backend/app/alembic/versions/`. After editing `models.py`, generate a migration
(`alembic revision --autogenerate`) — it is applied by `prestart` on boot.

## 7. Primary keys are UUIDs, timestamps are tz-aware UTC

`id` columns are `uuid.UUID` (`default_factory=uuid.uuid4`), not integers.
`created_at` uses `DateTime(timezone=True)` with a UTC `default_factory`. Follow
this for new tables.

## 8. Single shared `.env` at the repo root

There is one `.env` at the repo root, consumed by **both** the backend
(`pydantic-settings` reads `../.env` relative to `backend/`) and Docker Compose.
New settings go in `core/config.py`'s `Settings`, the root `.env`, and the
relevant compose `environment:` block. Secrets default to `changethis`, which
raises (not warns) outside `ENVIRONMENT=local`.

## 9. Frontend specifics

- Routing is **file-based** (TanStack Router); routes under `routes/_layout/`
  require authentication, top-level routes (`login`, `signup`,
  `recover-password`, `reset-password`) are public.
- The JWT lives in `localStorage` under `access_token`; a global QueryClient
  error handler clears it and redirects to `/login` on 401/403 (`main.tsx`).
- UI primitives in `components/ui/` are shadcn/ui — extend via the shadcn CLI,
  don't rewrite them by hand.
- Path alias `@/` maps to `frontend/src/`.

## Tooling commands

| Task | Command |
|---|---|
| Backend lint / format | `bash backend/scripts/lint.sh` / `format.sh` |
| Backend tests | `bash backend/scripts/test.sh` (pytest + coverage) |
| Frontend lint | `bun run --filter frontend lint` (Biome) |
| Frontend E2E | `bun run --filter frontend test` (Playwright) |
| Regenerate API client | `bash scripts/generate-client.sh` |

See also [ARCHITECTURE.md](ARCHITECTURE.md), [CODE-MAP.md](CODE-MAP.md),
[GLOSSARY.md](GLOSSARY.md), and the harness rules in
`.claude/rules/docs-discipline.md` / `.claude/rules/testing.md`.
