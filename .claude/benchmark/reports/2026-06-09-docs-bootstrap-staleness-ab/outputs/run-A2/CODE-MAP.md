---
owner: @nikitaCodeSave
last-updated: 2026-06-09
---

# Code Map

Top-level layout and a "where do I find X?" index. Paths are repo-relative.

## Top-level layout

```
.
├── backend/            FastAPI API, SQLModel, Alembic migrations, pytest suite
├── frontend/           React 19 SPA (Vite, TanStack), generated API client, Playwright e2e
├── compose.yml         Base Docker Compose stack (db, adminer, prestart, backend, frontend)
├── compose.override.yml   Dev overrides (live reload, exposed ports, mailcatcher)
├── compose.traefik.yml    Traefik reverse-proxy stack (TLS, routing)
├── .env                Single source of env config for the whole stack (see config.py)
├── copier.yml          Copier template variables (this repo is a project template)
├── development.md      Local dev workflow
├── deployment.md       Production deployment (Traefik, CI/CD)
└── README.md           Overview & template usage
```

## Backend (`backend/app/`)

```
app/
├── main.py              FastAPI app instance: CORS, Sentry, router mount, unique-id fn
├── models.py            ★ ALL SQLModel tables + API request/response schemas
├── crud.py              DB operations for User/Item (create_user, authenticate, update_user…)
├── utils.py             Email rendering + SMTP send, password-reset JWT generate/verify
├── initial_data.py      Entry point: seeds FIRST_SUPERUSER (calls core.db.init_db)
├── backend_pre_start.py Waits for DB to accept connections (tenacity retry)
├── tests_pre_start.py   Same wait, used before the test run
├── api/
│   ├── main.py          Aggregates all routers; mounts `private` only when local
│   ├── deps.py          ★ DI: SessionDep, CurrentUser, get_current_active_superuser
│   └── routes/
│       ├── login.py     /login/access-token, /login/test-token, password recovery/reset
│       ├── users.py     /users CRUD + /users/me + /users/signup
│       ├── items.py     /items CRUD (ownership-scoped)
│       ├── utils.py     /utils/test-email, /utils/health-check
│       └── private.py   /private/users — test-only, local env only
├── core/
│   ├── config.py        ★ Settings (Pydantic-Settings) — every env var lives here
│   ├── security.py      JWT create/decode, password hash/verify (pwdlib Argon2+bcrypt)
│   └── db.py            SQLAlchemy engine + init_db (superuser seed)
├── alembic/             Migration env + versions/ (5 migrations, see below)
└── email-templates/
    ├── src/*.mjml       Authored email templates (MJML)
    └── build/*.html     Compiled HTML rendered with Jinja2 at runtime
```

Tests: `backend/tests/` mirrors the app layout (`tests/api/routes/test_items.py`, …);
shared fixtures in `tests/conftest.py` (session-scoped `db`, module-scoped `client`,
superuser/normal-user token-header fixtures). Helpers in `tests/utils/`.

Scripts: `backend/scripts/` — `prestart.sh` (migrate + seed), `test.sh` (coverage + pytest),
`lint.sh`, `format.sh`, `tests-start.sh`.

## Frontend (`frontend/src/`)

```
src/
├── main.tsx             App entry: QueryClient, router, OpenAPI base URL + token, 401/403 handler
├── routes/              ★ TanStack Router file-based routes
│   ├── __root.tsx       Root layout + devtools + error/notfound fallbacks
│   ├── _layout.tsx      Auth-guarded shell (sidebar/header/footer); redirects to /login
│   ├── _layout/index.tsx     Dashboard home
│   ├── _layout/items.tsx     Items table + CRUD
│   ├── _layout/admin.tsx     User management (superuser)
│   ├── _layout/settings.tsx  Profile / password / appearance / delete account
│   ├── login.tsx · signup.tsx · recover-password.tsx · reset-password.tsx
│   └── routeTree.gen.ts      Generated route tree (do not edit by hand)
├── client/              ★ GENERATED API client (@hey-api/openapi-ts) — do not edit
│   ├── sdk.gen.ts       Service classes: LoginService, UsersService, ItemsService, …
│   ├── types.gen.ts     TS types mirrored from backend Pydantic models
│   ├── schemas.gen.ts   JSON schema definitions
│   └── core/            OpenAPI config, request executor, ApiError
├── hooks/
│   ├── useAuth.ts       ★ login/logout, current-user query, isLoggedIn()
│   ├── useCustomToast.ts · useCopyToClipboard.ts · useMobile.ts
├── components/
│   ├── ui/              shadcn/ui primitives (Radix + Tailwind): button, dialog, table…
│   ├── Common/          DataTable, AuthLayout, Footer, Logo, NotFound, Appearance…
│   ├── Admin/           AddUser, EditUser, DeleteUser, columns, UserActionsMenu
│   ├── Items/           AddItem, EditItem, DeleteItem, columns, ItemActionsMenu
│   ├── UserSettings/    UserInformation, ChangePassword, DeleteAccount, DeleteConfirmation
│   ├── Sidebar/         AppSidebar, Main, User
│   └── Pending/         PendingItems, PendingUsers (skeleton loaders)
├── lib/utils.ts · utils.ts   cn() helper, error handling
└── index.css            Tailwind entry
```

E2E tests: `frontend/tests/*.spec.ts` (Playwright), config in
`frontend/playwright.config.ts`; auth state reused across tests.

## Where to find X

| I want to… | Look at |
|---|---|
| Add/change a DB field | `backend/app/models.py` → then `alembic revision --autogenerate` |
| Add an API endpoint | new/existing router in `backend/app/api/routes/`, registered in `api/main.py` |
| Change who can call an endpoint | dependencies in `backend/app/api/deps.py` (`CurrentUser` / superuser) |
| Add an env var / config | `backend/app/core/config.py` (`Settings`) + `.env` |
| Change password hashing or JWT | `backend/app/core/security.py` |
| Change the superuser seed | `backend/app/core/db.py` (`init_db`) + `FIRST_SUPERUSER*` env |
| Edit a transactional email | `backend/app/email-templates/src/*.mjml` (rebuild → `build/`), `app/utils.py` |
| Regenerate the frontend API client | `frontend` → `npm run generate-client` (after OpenAPI changes) |
| Add a page / route | `frontend/src/routes/` (file-based; tree regenerates) |
| Add a UI primitive | `frontend/src/components/ui/` (shadcn/ui) |
| Find auth/token logic (FE) | `frontend/src/hooks/useAuth.ts`, `frontend/src/main.tsx` |
| Run backend tests | `backend/scripts/test.sh` (or `pytest tests/`) |
| Run e2e tests | `frontend/playwright.config.ts`, `frontend/tests/` |
| Configure the deployed stack | `compose*.yml`, `.env`, `deployment.md` |

## Database migrations (`backend/app/alembic/versions/`)

History (oldest → newest):
1. `e2412789c190` — initialize models
2. `d98dd8ec85a3` — replace integer ids with UUIDs across models
3. `9c0a54914c78` — add max_length to string/varchar columns
4. `1a31ce608336` — add cascade-delete relationships (User → Items)
5. `fe56fa70289e` — add `created_at` to User and Item

`★` marks the highest-traffic files to read first when onboarding.
