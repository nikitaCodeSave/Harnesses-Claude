---
owner: @nikitaCodeSave
last-updated: 2026-06-09
---

# Conventions

Patterns this codebase follows. Match them when extending — they are load-bearing
(the generated frontend client, the migration flow, and the auth model all depend on them).

## SQLModel schema layering

Every entity in `backend/app/models.py` is expressed as a family of classes rather than one:
a shared `*Base`, a `table=True` DB model, typed input models, and `*Public` output models.
See the suffix table in [GLOSSARY.md](GLOSSARY.md#model-layering-suffixes-sqlmodel).

Rules:
- **Never return a `table=True` model directly from an endpoint.** Declare
  `response_model=...Public` so secrets (e.g. `hashed_password`) can't leak.
- **Update models make fields optional** and handlers apply them with
  `model_dump(exclude_unset=True)` + `sqlmodel_update(...)` (partial update semantics).
- New string fields get an explicit `max_length` (mirrored by a migration) — the
  `9c0a54914c78` migration exists precisely to enforce this.

## API routing

- One `APIRouter` per domain file under `app/api/routes/`, with `prefix` and `tags` set on
  the router (e.g. `APIRouter(prefix="/items", tags=["items"])`). Register it in
  `app/api/main.py`.
- `tags[0]` matters: `main.py custom_generate_unique_id` derives each operation id as
  `"{tag}-{name}"`, which becomes the **method name in the generated frontend client**.
  Keep one tag per router and give handlers clear function names.
- Authorization is declarative:
  - require a logged-in user → add a `CurrentUser` parameter;
  - require admin → add `dependencies=[Depends(get_current_active_superuser)]` to the route.
  - resource ownership (non-superuser scoping) is checked in-handler against
    `current_user.id`, following the pattern in `items.py`.
- Persistence goes through `app/crud.py` for users/auth; item routes operate on `SessionDep`
  directly. Don't open ad-hoc DB sessions — depend on `SessionDep`.

## Configuration

- All configuration is centralized in `Settings` (`app/core/config.py`) and read from the
  **top-level `.env`** (not `backend/.env`). Add new config there with a type and default;
  never read `os.environ` directly in app code.
- Secrets that must not ship as defaults (`SECRET_KEY`, `POSTGRES_PASSWORD`,
  `FIRST_SUPERUSER_PASSWORD`) are validated against `"changethis"` and hard-fail outside
  `local`. Follow that pattern for any new must-set secret.

## Database migrations

- Schema changes are **model-first**: edit `models.py`, then
  `alembic revision --autogenerate -m "..."` and review the generated migration.
- Migrations are applied automatically by prestart (`alembic upgrade head`) — do **not**
  rely on `SQLModel.metadata.create_all` (it's intentionally commented out in `core/db.py`).
- IDs are UUIDs and timestamps are timezone-aware (`get_datetime_utc`); keep new tables
  consistent (UUID PK + `created_at`).

## Frontend ↔ backend client

- The API client (`frontend/src/client/*.gen.ts`) is **generated, not authored**. After any
  backend change to routes or schemas, regenerate with `npm run generate-client`. Never edit
  the `.gen.ts` files or `routeTree.gen.ts` by hand.
- Call the API only through the generated `*Service` classes wrapped in TanStack Query
  (`useQuery`/`useSuspenseQuery` for reads, `useMutation` for writes); invalidate the
  relevant `queryKey` on mutation success.
- Routes are file-based under `frontend/src/routes/`; put authenticated pages under
  `_layout/` so they inherit the auth guard.
- UI primitives come from `components/ui/` (shadcn/ui); compose feature components on top of
  them rather than restyling primitives inline. Forms use react-hook-form + Zod.

## Testing

Project testing rules live in [`.claude/rules/testing.md`](../.claude/rules/testing.md).
In this repo concretely:
- Backend tests mirror the app tree under `backend/tests/` (`tests/api/routes/test_items.py`
  next to the `items` router). Shared fixtures (DB session, `TestClient`, token headers) are
  in `tests/conftest.py`. Run with `backend/scripts/test.sh` (pytest under coverage).
- Frontend e2e specs are Playwright (`frontend/tests/*.spec.ts`).

## Code style / tooling

- **Backend:** Ruff (lint + import sort) and mypy `strict`; both exclude `alembic/`. Format
  with `backend/scripts/format.sh`, lint with `lint.sh`. Target Python 3.10.
- **Frontend:** Biome for lint/format (`frontend/biome.json`); TypeScript strict.
- Pre-commit hooks are configured (`.pre-commit-config.yaml`).

## Documentation discipline

When a change touches structure, data flow, a domain term, a new convention, config, or an
operational procedure, update the matching doc in the **same** change — see
[`.claude/rules/docs-discipline.md`](../.claude/rules/docs-discipline.md) for the
diff→document mapping. Keep edits scoped to affected sections and bump `last-updated`.
