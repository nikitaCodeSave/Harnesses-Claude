---
owner: "@nikitaCodeSave"
last-updated: 2026-06-09
status: active
---

# Glossary

Domain and project-specific terms as they appear in this codebase. Generic web
terms (REST, CORS, JWT acronym itself) are only listed where this project uses
them in a specific way.

| Term | Definition | First seen |
|---|---|---|
| **Item** | The single example owned resource: a `title` + optional `description` belonging to one user. The template's demo domain entity. | `backend/app/models.py` (`Item`) |
| **Owner** | The user who owns an Item; `Item.owner_id` FK with `ON DELETE CASCADE` so a user's items are removed with the user. | `backend/app/models.py` (`Item.owner_id`) |
| **Superuser** | A user with `is_superuser=True`; bypasses ownership checks and may manage other users. Enforced by `get_current_active_superuser`. | `backend/app/api/deps.py` |
| **First superuser** | The bootstrap admin account seeded at startup from `FIRST_SUPERUSER` / `FIRST_SUPERUSER_PASSWORD`. | `backend/app/core/db.py` (`init_db`) |
| **Current user** | The authenticated `User` resolved from the bearer JWT for a request; injected via the `CurrentUser` dependency. | `backend/app/api/deps.py` (`get_current_user`) |
| **Access token** | The JWT returned by `/login/access-token`, HS256-signed with `SECRET_KEY`, expiring after `ACCESS_TOKEN_EXPIRE_MINUTES`. Stored client-side in `localStorage`. | `backend/app/core/security.py`, `frontend/src/main.tsx` |
| **`*Base` / `*Create` / `*Update` / `*Public` model** | The layered SQLModel pattern: shared fields in `*Base`, input shapes in `*Create`/`*Update`, the table in the bare class, API output in `*Public`. See CONVENTIONS. | `backend/app/models.py` |
| **Prestart** | The one-shot step that waits for the DB, runs Alembic migrations, and seeds the superuser before the API serves traffic. | `backend/app/backend_pre_start.py`, `prestart` service in `compose.yml` |
| **Generated client** | The TypeScript SDK in `frontend/src/client/*.gen.ts`, produced from the backend OpenAPI schema — never hand-edited. | `frontend/src/client/`, `scripts/generate-client.sh` |
| **Operation ID** | The stable, readable name FastAPI assigns each route (`{tag}-{route_name}` via `custom_generate_unique_id`); becomes the generated SDK method name. | `backend/app/main.py` |
| **Private router** | Endpoints mounted **only** when `ENVIRONMENT=local` (e.g. create-user without auth) for tests/dev. | `backend/app/api/routes/private.py`, `api/main.py` |
| **Emails enabled** | Computed flag: email features are active only when both `SMTP_HOST` and `EMAILS_FROM_EMAIL` are set; otherwise they no-op. | `backend/app/core/config.py` (`emails_enabled`) |
| **Stack name** | Copier input (no spaces/periods) used as the Docker Compose project name and label prefix. | `copier.yml`, README |
| **Copier** | The template engine that turns this repo into a new project, prompting for inputs and rewriting `.env`. | `copier.yml`, `hooks/post_gen_project.py` |
| **Mailcatcher** | Local fake SMTP server (port 1025) that captures outbound email and shows it at `:1080` instead of sending. | `development.md` |
| **Adminer** | Web DB admin UI (`:8080` in local) for browsing the Postgres database. | `compose.yml`, `development.md` |
| **Traefik** | Edge reverse proxy handling HTTPS and subdomain routing (`api.${DOMAIN}`, `dashboard.${DOMAIN}`). | `compose.traefik.yml`, `deployment.md` |
