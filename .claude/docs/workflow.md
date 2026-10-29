---
owner: nikitaCodeSave
status: active
---

# Development workflow (frontier-model baseline)

> **«Harness matters more than the model — review your configuration every 3-6 months because instructions tuned for older models constrain newer ones.»** — [claude.com/blog/how-claude-code-works-in-large-codebases](https://www.claude.com/blog/how-claude-code-works-in-large-codebases-best-practices-and-where-to-start) (first-party).
>
> Этот doc — **тонкий spine**: decision tree поверх built-ins, не дублирующий их описание. Slice-docs см. в [§ Routing](#routing).
>
> Spec → Build здесь — **execution-ядро**. Полный human-facing lifecycle (старт/контракт → требования/PRD → дизайн/ADR → execution → continuity/guardrails) — [../../WORKFLOW.md](../../WORKFLOW.md).

## Spine: Spec → Build (одна сессия) → доказательство

```
[ weight-class ↓ · Discovery(Explore, brownfield) · PRD-lite+NON-GOALS+инварианты[hard/soft] · design-lite→(large)грилл→ADR ]   ← upstream (WORKFLOW.md §1-3)
       ↓
SPEC                          →  BUILD (та же сессия)           →  ГОТОВО
интервью → SPEC.md               по SPEC.md, тесты пишет           команда + вывод;
(интерфейс из запроса            исполнитель, порядок              /code-review на substantive diff
дословно, ограничения scope)     не предписан

эскалации:  CHECK  — работа не помещается в одну сессию → приёмочные тесты из SPEC.md отдельным контекстом до свежей сборки
            REVIEW — по уровню риска (high-stakes, silent-wrong) → одно ревью свежим контекстом против SPEC.md, ≤3 раундов
```

Default для **нетривиальной** задачи, которая помещается в одну сессию. Проект, который развивается месяцами и копит знание, — [§ Долгий проект](#долгий-проект-слой-знаний-между-сессиями): спина та же, плюс лёгкие правила знаний и инструменты Pocock по триггеру. Trivial (typo / formatting / one-liner) — сразу Build. **Cold start (новый проект):** `/init` (repo-state → CLAUDE.md) + bootstrap canonical docs (ARCHITECTURE/CODE-MAP/GLOSSARY/CONVENTIONS/ADR/RUNBOOKS — нативно, read-before-write, per `docs-discipline.md`) + контракт (стек / mode / acceptance / verification / DENY) — детали в [../../WORKFLOW.md](../../WORKFLOW.md) §1-3.

**Почему так — измерено** (`benchmark/pipeline-ab/RESULTS.md`: три brownfield-задачи со скрытыми правилами владельца продукта, скрытый оракул, симулированный пользователь, который не правит итоговый отчёт, N=3):

| поток | 100% скрытой приёмки | стоимость (экв.) | человеку |
|---|---|---|---|
| **интервью → SPEC.md → сборка в той же сессии** | 8/9, медианы 100 / 100 / 100 | $1.0–1.4 | 1–2 хода, ~6k символов |
| то же, заданное `CLAUDE.md` кита, обычный запрос (через `/harness:task` — 8/9) | 9/9, медианы 100 / 100 / 100 | $1.7–2.6 | 1 ход, ~6–7k |
| то же, но сборка в свежей сессии | 7/9, медиана на T3 92.1 | $1.4–2.4 | 2–3 хода |
| + приёмочные тесты отдельным контекстом + ревью против спеки | 9/9 | $3.0–5.4 | 2–4 хода, ~15–19k |
| ваниль без интервью | 3/9, медиана на T1 63.9 | $0.7–0.9 | 0 ходов |
| полный пайплайн Pocock (grill → to-spec → to-tickets → implement-spec) | 9/9 | ещё в 3.1–4.4 раза дороже предыдущего | 4–7 ходов, ~20–28k |

Работает интервью до кода: без него теряются правила, которых нет в запросе (там, где бриф сам приглашал спрашивать, ваниль спрашивала и брала 100%). Свежая сессия видит только файл и теряет то, что в него не попало, — поэтому она нужна лишь тогда, когда работа не помещается в одну сессию, и тогда ей нужен носитель требований надёжнее прозы: приёмочные тесты из спеки. Параллельные исполнители и тикет-граф качества не добавили. Это расходится с best-practices, где сборку по `SPEC.md` советуют вести в свежей сессии: на работе такого размера свежая сессия без независимых тестов хуже той же. `CLAUDE.md` кита держит поток сам — без строки оператора и без команды; команды `/harness:*` качества сверх него не дали, они навигация. Из чего складывается надбавка шаблона к цене строки оператора, не разложено и не раскладывается: кит рассчитан на большие и долгие проекты, и цена сама по себе слой не снимает ([ADR 0004](adr/0004-kit-pod-bolshie-proekty-tsena-ne-kriteriy.md)).

### Spec
- *«Interview me until you could write the spec, then write it to SPEC.md»* — модель расспрашивает, пока не сможет написать спеку; факты о коде ищет сама, а не спрашивает у человека.
- Спека фиксирует *что* и *зачем*: критерии приёмки как проверяемые утверждения, non-goals, ограничения `[hard]`/`[soft]` — [WORKFLOW.md](../../WORKFLOW.md) §2. Чистая реализация (имена, пути, схема таблиц, библиотека) — не фиксируется, это решение исполнителя. **Но интерфейс, который зафиксировал запрос** (пути модулей, сигнатуры, классы ошибок, которые вызывает чужой код), — это требование, и он переносится в `SPEC.md` дословно: свежая сессия видит только файл, и выпавшая из спеки строка интерфейса ломает всё, что на неё опирается (`benchmark/pipeline-ab`, дымовой прогон).
- Где поведение выражается кодом — код, а не проза: сигнатуры, пример входа/выхода, HTML-мокап.
- ADR если объяснение решения >5 мин ([docs-discipline](../rules/docs-discipline.md) rule 6). Работа больше одной сессии — сначала карта решений, потом спека.
- Ограничения процесса и scope («не трогать X», «без новых зависимостей») — в `SPEC.md`, а не только в разговоре: компакция теряет ~36% процессных инструкций и исключений scope против 6% требований к фиче (arXiv 2610.31778).
- Вопросы окупаются: в недоопределённой задаче разрешение спрашивать возвращает большую часть разрыва до полной спеки (arXiv 2603.26233: 54.8 → до 70.4 при 70.8 с полной спекой); число вопросов само по себе не помогает (2607.21217).
- Plan mode и built-in `Plan` остаются доступными для read-only разведки, но поток их не требует.

### Check — эскалация: работа на несколько сессий, silent-wrong класс
- Триггер: сборка пойдёт в свежей сессии (работа не помещается в одну) или ошибка дорога и не видна (парсеры, guards, инвариантные рефакторы). На работе в одну сессию стадия Check качества не добавила, а стоила ~40% цены четырёхстадийного потока.
- Критерии из `SPEC.md` превращаются в приёмочные тесты **отдельным контекстом** (новая сессия или субагент), до реализации, через публичный интерфейс; ожидаемые значения — из спеки, а не из кода. Пред- и постусловия до тестов ловят больше багов (arXiv 2608.17177). Тесты, написанные после кода, наследуют его ошибки — 14% найденных ошибок против 25% у написанных независимо (arXiv 2607.05139); тест-сьюты передовых агентов дают <60% mutation score (2610.13065). Ни одна из открытых обвязок (Pocock, HumanLayer, Superpowers, Spec Kit, OpenSpec) независимого оракула не держит — тесты везде пишет исполнитель.
- Для исполнителя приёмочные тесты read-only — **deny-правилом** (`Edit`/`Write` на их путь), а не просьбой: *«If something has to happen every time, make it a hook, a deny rule, or a managed setting»*.
- Строгость — по классу модели исполнителя: модели слабее топовой нужны непрерывные проверки по ходу работы (Jain: 3/10 → 10/10 прогонов; arXiv 2609.20804 — шаг планирования поднимает слабую модель и лишь удешевляет сильную). Топовой те же непрерывные проверки качества не добавили, а стоили ×7; достаточен ли ей один финальный гейт — не проверено, поэтому независимая проверка остаётся обязательной.

### Build
- **Та же сессия, что писала спеку**, если работа в неё помещается (1M context — фича целиком без handoff). Свежая сессия — только когда не помещается, и тогда после Check.
- Порядок написания тестов и кода не предписывается — [testing rules](../rules/testing.md); тесты пишет исполнитель, качество их меряется (mutation testing), а не задаётся ритуалом.
- «Готово» = набор тестов зелёный и критерии спеки покрыты; в отчёте — команда и её вывод, а не «тесты проходят».
- Многошаговую работу текущее поколение ведёт без письменного чеклиста (task-list тулы выключены по умолчанию); что должно пережить сессию — в открытой спеке
- Subagents on demand only — дисциплина в [multi-agent.md](multi-agent.md); параллельные субагенты — не по умолчанию: в Claude Code на ограниченных задачах 59% с параллельностью против 83% без неё, токенов ×1.4–3.3, по времени выигрыша нет; польза бывает лишь на длинных задачах с действительно независимыми кусками (arXiv 2610.10263; CooperBench 2601.13295). В нашем замере тикет-граф с 12–22 исполнителями качества не добавил.

### Review
- **Дефолт — `/code-review` на substantive diff** и доказательство в отчёте исполнителя.
- **Эскалация по уровню риска — одно ревью всей ветки свежим контекстом против `SPEC.md`**: *«report gaps that affect correctness and skip style»*, каждая находка с file:line. Ревьюер, которого просят найти проблемы, найдёт что-нибудь всегда — фикс всех находок раздувает код. В замере на работе в одну сессию ревью нашло замечания в 3 прогонах из 18 при 100% скрытой приёмки во всех — вклад не виден, поэтому оно по риску, а не всегда.
- **Не больше 3 раундов** ревью → фикс; дальше не четвёртый раунд, а пересмотр подхода. Повторное ревью — только по новому диффу.
- **Человек нужен по уровню риска изменения, а не автора**: low (доки, копирайт, аддитивное за флагом) — достаточно зелёных автоматических проверок; medium — один человек; high и sensitive-пути — двое. Апрув агента за человеческий не засчитывается ([How the Claude Code team does code review](https://claude.dev/blog/solving-code-review-at-anthropic/)).
- Правила ревью конкретного репо — короткий `REVIEW.md` от владельцев кода, отдельно от CLAUDE.md: как выглядит провал здесь, лимит на мелочи, пути-исключения.
- Качество тестов меряется сенсорами — mutation testing, статанализ, — а не требованием test-first.
- `/code-review` built-in — дефолтная ступень для substantive change (working diff или PR, local, free, codebase-aware); `/review` — его алиас
- `/code-review ultra` (алиас `/ultrareview`, CLI `claude ultrareview`) — high-stakes (cloud multi-agent, ~5-10min, ~$5-20 via usage credits)
- Doc-with-code rule: PR обновляет doc в том же PR ([docs-discipline](../rules/docs-discipline.md) rule 1)
- Решение, которому должна следовать будущая работа, — ADR в той же сессии; что изменилось — описательный коммит

## Долгий проект: слой знаний между сессиями

Проект, который развивается месяцами, требует, чтобы каждая новая сессия начинала с контекста проекта — языка домена, принятых решений, состояния работы, — а не с первичного обсуждения первой задачи. Контекст живёт в версионируемых файлах репо, а не в памяти сессии.

**Измерено** (`benchmark/pipeline-ab/RESULTS.md`, многосессионный стенд: три фичи подряд в новых сессиях, владелец без памяти между ними, решения «на будущее» звучат один раз): спина без всякого слоя знаний сохранила ранние решения в 3/3 прогонах — передовая модель сама записывает их в долговременный файл и читает в следующих сессиях; лёгкие правила знаний — тоже 3/3 при +17% цены; поток Pocock по тикетам на каждую фичу (`/grill-with-docs` → `/to-spec` → `/to-tickets` → `/implement` по тикету, без `/tdd` и веера) — 2/3 в 11 раз дороже и с впятеро большим числом ходов человека (решение «на будущее» `/to-spec` оставил лишь заметкой вне scope, без суммы, а интервью следующей фичи переспросило его, и владелец без памяти согласился его снять; в ADR его не было). На слабой модели (дым, n=1) привычки нет: без правил 8/19 проверок, с правилами 18/19.

**Дефолт на каждую фичу:** спина выше + лёгкие правила знаний в проектном `CLAUDE.md` — страховка, которая не зависит от привычки конкретной модели и не даёт одному `SPEC.md` стать единственной памятью проекта:

```markdown
## Project knowledge
- Domain terms live in `GLOSSARY.md`: add a term the first time it is used or settled.
- Decisions that are hard to reverse, or that later work must follow — including ones the owner
  states "for later" — live in `docs/adr/NNNN-<slug>.md` (Context / Decision / Consequences),
  written in the session where they were made.
- Read `GLOSSARY.md` and `docs/adr/` before starting new work.
```

Это те же глоссарий и ADR, что в [docs-discipline](../rules/docs-discipline.md) rules 5–6, плюс два невыводимых пункта: решения «на будущее» записываются сразу, и знание читается перед работой. Открытая спека остаётся носителем непрерывности текущей работы.

**Инструменты Pocock — по триггеру, а не на каждую фичу** (плагин `mattpocock-skills`):

| Когда | Что | Почему |
|---|---|---|
| Фича не помещается в одну сессию | `/to-spec` → `/to-tickets`, трекер как состояние работы; `/implement` по тикету в свежей сессии | Тикеты с блокирующими рёбрами переживают сессии. Свежая сессия теряет то, чего нет в файле, — критерии тикета делать исполнимыми (§ Check) |
| Большая работа в тумане, путь не виден | `/wayfinder` — карта решений в трекере | Решения, а не срезы; собирается в спеку, когда туман рассеялся |
| Язык домена ещё складывается | `/grill-with-docs` вместо простого интервью | Ведёт `GLOSSARY.md` и ADR по ходу интервью; для переноса знаний необязателен — лёгкие правила дают то же |
| После вехи | `/retro` | Улучшает окружение: указатели в `CLAUDE.md`, механические проверки |
| Передача посреди фазы | `/handoff` | Переносимый документ для новой сессии или каталога |

Исполнители — последовательно, `/implement` по тикету, а не веер `/implement-spec`: тот же результат стоил в 3.1–4.4 раза дороже, параллельные субагенты на ограниченных задачах теряют качество (arXiv 2610.10263). `/tdd` закрыт deny-правилом (решение оператора о TDD); `/implement` собирает без него.

**Установка — плагином, не симлинками:** `claude plugin install mattpocock-skills --marketplace mattpocock/skills` (маркетплейс Pocock берёт плагин с ветки `main` его репо, тегов нет). Весь плагин — ~1.65k токенов always-on. `skillOverrides` на скиллы плагинов не действует; `/tdd` закрывается deny-правилом `Skill(mattpocock-skills:tdd)` в user settings (проверено). Автообновление плагинов при `DISABLE_AUTOUPDATER` требует `FORCE_AUTOUPDATE_PLUGINS=1`; иначе — `claude plugin update`. Стенд от установленной версии не зависит: он грузит плагин `--plugin-dir` на зафиксированном коммите.

**Не измерено:** месяцы накопления — десятки фич и решений, разрастание одной спеки. Там структура ADR вероятнее окупается, но это гипотеза.

## Routing — which built-in for what

| Задача | Что использовать | Где детали |
|--------|------------------|------------|
| Structured feature workflow (7-phase) | `/feature-dev` plugin (anthropics/claude-plugins-official) | `native-capabilities.md` |
| Long-running iterative refinement | `/ralph-loop` plugin (canonical Ralph pattern) | [workflow-async.md](workflow-async.md) |
| Async / background watch | `Monitor` tool, а где он недоступен — background Bash + output-file | [workflow-async.md](workflow-async.md) |
| Parallel feature branches | `-w` worktree + `claude agents` dispatch flags | [workflow-orchestration.md](workflow-orchestration.md) |
| Codebase-scale sweep / migration / multi-angle convergence (local) | **dynamic workflow** (keyword `ultracode`); find→refute→converge | [multi-agent.md](multi-agent.md) |
| Heavy planning | built-in `Plan` + `xhigh`/`ultrathink` (локально); облако — сессия на web в plan mode + `--teleport` | [workflow-cloud-offload.md](workflow-cloud-offload.md) |
| Bug-hunt sweep (cloud fleet) | `/code-review ultra` (алиас `/ultrareview`) | [workflow-cloud-offload.md](workflow-cloud-offload.md) |
| Scheduled / event-triggered | `Routines` (Anthropic web) | [workflow-cloud-offload.md](workflow-cloud-offload.md) |
| Independent verifications | parallel subagents (built-in `general-purpose`) | [multi-agent.md](multi-agent.md) |
| Commit / PR plumbing | `/commit` / `/commit-push-pr` plugin | `native-capabilities.md` |
| Старт нового проекта / scaffolding canonical docs | `/init` + bootstrap canonical docs (нативно, `docs-discipline.md`) | [../../WORKFLOW.md](../../WORKFLOW.md) §1-3 |
| Harness self-improvement | measurement loop + retire ritual | [workflow-evolution.md](workflow-evolution.md) |

## When workflow.md alone не покрывает

| Question | Read |
|----------|------|
| «Какой slash-command / flag / tool существует прямо сейчас?» | `.claude/docs/native-capabilities.md` — единственный canonical срез и единственное место, где допустим версионный пин |
| «Watch-process / scheduled task / handoff между сессиями» | [workflow-async.md](workflow-async.md) |
| «Параллельные сессии, worktree, dispatch flags для `claude agents`» | [workflow-orchestration.md](workflow-orchestration.md) |
| «Offload heavy phase в cloud (`/code-review ultra` / Routines / web-сессия)» | [workflow-cloud-offload.md](workflow-cloud-offload.md) |
| «Когда переучить harness под новую модель» | [workflow-evolution.md](workflow-evolution.md) |
| «Subagent дисциплина: когда spawn, когда нет» | [multi-agent.md](multi-agent.md) |
| «Что взять из community и arXiv, не дублируя» | [external-sources.md](external-sources.md) |
| «Полный lifecycle от старта/контракта/PRD/ADR до пайплайна (human-facing)» | [../../WORKFLOW.md](../../WORKFLOW.md) |

## Default effort

- **Старт — дефолт effort модели** (какой он у какой модели — `native-capabilities.md`); где остановиться, решает свип по своим задачам.
- **Свипай вниз, а не только вверх.** `low`/`medium` у текущих моделей сильные — прогоняй свип по своим задачам вместо того, чтобы держать высокий effort «на всякий случай». Понижение оправдывается замером, а не ощущением.
- **`xhigh`** — для трудных и long-running async задач; **`ultracode`** — **trigger word, не отдельный режим/tier** (per [«A harness for every task»](https://claude.com/blog/a-harness-for-every-task-dynamic-workflows-in-claude-code)): shorthand-сигнал «напиши dynamic workflow», к уровню effort не привязан. Голое «workflow» не триггерит.
- Adaptive thinking включён по умолчанию; не управляй thinking-бюджетами и не выключай thinking из харнеса — рычаг глубины здесь effort.

## Anti-patterns (cite-anchored)

| Anti-pattern | Evidence | Replacement |
|--------------|----------|-------------|
| Bash `sleep` loops для wait | Anthropic docs (tools-reference) | `Monitor` tool (event-driven) либо background Bash, если `Monitor` в профиле отсутствует — см. [workflow-async.md](workflow-async.md) |
| Polling для CI/PR status | community | `/autofix-pr` + `Monitor` |
| Vibe coding (one-shot без интервью и спеки) | SonarSource 16.4% conceptual-bug rate; `pipeline-ab`: без интервью 3/9 прогонов со 100% скрытой приёмки, медиана 63.9% на T1 | Интервью → `SPEC.md` → сборка в той же сессии |
| Спека фиксирует реализацию (имена/пути/схема/библиотека) | A/B `spec-upstream-ab/RESULTS.md` (не перемерен на текущем поколении моделей): 6/6 утечек в 3/3, одна подменила acceptance-критерий | детектор «что/зачем — явно, как — не пиши» (WORKFLOW.md §2) |
| Single end-session validation | blakecrosley 35% → 4% false-completion | task-gate + session-gate (two-gate) |
| Multi-agent для *most* coding | Anthropic explicit "ill-suited" (single-agent default) | Main thread; для scope>1 контекста — built-in dynamic workflow, не кастомный pipeline |
| Кастомная оркестрация там, где есть built-in dynamic workflow | built-ins-first | keyword `ultracode` |
| Sampling params (`top_p`/`temperature`/`top_k`) на текущих Opus/Sonnet | HTTP 400 from Anthropic | Omit entirely |
| Effort выставлен «на глаз» и не пересматривается | дефолт effort зависит от модели; `low`/`medium` у текущих моделей сильные | свип по своим задачам в обе стороны, а не фиксированный высокий |
| Инструкции самопроверки в промпте/CLAUDE.md («double-check», «add a final verification step», «use a subagent to verify») | [Anthropic prompting guide](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5): модель верифицирует себя сама, инструкция складывается с этим и даёт over-verification | Убрать из промпта; verification держать как *внешний* оракул (тесты, `/code-review`, независимый ревьюер) — [multi-agent.md](multi-agent.md) §7.3 |
| Спека как markdown-описание там, где есть исполнимый артефакт | [new rules of context engineering](https://claude.com/blog/the-new-rules-of-context-engineering-for-claude-5-generation-models): *«prefer files that are in code as it provides clear, high-fidelity instructions»* | Код, HTML-мокап, тест-сьют вместо пересказа |
| TDD / test-first как инструкция агенту | Böckeler: нет разницы в качестве и mutation score, ×3–8.5 токенов, red-шаг пропускают или подделывают; `pipeline-ab` H2: без TDD mutation score в пределах 0.05 от пайплайна с `/tdd` | Проверка pass/fail с доказательством; mutation testing как сенсор |
| Свежая сессия собирает по спеке без независимого оракула (работа на несколько сессий, silent-wrong) | `pipeline-ab`: свежая сборка только по файлу — 7/9, медиана 92.1 на T3; с приёмочными тестами отдельным контекстом — 9/9; конвергенция Jain / Böckeler / Hammant / StrongDM; arXiv 2608.17177 | Оракул из `SPEC.md` отдельным контекстом, read-only для исполнителя deny-правилом (§ Check) |
| Ревью «найди проблемы» без фильтра, фикс каждой находки | [best-practices](https://code.claude.com/docs/en/best-practices): *«will always find something»* → лишние абстракции и тесты невозможных случаев | Против `SPEC.md`, только корректность, `skip style` |
| Раунды ревью до «чисто» | Anthropic: PR с 50+ раундами за ночь | ≤3 раундов, дальше — пересмотр подхода |
| Субагент ради защиты контекстного окна | [best-practices](https://code.claude.com/docs/en/best-practices), «What you can stop doing» | Main thread; субагент — для параллельности, шумного вывода, независимого ревью |
| Находки ревьюера другой модели применяются как есть | arXiv 2607.21656: ревью более слабой моделью −8.6 п.п. у сильного автора | Каждую находку воспроизвести до фикса — [multi-agent.md](multi-agent.md) §7.3 |
| Доля смёрженных PR как метрика качества | arXiv 2609.37985: автор сам мёржит PR своего агента в 81–95% случаев | Откаты, дефекты, скрытые приёмочные тесты |
| Параллельные исполнители / тикет-граф по умолчанию | arXiv 2610.10263: Claude Code 59% против 83% без параллельности, ×1.4–3.3 токенов; `pipeline-ab`: тикет-граф с 12–22 исполнителями — та же приёмка за 3.1–4.4× цены четырёхстадийного потока | Последовательно в одной сессии; параллельно — только независимые куски длинной задачи |
| Процессные ограничения только в разговоре | arXiv 2610.31778: компакция теряет ~36% процессных инструкций и исключений scope | Записывать в `SPEC.md` |

## Sources

Primary first-party:
- [claude.com/blog — large-codebases best practices](https://www.claude.com/blog/how-claude-code-works-in-large-codebases-best-practices-and-where-to-start) — harness-matters-more-than-model doctrine
- [code.claude.com/docs/en/best-practices](https://code.claude.com/docs/en/best-practices) — интервью → `SPEC.md`, «What you can stop doing»
- [How the Claude Code team does code review](https://claude.dev/blog/solving-code-review-at-anthropic/) — ревью по уровню риска, `REVIEW.md`, лимит раундов
- [Boris Cherny — Code w/ Claude 2026 keynote](https://simonwillison.net/2026/May/6/code-w-claude-2026/) — Routines paradigm

Full source catalog: [external-sources.md](external-sources.md). Empirical foundation: [principles.md](principles.md).
