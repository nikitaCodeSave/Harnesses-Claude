---
name: update-plan-progress
description: "Обновить progress-журнал для long-running task'а в `.claude/progress/<slug>.md` (parallel к `.claude/plans/<slug>.md`, per rule #7 docs-discipline). Записывает Quick state + Phase checklist + Session log с измеримыми результатами + Live metrics + Risks. Trigger on: '/update-plan-progress', 'обнови прогресс', 'зафиксируй сессию', 'session log', 'запиши результаты сессии', а также после завершения значимого блока работы по плану. НЕ для одноразовых правок или задач без многосессионной траектории."
argument-hint: "[plan-slug, опционально — если несколько активных планов в .claude/plans/]"
allowed-tools: Read, Write, Edit, Bash(ls .claude/plans/*), Bash(ls .claude/progress/*), Bash(git diff:*), Bash(git log:*), Bash(git status:*), Bash(date:*), Bash(test:*)
---

# Навык: progress journal для multi-session task

Поддерживает `.claude/progress/<slug>.md` — single-threaded журнал для задачи, которая идёт несколько сессий. Источник правды: progress-файл под git. SessionStart hook (`.claude/hooks/session-context.sh`) уже инжектирует последнюю строку active progress в `additionalContext` — cold-start работает автоматически.

## Когда использовать

- Задача wall-clock >1ч **или** ≥3 distinct decision points (rule #7 threshold)
- Существует план в `.claude/plans/<slug>.md`
- Завершён значимый блок работы (≥1 фаза или ≥3 шага плана) с измеримыми результатами
- Сессия подходит к концу — нужно зафиксировать state, чтобы следующая сессия стартовала с cold

**НЕ** использовать:
- Без активного плана в `.claude/plans/`
- Для одноразовых правок (нет multi-session траектории)
- Когда нет измеримых результатов — только research / scoping без артефактов
- Для статусов TaskList — это in-memory progress, не journal

## Алгоритм

### 1. Определи целевой план

```bash
ls .claude/plans/*.md 2>/dev/null
```

- 1 файл → используй его slug (filename без `.md`)
- >1 файл → если пользователь передал arg-hint, используй; иначе спроси через AskUserQuestion **которому плану** соответствует прогресс (показывай mtime, чтобы было понятно «свежий»)
- 0 файлов → отказ: «Сначала зафиксируй план в `.claude/plans/<slug>.md`»

### 2. Проверь существование progress-файла

```bash
test -f ".claude/progress/${slug}.md" && echo "exists" || echo "new"
```

- `new` → создай файл из шаблона (раздел [Структура](#структура-progress-файла-contract) ниже), Session 1
- `exists` → определи следующий Session N (читай файл, найди `### Session N` с максимальным N, увеличь на 1)

### 3. Собери данные сессии

**Что сделано** (измеримые артефакты):
- `git diff --stat HEAD~N..HEAD` (где N = коммиты текущей сессии — определи по `git log --since="<last session date>"`)
- `git log --oneline --since="..."`
- Конкретные числа из output'а тестов, бенчмарков, exit codes, grep counts, file sizes

**Discovered / Blockers / Scope changes** — синтезируй из conversation context (что обсудили, что нашли неожиданно, что заблокировало).

**Next session targets** — обязательно **measurable acceptance criteria** (число, exit code, файл существует, тест проходит — НЕ «работает», НЕ «готово»).

### 4. Обнови / создай progress-файл

Используй структуру из раздела [Структура](#структура-progress-файла-contract).

**Правила обновления:**
- Quick state — перепиши целиком (cold-start снимок текущего момента)
- Phase checklist — переключай `[ ]` → `[~]` → `[x]` или `[~]` → `[x]`; записи **не удаляй** (scope changes — отдельной строкой ниже)
- Sessions log — добавь **новую** запись сверху (reverse chronological), старые не трогай
- Live metrics — обнови колонку `Last measured` для измеренных метрик; n/a → число одностороннее, обратно не возвращай (если метрика стала irrelevant — `deprecated` в Last measured, запись в Scope changes текущей сессии)
- Risks — переключай статусы, записи не удаляй; новые риски append с новым ID

### 5. Обнови frontmatter

```yaml
---
plan: .claude/plans/<slug>.md
last-updated: YYYY-MM-DD
status: in-progress | blocked | completed
session-count: <N>
---
```

### 6. Отчёт пользователю

```
Progress обновлён: .claude/progress/<slug>.md — Session <N>
Phase: <текущая фаза> (<x>/<y> шагов done)
Next targets: <первый measurable target из Next session>
Status: <in-progress|blocked|completed>
```

Если `status: completed` — добавь напоминание: «Задача завершена. Per rule #7: запусти `/devlog` чтобы сконвертировать journal в `.claude/devlog/entries/NNNN-<slug>.md`, затем удали progress-файл».

## Структура progress-файла (contract)

```markdown
---
plan: .claude/plans/<slug>.md
last-updated: YYYY-MM-DD
status: in-progress
session-count: <N>
---

# Прогресс: <plan title>

## Quick state

- **Last session**: YYYY-MM-DD
- **Current phase**: <Phase X — short name>
- **Next entry point**: <шаг, с которого стартует следующая сессия>
- **Live test status**: <last test result, optionally>
- **Open blockers**: <count или короткий list>

## Phase checklist

### Phase A — <name> (<x>/<y> done)
- [x] A.1 — <шаг>
- [x] A.2 — <шаг>
- [~] A.3 — <шаг> (in-progress, ⇒ A.4)
- [ ] A.4 — <шаг>

### Phase B — <name> (0/M)
- [ ] B.1 — <шаг>
- ...

## Sessions log

### Session <N> — YYYY-MM-DD

**Done & measured**

| Артефакт | Метрика | Target | Hit |
|---|---|---|---|
| <file/feature> | <число> | <число> | ✅ / ❌ |

**Discovered**
- <неожиданное знание / факт>

**Blockers**
- <что мешает / accepted risk>

**Scope changes**
- <что добавилось / выпало / переехало в другую фазу>

**Next session targets** (measurable)
- [ ] <конкретный acceptance criterion с числом>
- [ ] ...

### Session <N-1> — YYYY-MM-DD
... (предыдущая, неприкосновенна)

## Live metrics

| ID | Metric | Last measured | Target | Status |
|---|---|---|---|---|
| M1 | <name> | <число / n/a> | <число> | ✅ / ❌ / pending |
| M2 | ... | ... | ... | ... |

## Risks status

| ID | Risk | Status | Notes |
|---|---|---|---|
| R1 | <риск> | open / accepted / closed / promoted | <короткий audit trail> |
| R2 | ... | ... | ... |
```

## Methodology (9 правил)

Контракт для measurable progress tracking. Применяется во всех progress-файлах.

1. **Acceptance criteria всегда measurable** — число / exit code / file exists / grep count / test pass; НЕ «работает», НЕ «готово».
2. **Session log в обратной хронологии** — последняя сессия наверху, старые не редактируются.
3. **Fixed structure session log**: Done & measured / Discovered / Blockers / Scope changes / Next targets. Пропуски — явные `(none)`, не отсутствие секции.
4. **Live metrics — накопительные**, никогда не удаляются. n/a → число одностороннее. Регрессия видна в `git diff`.
5. **Risks live**: статусы переключаются (open → accepted → closed / promoted), записи не deletion-аются. Audit trail.
6. **Cold-start protocol**: последний Session log + Next session targets = единственная точка входа для следующей сессии. Quick state — 5-секундный снимок состояния.
7. **Scope creep visible**: scope changes явно фиксируются в Session log; план в `.claude/plans/<slug>.md` тоже обновляется, чтобы было consistency.
8. **Fail-stop**: если K из M next-session acceptance criteria провалились — НЕ продвигайся к следующей фазе. Зафиксируй blocker, переоцени план.
9. **Один progress = одна задача**: не объединяй несвязанные траектории. Если по ходу обнаружилась параллельная задача — отдельный slug, отдельный plan, отдельный progress.

## Завершение задачи

Per rule #7 docs-discipline:

1. Финальный update progress: `status: completed`, Session N с **Done & measured** для финального acceptance criteria
2. Запусти `/devlog` — создаст `.claude/devlog/entries/NNNN-<slug>.md` (frontmatter `status: complete`, body resume'ом из Sessions log: контекст, решения, измерения, затронутые файлы)
3. Удали `.claude/progress/<slug>.md` (`git rm`) — он мигрировал в devlog
4. (Опционально) переименуй / архивируй `.claude/plans/<slug>.md` если задача дальше не развивается

## Связь с другими артефактами

- **`.claude/rules/docs-discipline.md` rule #7** — invariant про progress journal threshold + SessionStart hook + конверсию в devlog. Этот skill — operational механика для rule #7.
- **`.claude/hooks/session-context.sh:35-42`** — SessionStart hook, инжектирует tail active progress-файла в `additionalContext`. Никаких дополнительных hook'ов скилл НЕ требует.
- **`.claude/skills/devlog/SKILL.md`** — финальный conversion progress → devlog entry при `status: completed`.
- **`.claude/plans/<slug>.md`** — план под git, source of truth для **что** делать; progress-файл — **что сделано**. Дробление осознанное: план редко меняется, прогресс — каждую сессию.
