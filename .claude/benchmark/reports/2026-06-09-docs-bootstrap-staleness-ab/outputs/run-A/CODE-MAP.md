---
owner: "@nikitaCodeSave"
last-updated: 2026-06-09
status: active
---

# Code map

Monorepo. Two deployable apps (`backend/`, `frontend/`) plus Docker Compose
orchestration and a Copier template layer at the root.

## Top-level layout

```
.
├── backend/            FastAPI + SQLModel API (Python, uv)
├── frontend/           React + TypeScript SPA (Vite, bun)
├── compose*.yml        Docker Compose: base + .override (dev) + .traefik (proxy)
├── .env                Single shared env file (read by backend AND compose)
├── scripts/            Repo-level helper scripts (client gen, test-local)
├── img/                README screenshots
├── .copier/, copier.yml, hooks/   Copier template machinery (template upstream)
├── deployment.md       Production deploy guide (Traefik, HTTPS, CI/CD)
├── development.md      Local development guide
└── release-notes.md    Changelog
```

> This repo is the **Full Stack FastAPI Template** — the `.copier/`, `copier.yml`
> and `hooks/` files exist so it can be re-used as a project generator. They are
> not part of the running application; ignore them when working on app features.

## Backend — `backend/app/`

```
app/
├── main.py             FastAPI app: CORS, Sentry, custom operation-id fn
├── models.py           ALL SQLModel tables + request/response schemas
├── crud.py             DB operations (create_user, authenticate, create_item, …)
├── utils.py            Email rendering/sending, password-reset tokens
├── initial_data.py     Seed entrypoint (calls core.db.init_db)
├── backend_pre_start.py / tests_pre_start.py   Wait-for-DB (tenacity)
├── api/
│   ├── main.py         Aggregates all routers (private only when ENVIRONMENT=local)
│   ├── deps.py         SessionDep, CurrentUser, superuser guard, JWT decode
│   └── routes/
│       ├── login.py    /login/access-token, /password-recovery, /reset-password
│       ├── users.py    /users CRUD + /users/me self-service + /signup
│       ├── items.py    /items CRUD (owner-scoped)
│       ├── utils.py    /utils/health-check, /utils/test-email
│       └── private.py  /private/users — test-only helper, local env only
├── core/
│   ├── config.py       Settings (pydantic-settings, reads ../.env)
│   ├── db.py           SQLAlchemy engine + init_db (seeds first superuser)
│   └── security.py     JWT (HS256) + password hashing (Argon2/bcrypt)
├── alembic/versions/   Migration history (5 revisions)
└── email-templates/    src/*.mjml → build/*.html
```

Tests mirror the source tree under `backend/tests/` (`api/routes/`, `crud/`,
`scripts/`, shared fixtures in `conftest.py`, factories in `tests/utils/`).

## Frontend — `frontend/src/`

```
src/
├── main.tsx            App bootstrap: Router + QueryClient + theme + auth token
├── routes/             File-based TanStack Router
│   ├── login.tsx, signup.tsx, recover-password.tsx, reset-password.tsx  (public)
│   └── _layout/        Authenticated shell: index, items, admin, settings
├── client/             GENERATED OpenAPI SDK + types — do not hand-edit
├── components/
│   ├── ui/             shadcn/ui primitives (generated)
│   ├── Admin/, Items/, UserSettings/, Sidebar/, Common/, Pending/   feature UI
│   └── theme-provider.tsx
├── hooks/              useAuth, useCustomToast, useCopyToClipboard, useMobile
├── lib/utils.ts, utils.ts   helpers (cn(), error handling)
└── routeTree.gen.ts    GENERATED route tree
```

## Where to find X

| I want to… | Look here |
|---|---|
| Add/change an API endpoint | `backend/app/api/routes/<domain>.py` (+ register in `api/main.py` if new file) |
| Add/change a DB field or schema | `backend/app/models.py`, then `alembic revision --autogenerate` |
| Change DB query logic | `backend/app/crud.py` |
| Add an env var / setting | `backend/app/core/config.py` (`Settings`), `.env`, and compose `environment:` |
| Adjust auth / JWT / password hashing | `backend/app/core/security.py`, `backend/app/api/deps.py` |
| Edit an email body | `backend/app/email-templates/src/*.mjml` (rebuild to `build/*.html`) |
| Regenerate the frontend API client | `scripts/generate-client.sh` (re-runs after backend schema changes) |
| Add a frontend page | `frontend/src/routes/` (+ `_layout/` if it requires login) |
| Add a UI primitive | `frontend/src/components/ui/` (shadcn) |
| Change login/logout/signup behaviour | `frontend/src/hooks/useAuth.ts` |
| Run / configure services | `compose.yml` (+ `compose.override.yml` for local) |
| Apply DB migrations at startup | `backend/scripts/prestart.sh` (run by the `prestart` service) |
| Read deploy steps | `deployment.md`; local setup → `development.md` |

## Conventions

Naming patterns, the generated-client contract, and the model-family pattern are
documented in [CONVENTIONS.md](CONVENTIONS.md). Architecture overview:
[ARCHITECTURE.md](ARCHITECTURE.md). Domain terms: [GLOSSARY.md](GLOSSARY.md).
