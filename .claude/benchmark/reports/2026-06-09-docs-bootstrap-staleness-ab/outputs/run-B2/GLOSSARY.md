---
owner: "@nikitaCodeSave"
last-updated: 2026-06-09
status: active
---

# Glossary

Термины, аббревиатуры и доменные сущности, встречающиеся в коде и конфигах этого
проекта. Первое использование нового термина в коде/доке → запись сюда (см.
`.claude/rules/docs-discipline.md`, rule #5).

## Доменные сущности

- **User** — учётная запись. Поля: `email` (unique), `hashed_password`, `is_active`,
  `is_superuser`, `full_name`. PK — UUID. См. `backend/app/models.py`.
- **Item** — пользовательская запись (title + description), принадлежит одному User
  через `owner_id` (FK с `ON DELETE CASCADE`). Демонстрационная сущность шаблона.
- **Superuser** — пользователь с `is_superuser=True`. Видит/правит чужие items, управляет
  пользователями, шлёт test-email. Проверка — `get_current_active_superuser`.
- **First superuser** — суперюзер, создаваемый при старте из
  `FIRST_SUPERUSER` / `FIRST_SUPERUSER_PASSWORD` (`core/db.py: init_db`).
- **Owner-scoping** — правило доступа: не-суперюзер работает только со своими items
  (`owner_id == current_user.id`).

## Схемы моделей (паттерн SQLModel)

Для каждой сущности — семейство классов (подробности в [CONVENTIONS.md](./CONVENTIONS.md)):

- **`*Base`** — общие поля (`UserBase`, `ItemBase`).
- **`*Create` / `*Register` / `*Update` / `*UpdateMe`** — входные схемы API.
- **`*` (table=True)** — модель-таблица БД (`User`, `Item`).
- **`*Public`** — выходная схема API (без `hashed_password`).
- **`*sPublic`** — обёртка списка: `{ data: [...], count: N }`.

## Аутентификация и безопасность

- **JWT** (JSON Web Token) — bearer-токен доступа. Алгоритм **HS256**, подпись —
  `SECRET_KEY`. Поле `sub` = UUID пользователя. См. `core/security.py`.
- **Access token** — JWT логина, TTL = `ACCESS_TOKEN_EXPIRE_MINUTES` (по умолч. 8 дней).
- **OAuth2PasswordRequestForm** — form-data логина (`username`/`password`); `username`
  здесь = email.
- **Reset-password token** — отдельный короткоживущий JWT для восстановления пароля
  (`EMAIL_RESET_TOKEN_EXPIRE_HOURS`, по умолч. 48ч).
- **pwdlib** — библиотека хеширования паролей. Сконфигурирована с **Argon2** (основной)
  + **bcrypt** (для верификации старых хешей); `verify_and_update` прозрачно
  перехеширует при логине.
- **DUMMY_HASH** — фиктивный Argon2-хеш в `crud.authenticate`; верификация против него
  при несуществующем email выравнивает время ответа (защита от timing-атаки).
- **User-enumeration защита** — эндпоинты recovery/reset и логин дают одинаковый ответ
  независимо от существования email.

## Стек и инструменты

- **SQLModel** — ORM поверх SQLAlchemy + Pydantic (модели = схемы). Основа `models.py`.
- **Pydantic / pydantic-settings** — валидация данных и загрузка конфигурации из `.env`.
- **Alembic** — миграции схемы БД (`backend/app/alembic/`).
- **Copier** — генератор проектов из шаблона. Репозиторий сам является шаблоном
  (`copier.yml`, `.copier/`, `hooks/post_gen_project.py`).
- **TanStack Router** — file-based роутинг фронтенда; `routeTree.gen.ts` — автоген.
- **TanStack Query** — управление серверным состоянием (кэш, мутации) на фронте.
- **shadcn/ui** — набор UI-компонентов поверх Radix + Tailwind (`components/ui/`).
- **Biome** — линтер/форматтер фронтенда (замена ESLint/Prettier).
- **@hey-api/openapi-ts** — генератор TypeScript-клиента из OpenAPI-схемы бэкенда.
- **uv** — менеджер зависимостей/окружения Python (`uv.lock`).
- **bun** — рантайм/менеджер пакетов фронтенда (`bun.lock`); запуск Playwright.
- **Ruff / mypy** — линтер и type-checker бэкенда.

## Инфраструктура

- **Traefik** — reverse-proxy/балансировщик, автоматический HTTPS через Let's Encrypt.
  Маршрутизация по поддоменам через docker-лейблы (`compose.yml`, `compose.traefik.yml`).
- **Let's Encrypt (`le`)** — certresolver Traefik для TLS-сертификатов.
- **Adminer** — веб-UI для PostgreSQL (поддомен `adminer.`).
- **Mailcatcher** — локальный SMTP-перехватчик писем для разработки.
- **Sentry** — мониторинг ошибок; включается при заданном `SENTRY_DSN` вне `local`.
- **prestart** — одноразовый Compose-сервис: ждёт БД, гонит миграции, сидит суперюзера
  (`backend/scripts/prestart.sh`).
- **STACK_NAME** — идентификатор стека для лейблов/имён Docker Compose.
- **DSN** (Data Source Name) — строка подключения; здесь у Sentry (`SENTRY_DSN`).

## Связанные документы
- [ARCHITECTURE.md](./ARCHITECTURE.md) · [CODE-MAP.md](./CODE-MAP.md) · [CONVENTIONS.md](./CONVENTIONS.md)
