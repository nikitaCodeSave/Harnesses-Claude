# Практики из живых проектов для Harness

- **Дата**: 2026-05-09
- **Источники**:
  - `~/Загрузки/HH_parser/hh-responses/` — самый зрелый, FastAPI + React, ~30+ devlog-записей, набор skills (think → research → research-to-plan → plan-exec → spec → devlog), worktree-параллелизация
  - `~/Документы/dialog_analyzer/` — Python CLI-пайплайн, минималистичная обвязка, devlog в формате `index.json + entries/*.md`, единственный skill `/spec`
  - `~/PROJECTS/Skills/` — общая база skills (`/tdd` и др.)
- **Назначение документа**: фиксация переносимых артефактов и решений для дефолтной стартовой обвязки Harness. Не теория — концентрат конкретных схем и файлов.

> Документ дополняет, не заменяет `docs/Harnesses_gude.md`. Где Harnesses_gude — meta-уровень («что вообще существует в Claude Code»), здесь — практический уровень («что реально работает в проектах автора»).

---

## 1. Devlog — главное переносимое изобретение

### 1.1 Зачем

Devlog отвечает на вопрос **«что и зачем менялось в проекте»**, на который не отвечают:
- `git log` — фиксирует коммиты, не решения. Squash-merge схлопывает мотивацию.
- `docs/` — описывают **текущее** состояние, не путь к нему.
- `MEMORY.md` — про предпочтения автора, не про эволюцию кодовой базы.

Devlog читается человеком и LLM как хронология решений с привязкой к файлам и мотивации. **Без него каждая новая сессия Claude Code читает код «без памяти команды».**

### 1.2 Два формата — выбор для Harness

| Аспект | HH_parser (`devlog/changelog.json`) | dialog_analyzer (`logs/index.json + entries/*.md`) |
|---|---|---|
| Структура | один файл | индекс + файлы по записи |
| Запись | поле `description` 2-5 предложений | `summary` (1 строка) + детальный `.md` |
| Размер записи | ~10 строк JSON | 1 строка в индексе + 30-100 строк markdown |
| Поиск | jq по полям | jq по индексу + grep по entries |
| Удобство для LLM | весь лог за раз → большой контекст | индекс читается целиком, детали — лениво |
| Иммутабельность | не оговорена | явно: «не переписывать задним числом, только новая запись» |

**Рекомендация для Harness**: формат dialog_analyzer (индекс + entries). Причины:
1. Контекст-эффективнее: 200 записей × 1 строка = 200 строк, читаемый одним проходом.
2. Детали (entry.md) подгружаются по запросу — не тратим контекст до того, как они нужны.
3. Иммутабельность задокументирована — снижает риск, что LLM «допишет» старую запись.
4. Файлы по записи легко цитировать в research/plan документах.

### 1.3 Схема `logs/index.json` (адаптировано для Harness-шаблона)

```json
{
  "_schema": {
    "description": "Индекс devlog-записей. Детали — в entries/*.md.",
    "entry_fields": {
      "id":         "Числовой, последовательный (1, 2, 3...)",
      "date":       "ISO-дата (YYYY-MM-DD)",
      "title":      "Краткий заголовок (< 80 символов)",
      "tags":       "Тип (feature|bugfix|refactor|config|docs|security|test|cleanup) + область (опционально)",
      "scope":      "Список затронутых файлов/модулей",
      "summary":    "Что сделано (1 предложение)",
      "motivation": "Зачем — проблема или цель",
      "breaking":   "true если ломает обратную совместимость (опционально)",
      "related":    "Связанные id записей или внешние ссылки ([] если нет)",
      "entry":      "Путь к детальному файлу (entries/{id}_{slug}.md)"
    }
  },
  "entries": []
}
```

### 1.4 Шаблон entry-файла

```markdown
# {Заголовок}

**ID:** {id}
**Дата:** YYYY-MM-DD
**Теги:** {tags}

## Контекст
Почему потребовалось изменение. Первая фраза = `motivation` из index.json.

## Изменения
Что конкретно сделано. Ключевые решения и trade-offs.

## Затронутые файлы
- `path/to/file.py` — что изменилось

## Проверка
Как проверено (команды, тесты, ручная проверка, скриншот).

## Related
Ссылки на связанные записи, задачи, планы. `[]` если нет.
```

### 1.5 Когда писать запись

Из обоих проектов:

**Писать**:
- Завершена фича или CLI-команда
- Исправлен баг (поведенческий, не опечатка)
- Рефакторинг модуля (переименование, вынос, удаление дублирования)
- Изменение конфигурации, env vars, auth flow, API-эндпоинтов
- Изменение пайплайна обработки (filtering, dedup, export, prompts)
- Добавлен/изменён тест (если тест задокументировал инвариант)

**НЕ писать**:
- Опечатки, форматирование, комментарии
- Промежуточные состояния («wip»)
- Ответы на вопросы / чтение кода / research без правок
- Косметика git-истории

### 1.6 Иммутабельность (из dialog_analyzer)

> Devlog фиксирует состояние **на момент события**, не переписывается задним числом. Если поведение из старой записи изменилось — создавай **новую запись** и укажи связь в `related` (в обе стороны: old → new через update индекса, new → old в теле).
>
> Допускаются только технические правки: опечатки, несоответствие формата, битые ссылки. Суть события не редактируется.

Это правило критично — без него LLM соблазняется «обновить» старую запись.

### 1.7 Синхронизация с docs/ (из dialog_analyzer)

Если правка меняет процесс, описанный в `docs/<process>.md`:
1. Обнови соответствующий раздел спеки **в том же коммите**, что и код.
2. В шапке спеки обнови `Last updated: YYYY-MM-DD` и добавь ссылку на новый devlog в секцию `Related devlogs`.
3. Если процесс ещё не задокументирован — это допустимо, но `related` в индексе должен сохранить трассируемость (id ↔ id).

### 1.8 Перенос в Harness

В стартовом шаблоне создаём:

```
.claude/skills/devlog/SKILL.md      # навык, в т.ч. триггеры на «обнови changelog»
docs/devlog-template/index.json     # шаблон с _schema и пустым entries[]
docs/devlog-template/README.md      # пользовательская инструкция (как в dialog_analyzer)
docs/devlog-template/entries/.gitkeep
```

При `/onboard` — копировать в `logs/` корня репо проекта (не в `.claude/`, чтобы быть видимым команде).

---

## 2. Workflow: think → research → spec/research-to-plan → plan-exec → devlog

Из HH_parser. Это **дискретная цепочка из 5 skills**, каждый со своим артефактом и фазой:

```
/think [идея]                       docs/thinking/YYYY-MM-DD-<slug>.md
  │                                  обсуждение, 3+ подходов, выбор
  │
  ├─ нужны факты    → /research      docs/research/<slug>.md
  │                                   код + веб + аналоги, фактический отчёт
  │                                       │
  │                                       └→ /research-to-plan → docs/plans/PLAN-<slug>.md + PROGRESS.json
  │
  ├─ готовы к коду  → /spec          план реализации с задачами, рисками
  │                                       │
  │                                       └→ /plan-exec → итеративное выполнение между сессиями
  │                                                       └→ /devlog запись
  │
  ├─ не сейчас      → MEMORY.md (отложенная идея)
  │
  └─ не делаем      → docs/thinking/ остаётся как «почему не сделали»
```

### 2.1 Артефакты по фазам

| Skill | Папка | Метаданные/Schema |
|---|---|---|
| `/think` | `docs/thinking/` | HTML-комментарий: `type` (exploration/evaluation/ideation/decision), `status` (open/decided/deferred/rejected), `next` (следующий skill) |
| `/research` | `docs/research/` | Markdown-шаблон: Резюме, Ключевые находки (код / веб), Как работает, Зависимости (upstream/downstream/external), Паттерны, Рекомендации, Риски, Источники |
| `/research-to-plan` | `docs/plans/PLAN-*.md` + `PROGRESS.json` | Граф зависимостей, юниты параллелизации, задачи 15-45 мин с обязательными полями (Files, Depends on, Test, Done when, Pattern-source) |
| `/spec` | вывод в чат + ExitPlanMode | Альтернативный вход без research; 6 фаз (Наблюдение, Контекст, Воздействие, План, Риски, Утверждение) |
| `/plan-exec` | обновляет `PROGRESS.json` | State: status (pending/in_progress/done/blocked/failed), depends_on, started_at/completed_at, verification_results, session_notes |

### 2.2 Стоп-гейты — ключевая практика

Каждый skill использует **стоп-гейты** — точки, где LLM останавливается и ждёт подтверждения:

- `/think` Фаза 1: «Вот что я понимаю о текущем состоянии. Всё верно?»
- `/think` Фаза 3: «Какой подход исследовать глубже?»
- `/think` Фаза 4: «Какой подход углубить?»
- `/spec` Фаза 0: blocking gate — `git status` не пуст → коммит/stash перед планированием
- `/plan-exec` Фаза 2: показать план действий → дождаться подтверждения

Без стоп-гейтов LLM пишет монолитный отчёт и пропускает калибровку с пользователем. Стоп-гейты — это **архитектурный приём для diverge → converge диалога**, не косметика.

### 2.3 Перенос в Harness

В минимальный шаблон обязательно:
- `/devlog` (есть в обоих проектах)
- `/spec` (есть в обоих проектах, лёгкий вход)
- `/research` (для проектов сложнее CRUD)

Опционально (для зрелых проектов после `/onboard`):
- `/think` — диалоговое размышление со стоп-гейтами
- `/research-to-plan` — мост от research к plan-exec
- `/plan-exec` — многосессионное выполнение через PROGRESS.json

`/think` и `/plan-exec` — тяжёлые скиллы (200+ строк инструкций + references/), не нужны в стартовом шаблоне. Документировать в `docs/SKILLS-CATALOG.md` как доступные для расширения.

---

## 3. PROGRESS.json — state-файл для многосессионного выполнения

Из HH_parser `/plan-exec`. Решает проблему: между сессиями Claude Code теряет контекст плана. Решение — единственный источник правды на диске.

### 3.1 Schema

```json
{
  "plan_file": "docs/plans/PLAN-feature.md",
  "plan_title": "Название",
  "created_at": "2026-03-08T10:00:00Z",
  "updated_at": "2026-03-08T14:30:00Z",
  "total_tasks": 5,
  "completed_tasks": 2,
  "tasks": [
    {
      "id": 1,
      "title": "...",
      "status": "done|pending|in_progress|blocked|failed",
      "depends_on": [],
      "files": ["src/foo.py"],
      "verification_commands": ["pytest tests/test_foo.py -q"],
      "done_when": "Тесты проходят, foo экспортируется.",
      "started_at": "...",
      "completed_at": "...",
      "verification_results": [
        {"command": "...", "passed": true, "output": "OK"}
      ],
      "session_notes": "Что было сделано в этой сессии"
    }
  ]
}
```

### 3.2 Правила

- `status="done"` ставится **только** после успешной верификации (вся верификация-чек-лист пройдена).
- `session_notes` — обязательное поле, читается следующей сессией для восстановления контекста.
- В начале сессии — `git status`, `lint`, `tests`. Если кодовая база сломана — сначала чинить, потом план.
- На длинных планах (10+ задач) — полный тест-сьют **перед каждой новой задачей**, не только после.

### 3.3 Перенос в Harness

Не переносить как часть стартового шаблона — слишком тяжёлая абстракция для нового проекта. Документировать в `docs/SKILLS-CATALOG.md` под «опциональные скиллы для зрелых проектов».

---

## 4. Параллелизация задач через worktree-агентов

Из HH_parser `/research-to-plan/references/parallelization.md`. **Главное правило**:

> Один файл — один агент. Два агента НЕ должны менять один и тот же файл.

### 4.1 Структура юнитов

```
Unit 0: Foundation (последовательно)
  Schema/types + общие регистрации (main.py, dependencies.py, router.tsx)

Unit 1: Backend core (параллельно, 3-5 агентов)
  Infrastructure module + tests
  Service module + tests

Unit 2: API + Frontend data layer (параллельно)
  Router + tests
  Frontend types + queries

Unit 3: Frontend UI (параллельно)
  Новые страницы/компоненты

Unit 4: Финализация (последовательно)
  Integration wiring + E2E + devlog
```

### 4.2 Когда **не** параллелить

- Менее 4 задач — overhead worktree > выигрыш
- Высокая связность — все задачи зависят друг от друга
- Один слой с общим состоянием

### 4.3 Промпт для worktree-агента (контракт)

Каждый агент получает:
1. Описание задачи из плана (целиком, не пересказ)
2. Ссылку на research-документ (для контекста решений)
3. Ссылку на паттерн-образец (аналогичный модуль той же архитектурной роли)
4. Чёткий скоуп файлов (что создать, что изменить)
5. Критерий Done when
6. Команды верификации

Агент **не** должен:
- Менять файлы вне своего скоупа
- Создавать PR (это делает координатор)
- Трогать shared-файлы (они уже в Foundation)

### 4.4 Чек-лист после параллельного юнита

```
1. Все агенты завершились (TaskList → нет in_progress)
2. Мерж веток (тяжёлая первой, чтобы конфликты решались на ней)
3. После каждого мержа: lint + tests
4. После всех мержей: Read shared-файлов на дубликаты импортов/регистраций
5. Полный тест-сьют
6. Очистка worktree-веток (local + remote)
```

### 4.5 Перенос в Harness

В шаблоне — **не** прописывать как обязательную практику. Worktree-параллелизация — техника для зрелого проекта со стабильной слоистой архитектурой. Для нового проекта приоритет — линейный workflow.

В `docs/SKILLS-CATALOG.md` упомянуть как «advanced pattern» с ссылкой на этот документ.

---

## 5. Permissions — observable patterns

Из `settings.local.json` обоих проектов. Оба используют **whitelist**, не `"*"`.

### 5.1 Общие разрешения

```json
{
  "permissions": {
    "allow": [
      "Bash(git:*)",
      "Bash(gh pr:*)",
      "Bash(gh api:*)",
      "Bash(gh search:*)",
      "mcp__plugin_context7_context7__resolve-library-id",
      "mcp__plugin_context7_context7__query-docs"
    ]
  }
}
```

Эти 6 разрешений — **минимум для разработки**. context7 для актуальной документации, git/gh для PR-цикла.

### 5.2 Стек-специфичные

HH_parser (frontend):
```json
"Bash(npm install:*)",
"Bash(npx tsc:*)",
"Bash(npm test:*)",
"Bash(cd /path/to/frontend && npx tsc --noEmit 2>&1 | tail -5)"
```

dialog_analyzer (Python CLI):
```json
"Bash(dialog-analyzer:*)",
"Bash(test:*)",
"Bash(xargs:*)",
"Bash(while IFS= read -r path)",
"Bash(do)", "Bash(done)", "Bash(then)", "Bash(else)", "Bash(fi)"
```

dialog_analyzer показывает анти-паттерн: разрешать «по строительным блокам» bash приводит к взрыву правил. Лучше:
```json
"Bash(scripts/run-tests.sh)",
"Bash(scripts/check.sh)"
```
— через явные скрипты в репо.

### 5.3 Перенос в Harness

Стартовый `.claude/settings.local.json` (template):
```json
{
  "permissions": {
    "allow": [
      "Bash(git:*)",
      "Bash(gh pr:*)",
      "Bash(gh api:*)",
      "mcp__plugin_context7_context7__resolve-library-id",
      "mcp__plugin_context7_context7__query-docs",
      "Read(./**)",
      "Edit(./**)",
      "Write(./**)"
    ]
  }
}
```

Стек-специфичные правила добавлять при `/onboard`, не дефолтить.

---

## 6. Rules — выделение в .claude/rules/

Из обоих проектов. Шаблон: проектный CLAUDE.md остаётся коротким (50-150 строк) и ссылается на `.claude/rules/<topic>.md`.

### 6.1 Типичный набор rules-файлов

| Файл | Содержание |
|---|---|
| `.claude/rules/code-style.md` | Язык, async, типы, ошибки, логирование |
| `.claude/rules/development-workflow.md` | Цикл разработки, тесты, git, docker |
| `.claude/rules/llm.md` | Бэкенды, промпты, fallback chain (для AI-проектов) |
| `.claude/rules/devlog.md` | Когда и как писать в devlog |
| `.claude/rules/architecture.md` | Слои, направление зависимостей, инварианты |

### 6.2 Зачем выделять

- CLAUDE.md грузится в каждый запрос — экономия контекста.
- rules/*.md грузятся **on-demand** через `Read` (когда LLM решит, что нужны).
- Можно цитировать из skill'ов: `> Подробности — .claude/rules/code-style.md`.
- Команды видят как обычные документы.

### 6.3 Перенос в Harness

Стартовый шаблон — **не** создавать rules/, оставить пустую папку с README. Заполняется в `/onboard` под конкретный стек. В CLAUDE.md проекта — ссылка на rules/ как точка расширения.

---

## 7. Что НЕ переносить

### 7.1 Тяжёлые skills с references/

`/think`, `/plan-exec`, `/research-to-plan` имеют по 2-3 файла в `references/` и SKILL.md по 200-500 строк. Это **зрелая обвязка**, не дефолт. Помещать в `docs/SKILLS-CATALOG.md` как «опционально».

### 7.2 Permission-«строительные блоки»

Разрешения вида `Bash(do)`, `Bash(done)`, `Bash(then)` (dialog_analyzer) — анти-паттерн. Заменяем на скрипты в `scripts/` корня проекта.

### 7.3 Жёсткая многослойная архитектура

`Router → Service → Infrastructure → Domain` отлично работает в HH_parser, но это специфика FastAPI-приложения. В Harness — оставить выбор за `/onboard`.

### 7.4 Параллелизация в шаблоне

Worktree-агенты — для зрелого проекта со стабильной декомпозицией. Стартовый шаблон должен работать без них.

### 7.5 «Author = nikita» в полях

В HH_parser changelog у каждой записи `"author": "nikita"`. Для Harness-шаблона убрать поле — определяется через `git config user.name` или подставляется автоматически.

---

## 8. Конкретный план переноса в Harness (черновик)

| # | Артефакт | Источник | Назначение в Harness |
|---|---|---|---|
| 1 | `.claude/skills/devlog/SKILL.md` | HH_parser, ~80 строк | Адаптировать под формат index+entries (dialog_analyzer) |
| 2 | `docs/devlog-template/index.json` | dialog_analyzer | Пустой шаблон с `_schema` |
| 3 | `docs/devlog-template/README.md` | dialog_analyzer | Инструкция для команды |
| 4 | `docs/devlog-template/entries/.gitkeep` | — | Для git |
| 5 | `.claude/skills/spec/SKILL.md` | HH_parser, ~50 строк | Лёгкая версия без Phase Templates |
| 6 | `.claude/skills/research/SKILL.md` | HH_parser, ~50 строк | Минимальная — параллельные потоки + шаблон отчёта |
| 7 | `docs/SKILLS-CATALOG.md` | новый | Каталог всех known skills с пометкой starter/advanced |
| 8 | `docs/RULES-TEMPLATE.md` | новый | Шаблон, как наполнять `.claude/rules/` при `/onboard` |
| 9 | `.claude/settings.json` (минимум) | оба проекта | git/gh + context7 + базовый Bash |

После применения — `/onboard` будет иметь скелет: devlog работает с нулевого дня, есть spec/research для нетривиальных задач, есть точки расширения для зрелого проекта.

---

## 9. Ссылки на источники

```
~/Загрузки/HH_parser/hh-responses/
  CLAUDE.md
  ONBOARDING.md
  CLAUDE_CODE_SETUP_GUIDE.md  (если есть)
  devlog/CLAUDE.md
  devlog/changelog.json
  .claude/skills/{devlog,research,research-to-plan,plan-exec,think,spec}/
  .claude/rules/{code-style,development-workflow,llm}.md
  .claude/settings.local.json
  docs/research/
  docs/plans/
  docs/thinking/

~/Документы/dialog_analyzer/
  CLAUDE.md
  logs/index.json
  logs/README.md
  logs/entries/*.md
  .claude/rules/{devlog,code-style,architecture,llm-prompts,models,execution}.md
  .claude/skills/spec/
  .claude/settings.local.json
```

---

## 10. Дельта от расширенного исследования (2026-05-09 v2)

Первая версия документа покрывала только три проекта (HH_parser, dialog_analyzer, Skills). Дополнительный обход семи проектов из `~/PROJECTS/` (`AI_analyst_for_work/{AI_analyst_for_work,AI_analyst_migration}`, `Crypto-2025-2026`, `claude-kit`, `Max_Confluence`, `claude_agent`, `Claude-Code-Kit`) добавил несколько паттернов, которых не было в первой выборке.

### 10.1 Path-scoped rules (новый паттерн — AI_analyst_migration)

Принципиально новая практика по сравнению с rules/ из HH_parser/dialog_analyzer. В frontmatter rule-файла указывается `paths:` — правило **активируется только когда LLM работает с этими файлами**, не грузится в каждом запросе.

Пример (`.claude/rules/security-critical.md`):
```yaml
---
paths:
  - "infrastructure/safe_builtins.py"
  - "infrastructure/db_connector.py"
  - "infrastructure/llm_client.py"
  - "infrastructure/settings.py"
  - "infrastructure/user_access.py"
---

# Правило: security-critical модули

## safe_builtins.py
- Изменения требуют ADR — это sandbox для exec()
...
```

Аналогично `thinking-mode.md` ограничивает действия Claude в `docs/thinking/**`: «Код не трогаем, артефакт — документ».

**Ценность для Harness**: контекст-эффективность. Правила безопасности грузятся только при работе с критическими файлами, а не висят в общем CLAUDE.md.

**Перенос**: добавить в `RULES-TEMPLATE.md` шаблон с `paths:` frontmatter и пример path-scoped правила.

### 10.2 PreToolUse hooks для безопасности и качества (AI_analyst_migration)

Три исполняемых хука — `.claude/hooks/{guard-secrets,guard-metadata,ruff-check}.sh`, подключённых через `.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [{ "type": "command", "command": ".claude/hooks/guard-metadata.sh", "timeout": 5 }]
      },
      {
        "matcher": "Bash",
        "hooks": [{ "type": "command", "command": ".claude/hooks/guard-secrets.sh", "timeout": 10 }]
      }
    ]
  }
}
```

**guard-secrets.sh** — блокирует `git commit/push` если в staged-diff обнаружены захардкоженные `API_KEY/PASSWORD/SECRET/TOKEN/DSN` со строковыми значениями. Whitelist для `os.environ`, `placeholder`, `your-*`, тестов и docs/plans/. Парсит JSON payload через `python3` → `tool_input.command`. `exit 2` → блокирующий запрет.

**guard-metadata.sh** — soft-warning при правке `metadata.py`: «используется в 6 модулях, проверь зависимости». `exit 0` (предупреждение, не блок) — это пример **информационного хука**, не блокирующего гейта.

**ruff-check.sh** (PostToolUse, не PreToolUse) — линтит .py-файл сразу после Edit/Write. Поиск ruff в PATH или `~/.local/bin/ruff`. Не падает если ruff не установлен.

**Перенос в Harness**: эти три хука — ценный стартовый набор. Уже есть в проекте свои хуки (`block-empty-task-desc`, `denied-log` и т. д.) — добавить как опциональные в `docs/HOOKS-CATALOG.md` с готовыми скриптами.

### 10.3 TDD-тройка субагентов (AI_analyst_migration)

Принципиально новый паттерн **изоляции контекста через субагенты**. В `.claude/agents/` лежат три специализированных агента:

| Агент | Фаза TDD | Роль |
|---|---|---|
| `tdd-test-writer.md` | RED | пишет падающий тест, **не видит** будущей реализации |
| `tdd-implementer.md` | GREEN | минимальная правка, **видит только тест и код** |
| `tdd-refactorer.md` | REFACTOR | свежий контекст для объективной оценки |

Цитата из `tdd-test-writer.md`:
> Ты работаешь в ИЗОЛИРОВАННОМ контексте. У тебя НЕТ знания о будущей реализации. Это критически важно — если тест спроектирован под конкретную реализацию, он бесполезен.

Оркестрируется через skill `/implement` (`.claude/skills/implement/SKILL.md`), который шаг за шагом запускает субагенты. Fallback: для тривиальных правок допустимо single-context (RED→GREEN→REFACTOR в одном окне).

**Зачем**: решает реальную проблему «LLM проектирует тест под реализацию, которую уже планирует». Изоляция контекста — единственное архитектурно чистое решение.

**Перенос в Harness**: не дефолт (TDD — выбор проекта), но включить в `SKILLS-CATALOG.md` как pattern для проектов, где TDD обязательно.

### 10.4 Specialised review-агенты (AI_analyst_migration)

Помимо TDD-тройки в `.claude/agents/` ещё:

- **`security-auditor.md`** — checklist на 5 областей: exec()-sandboxing, credential safety, SQL injection, prompt injection, path traversal. Read-only (`tools: Read, Grep, Glob, Bash`). Запускается перед мержем.
- **`docs-sync.md`** — карта `code → docs` (таблица «Изменение в коде → Какие документы проверить»). После значимых изменений пробегается по затронутым `.py` и обновляет `architecture.md`, `configuration.md`, `setup.md`, корневой CLAUDE.md. Создаёт ADR в `docs/decisions/ADR-NNN-*.md` если изменение архитектурное.
- **`spec-reviewer.md`** — quality-gate на thinking-документы (источники утверждений, привязка к проекту, риски/альтернативы).
- **`test-engineer.md`** — отдельный агент для тестового слоя.

**Перенос в Harness**: `security-auditor` и `docs-sync` — кандидаты в стартовый набор (полезны почти везде). `spec-reviewer` — для зрелых проектов с активным `/think`.

### 10.5 ADR в `docs/decisions/` + `docs/initiatives/` (AI_analyst_migration)

Дополнительная структура поверх docs/research/, docs/thinking/, docs/plans/:

- **`docs/decisions/ADR-NNN-краткое-описание.md`** — Architecture Decision Records по классическому шаблону (Контекст / Решение / Последствия). Нумерация ADR-001..ADR-022. Связь: `related` в devlog ссылается на ADR.
- **`docs/initiatives/<name>/`** — для крупных долгоживущих программ работ (несколько месяцев). Каждая инициатива — папка с `README.md` (карта), `roadmap.md`, `open-questions.md`, `decisions-log.md`, `insights.md`. В CLAUDE.md явно указано «Сейчас активно: production-v2, sql-prompt-quality».

**Перенос в Harness**: ADR — опциональный паттерн в `RULES-TEMPLATE.md` (рекомендовать для архитектурных проектов). Initiatives — слишком тяжело для шаблона, упомянуть как «продвинутый паттерн».

### 10.6 Девлог в AI_analyst_migration — копия HH_parser-формата

`devlog/changelog.json` (221 КБ) — тот же формат что в HH_parser: монолитный JSON с `_schema` и `entries[]`. Тот же `devlog/CLAUDE.md` практически слово в слово. Это не новый паттерн — а подтверждение, что HH_parser-формат скопировался автором между проектами.

**Дополнение к разделу 1.6**: автор уже выбрал JSON-формат для своих рабочих проектов. Возможно, переосмысление в пользу `index.json + entries/*.md` (как dialog_analyzer) — это более новое решение. Стоит уточнить у пользователя предпочтение перед фиксацией шаблона Harness.

### 10.7 Stage-based workflow без skills (claude-kit)

Альтернативный паттерн HH_parser-цепочки. claude-kit использует **только commands + agents**, без skills:

```
.claude/commands/workflow-strategy.md
.claude/commands/workflow-requirements.md
.claude/commands/workflow-architecture.md
.claude/commands/retry-agent.md
```

Каждая команда вызывает соответствующий агент (product-strategist, product-manager, solution-architect). Особенность — `/retry-agent {type} "{feedback}"` для **итеративной правки артефакта по человеческому фидбеку** без потери контекста предыдущих стадий.

**Перенос в Harness**: паттерн `retry-{agent}` для feedback-loop — интересный кандидат. Не нужен в стартовом шаблоне, упомянуть в `SKILLS-CATALOG.md`.

### 10.8 Structured text logs (Crypto-2025-2026)

В `.claude/logs/` — **операционные** логи команд (отличается от devlog!). Структура:
```
.claude/logs/
  new-analysis/{TICKER}-{YYYYMMDD-HHMMSS}.log
  record-trade/{TICKER}-{YYYYMMDD-HHMMSS}.log
  tactical-change/...
```

Формат строки: `[YYYY-MM-DD HH:MM:SS] [LEVEL] Message` где LEVEL ∈ {INFO, SUCCESS, WARNING, ERROR, DATA}.

**Отличие от devlog**: devlog — высокоуровневая хронология решений (motivation/scope), text logs — операционные следы выполнения slash-команд (что делал, какие данные читал, какие ошибки получил).

**Перенос в Harness**: не дефолт (специфика проекта-«дневника торговли»). В `docs/HOOKS-CATALOG.md` упомянуть как пример: SubagentStop hook может писать сжатый трек в такой логе для последующего разбора.

### 10.9 Background skills (Max_Confluence — гипотеза)

В Max_Confluence GUIDE.md, по описанию агента, skills делятся на «фоновые» (auto-load по контексту) и «пользовательские» (explicit slash). Не подтвердил чтением исходного `GUIDE.md` — оставлю как открытый вопрос для повторного прохода.

### 10.10 Сводный список конкретных дополнений к плану переноса (раздел 8)

К исходным 9 артефактам добавляю:

| # | Артефакт | Источник | Назначение в Harness |
|---|---|---|---|
| 10 | `.claude/hooks/guard-secrets.sh` | AI_analyst_migration | PreToolUse Bash, блок коммитов с хардкодами |
| 11 | `.claude/hooks/ruff-check.sh` (или универсальный `lint-on-write.sh`) | AI_analyst_migration | PostToolUse Edit\|Write, авто-линт |
| 12 | `.claude/agents/security-auditor.md` | AI_analyst_migration | read-only audit перед мержем |
| 13 | `.claude/agents/docs-sync.md` (шаблон) | AI_analyst_migration | code → docs синхронизация |
| 14 | `RULES-TEMPLATE.md` дополнить разделом «path-scoped rules» с примером frontmatter `paths:` | AI_analyst_migration | контекст-эффективность правил |
| 15 | `docs/SKILLS-CATALOG.md` дополнить TDD-паттерном (`/implement` + 3 субагента) | AI_analyst_migration | для проектов с TDD |
| 16 | Упомянуть ADR (`docs/decisions/`) и инициативы (`docs/initiatives/`) в RULES-TEMPLATE | AI_analyst_migration | расширения для зрелых проектов |
| 17 | `docs/HOOKS-CATALOG.md` — каталог хуков с готовыми скриптами | AI_analyst_migration + текущий Harness | альтернатива «всё в settings.json» |

### 10.11 Открытые вопросы (вынести на согласование)

1. **Формат devlog**: JSON-монолит (HH_parser, AI_analyst_migration — оба «рабочих» проекта) vs `index.json + entries/*.md` (dialog_analyzer — один проект). Возможно стоит дать оба шаблона на выбор, а не выбирать заочно.
2. **Path-scoped rules**: подтверждена ли поддержка `paths:` frontmatter в актуальном Claude Code или это **самопридуманный паттерн**? Нужно сверить с research-документом `Harnesses_gude.md`.
3. **TDD-агенты в дефолтном шаблоне**: 3 субагента + skill `/implement` — это +400 строк markdown. Может быть отдельным «расширением», подключаемым через `/onboard`-вопрос «нужна ли TDD-обвязка?».
4. **Crypto-style логи vs hooks**: пересекается ли с уже существующим в Harness `.claude/hooks/denied-log.sh` (тот пишет в `.claude/memory/denied.jsonl`)? Возможно стоит унифицировать формат.

### 10.12 Расширенные ссылки на источники

```
~/PROJECTS/AI_analyst_for_work/AI_analyst_migration/
  CLAUDE.md (123 строки)
  .claude/GUIDE.md (626 строк — нужно отдельное прочтение)
  .claude/settings.json (hooks конфигурация)
  .claude/hooks/{guard-secrets,guard-metadata,ruff-check}.sh
  .claude/agents/{tdd-test-writer,tdd-implementer,tdd-refactorer,security-auditor,docs-sync,spec-reviewer,test-engineer}.md
  .claude/skills/{think,research,spec,implement,fix-issue,refactor,verify,review,parallel-execute,sync-docs,compound,oracle-patterns,pipeline-knowledge}/SKILL.md
  .claude/rules/{code-style,development-workflow,devlog,security-critical,sql-pipeline,testing,thinking-mode}.md
  .claude/plans/*.md (~70 планов с randomized slug-именами — паттерн ad-hoc планирования)
  devlog/{changelog.json,CLAUDE.md}
  docs/decisions/ADR-001..ADR-022.md
  docs/initiatives/{production-v2,sql-prompt-quality}/

~/PROJECTS/AI_analyst_for_work/AI_analyst_for_work/
  (надмножество migration: + .claude/skill-evals/ — внутренние эвалюации skills)

~/PROJECTS/Crypto-2025-2026/.claude/
  logs/{new-analysis,record-trade,tactical-change}/{TICKER}-{ts}.log
  CHEAT-SHEET.md (матрица команд по периодичности)

~/PROJECTS/claude-kit/.claude/
  commands/workflow-{strategy,requirements,architecture,retry-agent}.md
  agents/ (product-strategist, product-manager, solution-architect)
```

---

## 11. Решения по открытым вопросам (после ultrathink-сессии 2026-05-09)

Три открытых вопроса из раздела 10.11 закрыты после рассуждений с автором. Логика записана здесь, чтобы не пересматривать заново.

### 11.1 TDD-тройка субагентов — НЕ переносим

**Решение**: TDD-тройка (`tdd-test-writer` / `tdd-implementer` / `tdd-refactorer` + skill `/implement`) в Harness не входит. Не входит даже как опция в `SKILLS-CATALOG.md` — слишком велик риск, что новички возьмут её «потому что она есть».

**Обоснование**:

1. **Изоляция контекста — устаревший паттерн под Sonnet 3.5 / Opus 3**. Эти модели плохо удерживали мета-инвариант «не подсматриваю реализацию», поэтому изоляция была единственным способом получить честный test-first. Opus 4.7 (Anthropic: «devises ways to verify its own outputs before reporting back») держит эту дисциплину при явной фазовой структуре в одном контексте.

2. **Стоимость изоляции = потеря конвенций проекта**. test-writer в чистом контексте не видит `tests/conftest.py`, имеющихся моков, стиля имён, фикстур. Получается «универсально хороший тест», не похожий на тесты проекта. Передавать преамбулу в каждом спавне — медленно и дорого; не передавать — тест требует переписывания после генерации.

3. **3× round-trip + 3× контекста → отрицательный ROI**. На простой задаче «функция + тест» — три полноценных спавна вместо одного. Координация падает: при ошибке непонятно где (test-writer ошибся в спецификации, implementer не понял, refactorer переусердствовал). Точно совпадает с описанным пользователем симптомом «трудности в разработке, проблемы в росте проекта».

4. **TaskCreate/TaskUpdate уже решают проблему дискретности фаз**. Тот же RED → GREEN → REFACTOR пишется как 3 явных task в одном контексте с pass-критериями в `done_when` (тест падает → проходит → код чистый). Дисциплина та же, накладных расходов нет.

5. **Принцип harness'а** (зафиксирован в `.claude/CLAUDE.md`): «Не создавать многоступенчатый PM→Architect→Dev→QA pipeline». TDD-тройка — это microversion того же анти-паттерна.

**Что переносим взамен**: ничего отдельного. В `.claude/rules/testing.md` (см. 11.3) есть пункт «изменение поведения → тест в той же сессии». Этого достаточно — Opus 4.7 сам структурирует work как «тест → код → проверка», если в правилах сказано, что тест нужен.

**Откатывается из плана переноса (раздел 10.10)**: пункт 15.

### 11.2 Devlog format — index.json (auto) + entries/*.md (truth)

**Решение**: финальный формат для шаблона Harness:

```
logs/
  index.json                      # АВТО-ГЕНЕРИРУЕМЫЙ из frontmatter entries/*.md
  README.md                       # инструкция (как писать, как запускать rebuild)
  entries/
    0001_kebab-case-slug.md       # frontmatter (single source of truth) + body
    .gitkeep
  scripts/
    rebuild-index.py              # idempotent: парсит entries/*.md → перезаписывает index.json
```

**Почему index.json — auto-generated, а не writable**:

Главная проблема всех предыдущих итераций пользователя — **рассинхронизация index и entries**. Если оба пишутся вручную, рано или поздно расходятся (запись в index есть, файла нет; или наоборот). Решение — превратить index в **derivative**: единственный источник правды — frontmatter в entry-файле.

Это закрывает «не довёл до идеала»: пользователь не может довести что-то, что архитектурно дуальное. Делаем одностороннюю зависимость — проблема пропадает.

**Структура entry-файла**:

```markdown
---
id: 17
date: 2026-05-09
tags: [feature, devlog]
scope: [src/foo.py, tests/test_foo.py]
breaking: false
related: [12, 14]
title: "Краткое название (< 80 символов)"
summary: "Что сделано (1 предложение)"
motivation: "Зачем (1 предложение)"
---

# {title}

## Контекст
Подробно о мотивации (мотив из frontmatter — выжимка).

## Изменения
Что сделано — code blocks, примеры, trade-offs.

## Проверка
Команды / тесты / ручная проверка.

## Related
- #{id} — кратко о связи (детали уже в frontmatter `related`)
```

**Структура index.json** (генерируется):

```json
{
  "_schema": {
    "description": "Индекс devlog. ГЕНЕРИРУЕТСЯ из entries/*.md, НЕ редактировать вручную.",
    "regenerate": "python logs/scripts/rebuild-index.py",
    "entry_fields": {
      "id":         "Числовой, последовательный",
      "date":       "ISO-дата",
      "tags":       "Список",
      "scope":      "Список затронутых файлов",
      "title":      "< 80 символов",
      "summary":    "1 предложение",
      "motivation": "1 предложение",
      "breaking":   "boolean",
      "related":    "Массив id записей",
      "entry":      "Относительный путь к .md"
    }
  },
  "_generated_at": "2026-05-09T12:34:56Z",
  "entries": [
    {
      "id": 17,
      "date": "2026-05-09",
      "tags": ["feature", "devlog"],
      "scope": ["src/foo.py"],
      "title": "...",
      "summary": "...",
      "motivation": "...",
      "breaking": false,
      "related": [12, 14],
      "entry": "entries/0017_kebab-case-slug.md"
    }
  ]
}
```

**Почему `.md` для entries, а не `.json`** (запрос пользователя «index в JSON» удовлетворён, но entries — markdown):

1. LLM генерирует markdown нативно — нет escape-мучений с code blocks.
2. Frontmatter уже структурирован — `python-frontmatter` / `yaml` парсит как dict.
3. Это формат Anthropic Skills (SKILL.md с frontmatter) — на который пользователь явно ссылался.
4. Markdown-headers дают навигацию (`Контекст / Изменения / Проверка`).
5. `.json` для entries означал бы поле `body_markdown` со строкой markdown внутри — шаг назад в удобстве, обратимая декомпозиция.

Если в будущем понадобится строго-JSON entry — конвертация одной командой.

**Решения для типичных проблем index+entries**:

| Проблема | Решение |
|---|---|
| id-конфликты при параллельной работе | id = max(существующих) + 1, проверяется в `rebuild-index.py`. Альтернатива — id = ISO timestamp `2026-05-09T12-34-56`, уникален без координации (но менее читаем). По умолчанию в шаблоне — числовые. |
| Slug-разнобой | Детерминированная функция `slugify(title)`: lowercase, kebab-case, ascii-fold, max 50 символов. Реализована в `rebuild-index.py` и в skill `/devlog`. |
| Рассинхронизация | Невозможна — index — derivative. |
| Рост entries/ | После 100 записей — переезд в `entries/YYYY/{id}_*.md`. `rebuild-index.py` поддерживает рекурсивный обход. |
| Иммутабельность | Из dialog_analyzer: «devlog фиксирует состояние на момент события, не переписывается. Изменения → новая запись + related ↔». В README зафиксировать. |

**Перенос в Harness — артефакты**:

| Файл | Содержание |
|---|---|
| `.claude/skills/devlog/SKILL.md` | Триггеры + алгоритм: создать `entries/{id}_*.md` с правильным frontmatter + запустить rebuild-index.py |
| `docs/devlog-template/README.md` | Инструкция (включая правило иммутабельности) |
| `docs/devlog-template/entries/.gitkeep` | Пустая папка |
| `docs/devlog-template/scripts/rebuild-index.py` | Парсит frontmatter из всех `entries/**/*.md` → генерирует index.json |
| `docs/devlog-template/index.json` | Стартовый скелет с пустым `entries: []` (после первого `rebuild-index.py` всё равно перезапишется) |

**Откатывается из плана переноса (раздел 10.10)**: пункт 1 переформулируется (skill пишет в `.md` с frontmatter, не в JSON-массив). Добавляется новый пункт — `rebuild-index.py`.

### 11.3 TDD/BDD-обвязка — НЕТ. Замена: 1 страница `testing.md`

**Решение**: TDD-обвязка (3 субагента + `/implement` skill) и BDD-обвязка (Gherkin / Cucumber) в Harness не входят. Заменяются одной страницей `.claude/rules/testing.md` на 15-25 строк.

**Обоснование**:

1. **TDD-обвязка** обоснована к отказу в 11.1.

2. **BDD-обвязка** — переносит дисциплину спецификации в формальный язык (Gherkin). Имеет смысл когда есть product-аналитики, пишущие `Given/When/Then`-сценарии. Для dev-flow «один разработчик + LLM» — overhead на синтаксис без выигрыша. LLM не сопротивляется обычному pytest-стилю, не нуждается в принудительной формализации.

3. **Что Opus 4.7 делает БЕЗ обвязки** (наблюдаемое):
   - Сам предлагает «давайте добавим тест» при нетривиальной логике
   - Сам запускает pytest/jest и читает вывод
   - Видит регрессии в смежных модулях

4. **Что Opus 4.7 не делает БЕЗ явных правил**:
   - Test-first (обычно тест-после)
   - Не сопротивляется «тест под реализацию»
   - Может пропустить edge cases в первом проходе

5. **Минимально достаточные правила** — это 3-4 строчки в `testing.md`. Они дают тот же результат, что TDD-обвязка, без церемонии.

**Шаблон `.claude/rules/testing.md`** (рекомендуется добавить в `RULES-TEMPLATE.md`):

```markdown
# Правило: тестирование

- **Изменение поведения → тест в той же сессии.** Не «потом добавим». Тест и код — единая задача.
- **Тест должен сначала падать.** Перед тем как сказать «готово», убедись что тест пройдёт только с твоей правкой (откати → запусти → должен упасть).
- **Тесты рядом с кодом.** Не отдельная задача «написать тесты к фиче N» — это всегда часть фичи N.
- **Запуск тестов — часть задачи, не отдельный шаг.** Done when включает passing test suite.
- **Тестируй контракт, не реализацию.** Изменение реализации не должно ломать тест, если контракт стабилен.

## Что НЕ тестировать
- Чистые геттеры/сеттеры
- Тонкие обёртки над внешними API (мокать значит тестировать мок)
- LLM-ответы по содержанию (тестируй формат, не содержание — LLM недетерминирован)
```

**Перенос в Harness**: добавить этот шаблон в `RULES-TEMPLATE.md` как пример рекомендуемого `.claude/rules/testing.md`.

**Откатывается из плана переноса (раздел 10.10)**: пункт 15 (TDD-агенты) полностью.

### 11.4 Сводная таблица: финальный план переноса (после ultrathink)

| # | Артефакт | Статус |
|---|---|---|
| 1 | `.claude/skills/devlog/SKILL.md` | ✅ Переформулирован: пишет в `entries/*.md` + триггерит rebuild-index.py |
| 2 | `docs/devlog-template/index.json` | ✅ Скелет (auto-generated, в шаблоне — пустой) |
| 3 | `docs/devlog-template/README.md` | ✅ Инструкция + правило иммутабельности |
| 4 | `docs/devlog-template/entries/.gitkeep` | ✅ |
| — | `docs/devlog-template/scripts/rebuild-index.py` | ✅ НОВОЕ: idempotent indexer |
| 5 | `.claude/skills/spec/SKILL.md` (лёгкая) | ✅ Без изменений |
| 6 | `.claude/skills/research/SKILL.md` (минимальная) | ✅ Без изменений |
| 7 | `docs/SKILLS-CATALOG.md` | ✅ Без TDD-секции |
| 8 | `docs/RULES-TEMPLATE.md` | ✅ Дополнен примером `testing.md` (11.3) и path-scoped frontmatter (10.1) |
| 9 | `.claude/settings.json` (минимум) | ✅ Без изменений |
| 10 | `.claude/hooks/guard-secrets.sh` | ✅ Опционально |
| 11 | `.claude/hooks/lint-on-write.sh` (универсал, не ruff-only) | ✅ Опционально |
| 12 | `.claude/agents/security-auditor.md` | ✅ Опционально |
| 13 | `.claude/agents/docs-sync.md` (шаблон) | ✅ Опционально |
| 14 | RULES-TEMPLATE: path-scoped rules | ✅ |
| ~~15~~ | ~~TDD-тройка субагентов~~ | ❌ Отменено (11.1) |
| 16 | ADR (`docs/decisions/`) и initiatives — упоминание в RULES-TEMPLATE | ✅ |
| 17 | `docs/HOOKS-CATALOG.md` | ✅ |

### 11.5 Главный принцип, к которому пришли

> **Под Opus 4.7 минимум обвязки даёт максимум продуктивности.** Каждый дополнительный субагент / skill / hook должен оправдывать себя реальным выигрышем, а не «потому что красиво». Симптом «трудности в разработке, проблемы в росте проекта» — почти всегда признак того, что обвязка переросла полезность.

Это перекликается с уже зафиксированным в `.claude/CLAUDE.md` принципом: «Уже покрыто defaults Claude Code? → DO NOTHING». Раздел 11 — конкретное приложение этого принципа к трём вопросам.


