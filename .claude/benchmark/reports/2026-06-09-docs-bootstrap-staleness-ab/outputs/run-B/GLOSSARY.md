---
owner: "@nikitaCodeSave"
last-updated: 2026-06-09
status: active
---

# Glossary

Термины предметной области и проекта, встречающиеся в коде. Только то, что
неочевидно из общего бэкграунда — общеизвестные аббревиатуры (HTTP, JSON, URL)
не включены.

| Термин | Определение | Где в коде |
|---|---|---|
| **Item** | Базовая доменная сущность-«вещь», принадлежащая пользователю (`title` + `description`). В шаблоне это пример пользовательского ресурса, который заменяется реальной доменной моделью. | `app/models.py` (`Item*`), `app/api/routes/items.py` |
| **Owner** | Пользователь-владелец item'а; связь 1→N через `owner_id` (FK на `user.id`, `ON DELETE CASCADE`). Не-суперюзер видит только свои items. | `app/models.py` (`Item.owner_id`) |
| **Superuser** | Пользователь с `is_superuser=True`; имеет привилегии управления чужими аккаунтами и items, доступ к админ-эндпоинтам. Первый суперюзер сидится из `FIRST_SUPERUSER`. | `app/api/deps.py` (`get_current_active_superuser`) |
| **FIRST_SUPERUSER** | Env-переменная с email начального суперюзера; создаётся `init_db` при старте, если ещё не существует. | `app/core/config.py`, `app/core/db.py` |
| **CurrentUser** | Тип-зависимость FastAPI (`Annotated[User, Depends(get_current_user)]`), резолвящий активного юзера из Bearer-JWT. Инъектится в защищённые эндпоинты. | `app/api/deps.py` |
| **SessionDep** | Тип-зависимость, дающая на запрос SQLModel-`Session` (через `get_db`). | `app/api/deps.py` |
| **`*Base` / `*Create` / `*Update` / `*Public`** | Конвенция разделения SQLModel-моделей по роли: общие поля, входные на создание, входные на обновление, выходные в API. См. [CONVENTIONS.md](CONVENTIONS.md). | `app/models.py` |
| **access_token** | JWT (HS256), выдаётся `/login/access-token`, хранится на фронте в `localStorage`, передаётся как `Bearer`. `sub` = `user.id`. | `app/core/security.py`, `frontend/src/hooks/useAuth.ts` |
| **prestart** | Один-shot шаг/контейнер перед запуском backend'а: ждёт БД, прогоняет миграции, сидит суперюзера. | `backend/scripts/prestart.sh`, `compose.yml` |
| **generate-client** | Кодогенерация TypeScript-клиента из OpenAPI-схемы backend'а (openapi-ts). Делает типы фронта производными от Pydantic-моделей. | `frontend/package.json`, `frontend/src/client/` |
| **operation_id** | Уникальный id операции в OpenAPI; здесь переопределён как `{tag}-{name}` ради человекочитаемых имён в сгенерированном клиенте. | `app/main.py` (`custom_generate_unique_id`) |
| **emails_enabled** | Вычисляемый флаг: письма отправляются, только если заданы `SMTP_HOST` и `EMAILS_FROM_EMAIL`. | `app/core/config.py` |
| **DUMMY_HASH** | Фиксированный Argon2-хеш, используется для constant-time-проверки при отсутствии юзера — защита от timing-атак на enumeration email'ов. | `app/crud.py` |
| **private routes** | Группа эндпоинтов под `/api/v1/private`, подключаемая **только при `ENVIRONMENT=local`**; незащищённое создание юзера для тестов/seed. | `app/api/routes/private.py`, `app/api/main.py` |
| **STACK_NAME / DOMAIN** | Env-переменные деплоя: префикс имён Traefik-роутеров и базовый домен (`api.${DOMAIN}`, `dashboard.${DOMAIN}`, `adminer.${DOMAIN}`). | `compose.yml`, `.env` |
| **traefik-public** | Внешняя Docker-сеть, через которую Traefik обнаруживает сервисы по labels. | `compose.yml`, `compose.traefik.yml` |
| **Copier** | Шаблонизатор проектов: репозиторий сгенерирован из шаблона и может обновляться `copier update`. | `copier.yml`, `.copier/` |
