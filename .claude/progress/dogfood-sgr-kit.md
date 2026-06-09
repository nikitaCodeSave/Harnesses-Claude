---
plan: .claude/plans/dogfood-sgr-kit.md
last-updated: 2026-06-09
status: in-progress
session-count: 3
---

# Прогресс: Dogfood SGR-переписи через Bootstrap + long-running build kit

## Quick state

- **Last session**: 2026-06-09 (Session 3 — верификация dogfood-сессии 1)
- **Current phase**: Phase C — build-цикл (1 продуктовая сессия из ~5 до первого D-цикла)
- **Next entry point**: C.2 — фича F2 (Oracle connector) в dogfood-репо; требует донорский dev-стек (`AI_analyst_migration/dev/run-dev.sh`)
- **Live test status**: dogfood `./init.sh` → ORACLE GREEN (13 passed)
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

### Phase D — feedback-циклы (0/n, каждые ~5 сессий C)
- [ ] D.1 — первая lab-сессия: журнал → правки skill'а + devlog

## Sessions log

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
| M1 | dogfood-сессий проведено | 2 (session 0 + F1) | — (счётчик) | ✅ |
| M2 | наблюдений в harness-journal.md | 6 (3+3) | ≥1/сессию | ✅ |
| M3 | D-циклов (журнал → правки skill'а) | 0 | 1 на ~5 сессий C | pending |
| M4 | фич в features.json со `passes:true` | 1 из 6 (F1) | растёт монотонно | ✅ |

## Risks status

| ID | Risk | Status | Notes |
|---|---|---|---|
| R1 | Журнал заполняется формально («всё ок») и не даёт сигнала | open | проверить на первом D-цикле: если 5 сессий × 0 содержательных наблюдений — пересмотреть ритуал |
| R2 | Продуктовая срочность вытеснит lab-цель (журнал забросят) | open | чекпоинт каждые ~5 сессий из лаборатории |
| R3 | Донор _sgr всё-таки заякорит архитектуру через копипасту | open | конвенция read-only + осознанное заимствование в CLAUDE.md dogfood-репо |
