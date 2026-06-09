---
plan: .claude/plans/dogfood-sgr-kit.md
last-updated: 2026-06-09
status: in-progress
session-count: 1
---

# Прогресс: Dogfood SGR-переписи через Bootstrap + long-running build kit

## Quick state

- **Last session**: 2026-06-09
- **Current phase**: Phase A — инфраструктура (4/4 done) → вход в Phase B
- **Next entry point**: B.1 — создать пустой репозиторий SGR-переписи, сессия 0 Bootstrap
- **Live test status**: n/a (dogfood-репо ещё не существует)
- **Open blockers**: 0

## Phase checklist

### Phase A — инфраструктура лаборатории (4/4 done)
- [x] A.1 — `~/.claude` под git + приватный remote `dot-claude`
- [x] A.2 — README `dot-claude` с «New project quick start»
- [x] A.3 — гигиена лаб-репо: devlog #77 закоммичен, ветка ff-merged в main, запушено
- [x] A.4 — devlog #78 + план + этот progress-файл

### Phase B — старт dogfood'а (0/5)
- [ ] B.1 — пустой репозиторий SGR-переписи
- [ ] B.2 — сессия 0: Bootstrap (CLAUDE.md ≤200 строк + settings.json)
- [ ] B.3 — Phase 5 kit: init.sh green baseline, features.json, progress, ритуал, Evaluator-строка
- [ ] B.4 — harness-journal.md + журнал-строка в ритуале
- [ ] B.5 — Plan-сессия milestone 1

### Phase C — build-цикл (0/n, n = по features.json)

### Phase D — feedback-циклы (0/n, каждые ~5 сессий C)
- [ ] D.1 — первая lab-сессия: журнал → правки skill'а + devlog

## Sessions log

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
| M1 | dogfood-сессий проведено | 0 | — (счётчик) | pending |
| M2 | наблюдений в harness-journal.md | n/a | ≥1/сессию | pending |
| M3 | D-циклов (журнал → правки skill'а) | 0 | 1 на ~5 сессий C | pending |
| M4 | фич в features.json со `passes:true` | n/a | растёт монотонно | pending |

## Risks status

| ID | Risk | Status | Notes |
|---|---|---|---|
| R1 | Журнал заполняется формально («всё ок») и не даёт сигнала | open | проверить на первом D-цикле: если 5 сессий × 0 содержательных наблюдений — пересмотреть ритуал |
| R2 | Продуктовая срочность вытеснит lab-цель (журнал забросят) | open | чекпоинт каждые ~5 сессий из лаборатории |
| R3 | Донор _sgr всё-таки заякорит архитектуру через копипасту | open | конвенция read-only + осознанное заимствование в CLAUDE.md dogfood-репо |
