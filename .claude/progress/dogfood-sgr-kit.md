---
plan: .claude/plans/dogfood-sgr-kit.md
last-updated: 2026-06-10
status: in-progress
session-count: 9
---

# Прогресс: Dogfood SGR-переписи через Bootstrap + long-running build kit

## Quick state

- **Last session**: 2026-06-10 (Session 9 — внешний 3-агентный аудит F5: STANDS/CONFIRMED/CLEAN, анти-паттерн избегнут)
- **Current phase**: milestone 1 почти закрыт (5/6) — остался F6 (CLI e2e); затем D.2
- **Next entry point**: dogfood — «начни сессию по ритуалу» (F6); D.2 — 4 кандидата готовы
- **Live test status**: dogfood `./init.sh` → ORACLE GREEN (114 passed); F5 wiring подтверждён внешним аудитом
- **Open blockers**: 0

## Phase checklist

### Phase A — инфраструктура лаборатории (4/4 done)
- [x] A.1 — `~/.claude` под git + приватный remote `dot-claude`
- [x] A.2 — README `dot-claude` с «New project quick start»
- [x] A.3 — гигиена лаб-репо: devlog #77 закоммичен, ветка ff-merged в main, запушено
- [x] A.4 — devlog #78 + план + этот progress-файл

### Phase B — старт dogfood'а (5/5 done)
- [x] B.1 — пустой репозиторий SGR-переписи (`AI_analyst_for_work/AI_analyst_sgr`, git init)
- [x] B.2 — сессия 0: Bootstrap (CLAUDE.md 70 строк + settings.json, доноры read-only через deny)
- [x] B.3 — Phase 5 kit: init.sh → ORACLE GREEN, features.json (6 фич), claude-progress.md, ритуал, Evaluator-строка
- [x] B.4 — harness-journal.md + журнал-строка в ритуале (3 наблюдения session 0)
- [x] B.5 — milestone 1 в features.json + docs/ARCHITECTURE.md (инверсия «пайплайн → агент», D1/D2)

### Phase C — build-цикл (0/n, n = по features.json)

### Phase D — feedback-циклы (1/n)
- [x] D.1 — 2026-06-09, раньше плана (3 продуктовых сессии, 12 наблюдений, тревога
      оператора): 5 evidence-grounded правок bootstrap-checklist (donors-deny, domain
      oracle + negative cases, verify-контракты + preconditions, progress в .claude/ +
      devlog-слой + нумерация, периодический аудит принятых фич). dot-claude a831215,
      devlog #79. Копилка кандидатов очищена (7/7 влиты).
- [ ] D.2 — после F5/F6 или по накоплению журнала

## Sessions log

### Session 9 — 2026-06-10 (3-агентный внешний аудит F5 — central thesis validated)

**Done & measured**

| Аудитор (fresh context, refute) | Вердикт | Ключевое |
|---|---|---|
| Архитектурный рефьютер | STANDS | 4 ГРАНУЛЯРНЫХ tool (не 1 монолит); LLM владеет потоком (NextStepTools discriminator, не if-цепочка); ExecuteSqlTool re-validates (defense-in-depth); guard итераций энфорсится |
| Evidence-executor | CONFIRMED | sgr-agent-core 0.7.0 реально импортируется; 14 F5-тестов pass; mock-LLM гоняет настоящий loop (model_validate схемы, не заглушка); оракул 114 passed |
| Process-auditor | CLEAN | red→green без ослабления; scope чист; D1 в ARCHITECTURE; доноры нетронуты; долги F2/F4 закрыты; ритуал соблюдён |

**Discovered**
- **Центральный тезис переписи подтверждён внешне**: F5 НЕ воспроизвёл «1 агент + 1 tool».
  Это главный риск-критерий dogfood'а — снят независимым аудитом, не самоотчётом.
- Кросс-проверка аудиторов: архитектурный приписал validate_sql +17 к F5, процессный
  уточнил — это NFKC из F4-hardening (диапазон cf01e55..HEAD захватывал обе фичи).
  Регрессии нет; аудиторы поймали неточность друг друга — ценность 3 углов.
- F5 сам нашёл дефект upstream sgr-agent-core 0.7.0 (max_iterations не энфорсится) и
  закрыл сабклассом — D1 «upstream PyPI» выбран с открытыми глазами.

**Blockers** — (none)

**Scope changes** — (none — milestone 1: 5/6, остался F6 CLI e2e)

**Next session targets** (measurable)
- [ ] F6 `passes:true` (CLI e2e против живого Oracle+ollama; риск: structured-output qwen3)
- [ ] D.2 после F6: 4 кандидата готовы к влитию в bootstrap-checklist
- [ ] M2: ≥1 наблюдение journal

### Session 8 — 2026-06-10 (верификация F4-hardening)

**Done & measured**

| Артефакт | Метрика | Target | Hit |
|---|---|---|---|
| F4-hardening закрыт | `_normalize()` = NFKC + strip{Cf,Mn}; red→green (a270886→318eab1); 100 passed | Unicode-обход закрыт | ✅ |
| Свой прогон 5 payload'ов | fullwidth/zwsp/ZWNJ/combining/soft-hyphen — все BLOCKED | все REJECT | ✅ |
| Контроль легитимности | кириллица в литерале + plain COUNT — проходят | не over-block | ✅ |

**Discovered**
- **§8 развёрнут на саму лабораторию**: сессия 4 не доверилась МОЕЙ хэндофф-заметке
  «NFKC закрывает оба payload'а» — проверила запуском, и оказалось неверно (NFKC не
  трогает U+200B, Cf). Моя «проверенная» заметка была looks-done-ловушкой (я прогнал
  только fullwidth, про zwsp домыслил). Минимальный набор найден батареей векторов, не
  угадан → вскрылся 3-й класс (combining). **Kit-кандидат D.2 (4-й):** хэндофф-заметка
  с «проверено/fix известен» обязана быть re-verified потребляющей сессией — assertion
  ≠ execution; фиксы в Next steps формулировать как «воспроизвести → закрыть», не как
  готовое решение.
- Сессия 4 — образцовая по §5/§8: эмпирика до имплементации, батарея вместо догадки,
  guard на легитимный случай (кириллица) в том же red-коммите.

**Blockers** — (none)

**Scope changes** — (none)

**Next session targets** (measurable)
- [ ] F5 `passes:true` (решает D1, записать форму зависимости в ARCHITECTURE.md)
- [ ] F5 — внешний (лабораторный) аудит wiring агента, не self-orchestrated
- [ ] M2: ≥1 наблюдение journal

### Session 7 — 2026-06-10 (верификация F4 + независимый security-аудит)

**Done & measured**

| Артефакт | Метрика | Target | Hit |
|---|---|---|---|
| Механическая верификация F4 | 5 коммитов red→green, оракул 91 passed, devlog #5, passes=F1–F4, дерево чистое | отчёт сессии 3 правдив | ✅ |
| validate_sql тесты | 59 collected (progress говорил «55» — параметризация) | ≥корпус | ✅ |
| Lab security-рефьютер (независимый) | REFUTED: Unicode-обход денлиста (fullwidth `＿`, ZWSP), подтверждён запуском | найти обход | НАШЁЛ ❌→долг |
| Запись в dogfood | F4-hardening наверх Next steps + Audit log + journal (387f3ef) | долг в очереди | ✅ |

**Discovered**
- **§8 подтверждён на dogfood**: сессия 3 сама заказала Evaluator (по ledger) — он поймал
  критичный класс (опасные Oracle-функции), но ПРОПУСТИЛ Unicode-обход; полностью внешний
  лаб-рефьютер его нашёл. Evaluator внутри авторской сессии частично анкорится → для
  security внешний контекст строго сильнее. Kit-кандидат D.2 (3-й).
- Сессия 3 сильна по процессу: re-verify фикса 2-м прогоном поймал собственную регрессию
  (over-block), TDD без ослабления, долг F2 не забыт.

**Blockers** — (none)

**Scope changes** — (none)

**Next session targets** (measurable)
- [ ] F4-hardening закрыт (NFKC + Unicode-тесты, red→green); Unicode-payload'ы → REJECT
- [ ] F5 `passes:true` (решает D1) или явный прогресс
- [ ] M2: ≥1 наблюдение journal

### Session 6 — 2026-06-09 (D.1 — см. Phase D checklist; влитие 7 находок в bootstrap-checklist, devlog #79)

### Session 5 — 2026-06-09 (continuity-fix по сигналу оператора)

**Done & measured**

| Артефакт | Метрика | Target | Hit |
|---|---|---|---|
| Devlog dogfood'а | 3 backfill-записи (#1 bootstrap, #2 F1, #3 F2+аудит), index rebuilt | эпизодика существует | ✅ |
| Progress-файл | `claude-progress.md` → `.claude/progress/build.md` + однострочный Quick state | hook видит | ✅ |
| SessionStart-hook прогон | additionalContext = 3 devlog-заголовка + Quick state с фактами | непустой | ✅ |
| CLAUDE.md dogfood | ритуал: devlog-шаг + сквозная нумерация; карта «где живёт состояние»; 75 строк | ≤200 | ✅ |

**Discovered**
- Оператор зашёл в dogfood-репо и НЕ УВИДЕЛ continuity («нет devlog, прогресс одним
  файлом в корне, непонятно как продолжать») — при том что ритуал технически работал.
  Двойная находка: (а) **kit-кандидат #6** — kit кладёт прогресс в root-файл, невидимый
  глобальному SessionStart-hook'у, и не заводит devlog → конфликт с трёхслойной
  continuity (§6); (б) **легитимность для оператора** — kit обязан делать состояние
  видимым человеку, не только агенту (карта «где живёт состояние» в CLAUDE.md).
- **Kit-кандидат #7** (из журнала F2-сессии): поле `preconditions` у фич в ledger
  (F2 требовал поднятый Oracle — сейчас это неявно).
- Оператор подтвердил: транскрипты dogfood-сессий доступны в ~/.claude/projects/ —
  использовать в D-цикле как сырьё (mining наблюдений сверх журнала).

**Blockers**
- (none)

**Scope changes**
- (none)

**Next session targets** (measurable)
- [ ] C.3: F2-hardening закрыт + F3 `passes:true` (та же команда «по ритуалу»)
- [ ] D.1 готов к старту после F3/F4: копилка ≥7 кандидатов уже набрана

### Session 4 — 2026-06-09 (3-агентный fresh-context аудит F2)

**Done & measured**

| Артефакт | Метрика | Target | Hit |
|---|---|---|---|
| Evidence-executor | init.sh 20 passed; `pytest -m integration` 1 passed против живого ai-analyst-oracle; независимый SELECT 1 FROM dual через код проекта — OK | CONFIRMED/REFUTED | CONFIRMED ✅ |
| Process-auditor | red→green без ослабления тестов (git diff пуст по tests/), scope чистый, доноры нетронуты; 1 MED: нумерация сессий (F1 и F2 обе «session 1») | CLEAN/VIOLATIONS | CLEAN (1 MED) ✅ |
| Code-refuter | 1 HIGH (cursor.description=None → сырой TypeError мимо OracleQueryError) + 1 MED (тест не фиксирует использование пула) | REFUTED/STANDS | REFUTED ❌→учтено |
| Итог в dogfood | Audit log + F2-hardening в claude-progress (коммит c38cae5); passes:true сохранён (verify-шаги выполнены, дефект за их пределами) | долг зафиксирован | ✅ |

**Discovered**
- **Сильнейший lab-сигнал трека**: fresh-context аудит нашёл HIGH-дефект в фиче, которую
  авторская сессия довела до «все тесты зелёные, integration живой». Повтор паттерна
  devlog #62/#65 уже на dogfood: оракул ловит «работает ли», судья — «правильно ли».
  Кандидат в kit (4-й): периодический независимый аудит не только для high-stakes фич.
- Нумерация сессий в журнале — слабое место конвенции kit'а (обе фичи «session 1»);
  конвенция уточнена в dogfood Decisions. Кандидат-микроправка ритуала (5-й).

**Blockers**
- (none)

**Scope changes**
- (none)

**Next session targets** (measurable)
- [ ] C.3: F2-hardening закрыт (guard + тест пула, оба red→green), F3 `passes:true`
- [ ] M2: ≥1 наблюдение в journal за сессию
- [ ] Копилка D-цикла: ≥5 кандидатов (сейчас 5) — при 5 сессиях Phase C можно стартовать D.1

### Session 3 — 2026-06-09 (верификация dogfood-сессии 1 / F1)

**Done & measured**

| Артефакт | Метрика | Target | Hit |
|---|---|---|---|
| F1 Settings в dogfood | `passes:true`, 12 unit-тестов, TDD (red-коммит 7537eb1 → green 377f2df) | verify-шаги F1 | ✅ |
| Оракул dogfood | ORACLE GREEN, 13 passed, рабочее дерево чистое | exit 0 | ✅ |
| harness-journal | +3 наблюдения за сессию 1 (2 kit-помог, 1 kit-не-хватило) | ≥1/сессию | ✅ |
| claude-progress dogfood | Decisions пополнен (env без префикса, все 7 переменных обязательны, пустая строка = отсутствие) | handoff живой | ✅ |

**Discovered**
- Ритуал отработал как задуман: старт работы ~2 мин без уточняющих вопросов; red-коммит
  тестов до имплементации органично совместился с commit-per-feature (2 коммита на фичу).
- Артефакт прошлой сессии (.env.example) сыграл роль зафиксированного решения — сессия 1
  не переобсуждала env-нейминг. Подтверждение «файл = authoritative state».
- Новый кандидат в kit (3-й): verify-шаги фич должны нести явный контракт
  (required/default), иначе каждая сессия делает молчаливые микрорешения. → копилка D-цикла.

**Blockers**
- (none)

**Scope changes**
- (none)

**Next session targets** (measurable)
- [ ] C.2: F2 Oracle connector — `passes:true` (unit с mock + integration `SELECT 1 FROM dual`)
- [ ] Dev-стек поднят: docker Oracle XE отвечает, `.env` заполнен
- [ ] M2: ≥1 наблюдение в journal за сессию

### Session 2 — 2026-06-09

**Done & measured**

| Артефакт | Метрика | Target | Hit |
|---|---|---|---|
| Dogfood-репо `AI_analyst_sgr` | 2 коммита session 0 | ≥1 commit | ✅ |
| CLAUDE.md dogfood'а | 70 строк | ≤200 | ✅ |
| Оракул `./init.sh` | exit 0, «ORACLE GREEN», 1 test passed | exit 0 | ✅ |
| `features.json` | валидный JSON, 6 фич `passes:false` | ≥1 фича | ✅ |
| `harness-journal.md` | 3 наблюдения session 0 (1 kit-помог, 2 kit-не-хватило) | ≥1/сессию | ✅ |
| Phase 7 verify | `claude --print` в репо корректно отвечает по CLAUDE.md | загрузка подтверждена | ✅ |

**Discovered**
- Разведка доноров (3 параллельных Explore): оригинал = 8-шаговый пайплайн с зашитыми
  LLM-вызовами; провал _sgr = весь пайплайн за одним MCP-tool `analyst_ask` при
  агенте-проводнике. Целевая архитектура — инверсия: reasoning-части пайплайна
  становятся reasoning'ом SGR-агента, детерминированные — гранулярными tools.
- Кандидаты в bootstrap-checklist уже из session 0 (см. harness-journal): (а) deny-паттерн
  для read-only доноров при rewrite-проектах; (б) domain-оракул (golden questions) для
  не-web продуктов — Phase 5 упоминает только browser-automation.

**Blockers**
- (none)

**Scope changes**
- B.5 выполнен внутри session 0 (features.json + ARCHITECTURE.md), отдельная
  Plan-сессия не понадобилась — milestone 1 определился из донорской разведки.

**Next session targets** (measurable)
- [ ] C.1: фича F1 (Settings) в dogfood-репо — её verify-шаги пройдены, `passes:true`, commit
- [ ] M2: ≥1 наблюдение в harness-journal.md за сессию
- [ ] Для F2+: dev-стек поднят (`dev/run-dev.sh` донора), `SELECT 1 FROM dual` проходит

### Session 1 — 2026-06-09

**Done & measured**

| Артефакт | Метрика | Target | Hit |
|---|---|---|---|
| Репо `dot-claude` (приватный) | 28 файлов tracked, 0 runtime/secrets | curated-only | ✅ |
| Секрет-скан куратированного набора | 0 реальных совпадений | 0 | ✅ |
| Лаб main | ff-merge + push (68 коммитов на origin) | main == ветка | ✅ |
| devlog | #78 записан, index = 78 entries | rebuild exit 0 | ✅ |

**Discovered**
- Slugify devlog-скрипта выбрасывает кириллицу целиком — заголовки entries надо
  строить так, чтобы латинских токенов хватало для осмысленного slug'а.
- В корне лаб-репо лежат непонятные `files.zip` и `.scratch/` — не мои, не трогал,
  ждут решения оператора.

**Blockers**
- (none)

**Scope changes**
- Grill добавил в трек версионирование `~/.claude` (Phase A) — изначально зона
  роста формулировалась только как «готовый kit».

**Next session targets** (measurable)
- [ ] B.1: dogfood-репо существует, `git log` ≥1 commit
- [ ] B.2–B.3: CLAUDE.md ≤200 строк (`wc -l`), `init.sh` выходит с кодом 0 (green baseline), `features.json` валидный JSON с ≥1 фичей `passes:false`
- [ ] B.4: `harness-journal.md` существует, session-ритуал в CLAUDE.md содержит журнал-строку (grep)

## Live metrics

| ID | Metric | Last measured | Target | Status |
|---|---|---|---|---|
| M1 | dogfood-сессий проведено | 4 (session 0 + F1 + F2 + s2:hardening/F3) | — (счётчик) | ✅ |
| M2 | наблюдений в harness-journal.md | 12 (3×4) | ≥1/сессию | ✅ |
| M3 | D-циклов (журнал → правки skill'а) | 1 (D.1, devlog #79) | 1 на ~5 сессий C | ✅ |
| M4 | фич в features.json со `passes:true` | 5 из 6 (F1–F5) + 2 hardening | растёт монотонно | ✅ |
| M5 | кандидатов в копилке D-цикла | 4 (.env policy; артефакты под .claude/; внешний vs self Evaluator; handoff-заметка требует re-verify) | ≥1 к D.2 | ✅ |

## Risks status

| ID | Risk | Status | Notes |
|---|---|---|---|
| R1 | Журнал заполняется формально («всё ок») и не даёт сигнала | open | проверить на первом D-цикле: если 5 сессий × 0 содержательных наблюдений — пересмотреть ритуал |
| R2 | Продуктовая срочность вытеснит lab-цель (журнал забросят) | open | чекпоинт каждые ~5 сессий из лаборатории |
| R3 | Донор _sgr всё-таки заякорит архитектуру через копипасту | open | конвенция read-only + осознанное заимствование в CLAUDE.md dogfood-репо |
