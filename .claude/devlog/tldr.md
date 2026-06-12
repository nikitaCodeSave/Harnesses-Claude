# Devlog TL;DR

Derived view — генерируется `rebuild-index.py` из `entries/*.md`.
Источник правды — `entries/`. **Этот файл не редактируется вручную.**

Назначение: холодный вход агента / читателя в проектную хронологию
без открытия всех entry-файлов целиком. Записи отсортированы по id desc.

---

## #102 · 2026-06-13 · practice-baseline project-embed по умолчанию (two-consumer fix)

**Tags:** canon, kit, harness-evolution, practice-baseline

Фидбэк оператора: при /claude-code-harness в проектах появляется недостаточно файлов, чтобы агенты знали best-practices (рекомендации Anthropic/Boris). Диагноз: §1–8 (think-before-coding, simplicity, surgical, goal-driven, tests-you-run, continuity, guardrails, fresh-context…

[→ entries/0102-practice-baseline-project-embed-po-umolchaniyu-two-consumer.md](entries/0102-practice-baseline-project-embed-po-umolchaniyu-two-consumer.md)

---

## #101 · 2026-06-13 · D-cycle: refresh-hygiene + live-vs-completed, нативно верифицировано

**Tags:** canon, kit, harness-evolution, validation

Продолжение #100. Ремарка оператора: мои правки из лаборатории в чужие проекты = костыль; плагин должен делать нативные сессии самодостаточными. Два витка D-cycle на реальных проектах.

[→ entries/0101-d-cycle-refresh-hygiene-live-vs-completed-nativno-verifitsir.md](entries/0101-d-cycle-refresh-hygiene-live-vs-completed-nativno-verifitsir.md)

---

## #100 · 2026-06-13 · Репликация kit на AI_analyst_migration: n=2 + тест самодостаточности плагина

**Tags:** canon, kit, harness-evolution, validation, benchmark

Второй реальный проект (NL→SQL для банка, Oracle, 149 py) для проверки жалобы «kit ни разу не зашёл — потеря знаний». Ветка feature/client-product-migration (main = архив, не трогать). Тяжёлый, уже однажды подрезанный harness (11 skills, 3 agents, hooks, GUIDE, features.json).

[→ entries/0100-replikatsiya-kit-na-ai-analyst-migration-n-2-test-samodostat.md](entries/0100-replikatsiya-kit-na-ai-analyst-migration-n-2-test-samodostat.md)

---

## #99 · 2026-06-12 · Валидация kit v1.9.0: battle-test + refuter-ремедиация

**Tags:** canon, kit, harness-evolution, benchmark, validation

Фидбэк оператора: «claude-code-harness ни разу не удалось успешно применить на моих проектах — всегда потеря знаний и низкое качество». Решено проверить обновлённый harness dialog_analyzer (v1.9.0, devlog #98/#26) не самоотчётом, а тремя свежими контекстами: gap → battle-test →…

[→ entries/0099-validatsiya-kit-v1-9-0-battle-test-refuter-remediatsiya.md](entries/0099-validatsiya-kit-v1-9-0-battle-test-refuter-remediatsiya.md)

---

## #98 · 2026-06-12 · Kit v1.9.0: fold практик dialog_analyzer (D-cycle)

**Tags:** canon, kit, harness-evolution, workflow

Директива оператора: довести плагин claude-code-harness до уровня, на котором он переносит наработки «фабрики» в др. проекты. Мишень — реальный аудит harness'а dialog_analyzer (/home/nikita/Документы/dialog_analyzer): pre-v1.8 родословная, местами богаче kit'а. Аудит (Mode 2)…

[→ entries/0098-kit-v1-9-0-fold-praktik-dialog-analyzer-d-cycle.md](entries/0098-kit-v1-9-0-fold-praktik-dialog-analyzer-d-cycle.md)

---

## #97 · 2026-06-11 · Kit v1.8.0: production-grade default + отгружаемая выжимка

**Tags:** canon, kit, bootstrap, docs, workflow

Продолжение #96. Две директивы оператора: (1) kit отгружает самую ценную выжимку workflow файлами в .claude/docs/ проекта — push-канал, доступный каждой сессии без вызова скилла, обновляемый через плагин; (2) дефолтная посадка — production-grade независимо от размера проекта…

[→ entries/0097-kit-v1-8-0-production-grade-default-otgruzhaemaya-vyzhimka.md](entries/0097-kit-v1-8-0-production-grade-default-otgruzhaemaya-vyzhimka.md)

---

## #96 · 2026-06-11 · Kit v1.7.0: write-through практик в проекты

**Tags:** canon, kit, bootstrap, workflow, docs

Battle-test плагина на реальном проекте (11062026/granola, 6 сессий, 8 фич) показал разрыв: артефактные практики с механическим каналом доставки (features.json, progress, devlog, red→green из глобального baseline) исполнялись образцово, а практики, жившие текстом в референсах…

[→ entries/0096-kit-v1-7-0-write-through-praktik-v-proekty.md](entries/0096-kit-v1-7-0-write-through-praktik-v-proekty.md)

---

## #95 · 2026-06-11 · Strip: custom-агенты и skill-дубли built-ins удалены

**Tags:** canon, strip, agents, skills, hooks

По распоряжению оператора — strip-ревизия лаборатории против свеже-переземлённого инвентаря built-ins (kit v1.6.1): удалить агентов и навыки, дублирующие встроенный функционал. Та же операция, что делалась в dialog_analyzer (F4/F5), теперь над собой.

[→ entries/0095-strip-custom-agenty-i-skill-dubli-built-ins-udaleny.md](entries/0095-strip-custom-agenty-i-skill-dubli-built-ins-udaleny.md)

---

## #94 · 2026-06-11 · External-audit debt fold: kit v1.6.1

**Tags:** canon, plugin, release, d-cycle, devlog-skill

Оператор прогнал /external-audit на harness-refresh коммите dialog_analyzer (c6902fa) — первый боевой запуск 3-ролевого аудита вне лаборатории. Вердикт confirmed_with_debt; два minor-долга оператор принёс в лабораторию: 1. Обоснование удаления code-reviewer ссылалось на…

[→ entries/0094-external-audit-debt-fold-kit-v1-6-1.md](entries/0094-external-audit-debt-fold-kit-v1-6-1.md)

---

## #93 · 2026-06-11 · Kit v1.6.0: operator handoff footer

**Tags:** canon, plugin, release, ux, d-cycle

Discoverability-gap, два сигнала за день (multi-source → проходит gate D-цикла): 1. Battle-test на dialog_analyzer (watch в memory): audit-сессия не предложила operator-playbook как вход — оператор не узнал про /external-audit и Phase 5 kit. 2. Прямой операторский фидбек: «не…

[→ entries/0093-kit-v1-6-0-operator-handoff-footer.md](entries/0093-kit-v1-6-0-operator-handoff-footer.md)

---

## #92 · 2026-06-11 · Kit v1.5.1: clean fair-copy edition

**Tags:** canon, plugin, release, editorial

Оператор: «идеальный чистовой вариант без заметок на полях» — файлы kit'а должны читаться как текущее состояние, без отсылок к тому, что и когда менялось.

[→ entries/0092-kit-v1-5-1-clean-fair-copy-edition.md](entries/0092-kit-v1-5-1-clean-fair-copy-edition.md)

---

## #91 · 2026-06-11 · Kit v1.5.0: full first-party re-ground

**Tags:** canon, plugin, release, audit, re-ground

Оператор спросил «вся ли информация плагина актуальна для CLI-подписки и последних моделей/версий CC?». После урока Monitor (devlog #89) ответ дан не по памяти: 3 параллельных fact-checker'а сверили каждый проверяемый claim native-capabilities/evidence-base/discipline с…

[→ entries/0091-kit-v1-5-0-full-first-party-re-ground.md](entries/0091-kit-v1-5-0-full-first-party-re-ground.md)

---

## #90 · 2026-06-11 · Операторское ревью Регламента v1 пройдено частично

**Tags:** docs, harness

Трек «Регламент v1» закрыт агентом (devlog #86/#87); оставался ручной операторский чеклист .claude/progress/operator-review.md — шаги 1–3 обязательные, 10 вопросов В1–В10. Оператор прошёл их 2026-06-11; часть вопросов закрыта решениями, часть осознанно отложена до практики. Файл…

[→ entries/0090-operatorskoe-revyu-reglamenta-v1-proydeno-chastichno.md](entries/0090-operatorskoe-revyu-reglamenta-v1-proydeno-chastichno.md)

---

## #89 · 2026-06-11 · Kit v1.4.0: review-лестница, execution spine, maintainer/consumer split

**Tags:** canon, plugin, release, audit, d-cycle

Перед боевым тестом kit'а на реальном проекте (dialog_analyzer) оператор заказал проверку «всё ли перенесено из лаборатории». Два fresh-context аудита (§8): coverage-refuter — ОПРОВЕРГНУТО (~70-75% покрытия, gap'ы G1–G10), freshness-refuter — стоит с 2 medium. Оператор…

[→ entries/0089-kit-v1-4-0-review-lestnitsa-execution-spine-maintainer-consu.md](entries/0089-kit-v1-4-0-review-lestnitsa-execution-spine-maintainer-consu.md)

---

## #88 · 2026-06-11 · Транслитерация кириллицы в slugify devlog-канона

**Tags:** bugfix, devlog, canon, test

Оператор нашёл латентный баг канона: slugify() в rebuild-index.py выбрасывал всё, кроме [a-z0-9], поэтому чисто русский title давал пустой slug и файл не проходил валидацию. Собственный пример из SKILL.md («Добавлена фильтрация по ключевым словам») был невалиден по этому же…

[→ entries/0088-transliteratsiya-kirillitsy-v-slugify-devlog-kanona.md](entries/0088-transliteratsiya-kirillitsy-v-slugify-devlog-kanona.md)

---

## #87 · 2026-06-10 · Regulation v1: B C F1.1

**Tags:** harness, regulation, cleanup, workflow

После релиза v1.3.0 (#86) оставались хвосты, зарезервированные за оператором. Оператор делегировал «оставшиеся размышления и решения от моего лица» — решения приняты и исполнены в той же сессии (Workflow №4: 5 последовательных стейджей на migration ∥ debt-фикс prompt-regress; 6…

[→ entries/0087-regulation-v1-b-c-f1-1.md](entries/0087-regulation-v1-b-c-f1-1.md)

---

## #86 · 2026-06-10 · Regulation v1 released: T2-T4 v1.3.0

**Tags:** harness, regulation, release, plugin, workflow

Закрытие трека «Регламент v1» (план .claude/plans/standard-v1-regulation.md): после T1 (#85) оставались T2 (легаси-аудит), T3 (n=2), T4 (внешний walkthrough) и Phase 4 (D.3 + релиз). Выполнено за одну сессию тремя мультиагентными workflow с итерацией оркестратора между ними.

[→ entries/0086-regulation-v1-released-t2-t4-v1-3-0.md](entries/0086-regulation-v1-released-t2-t4-v1-3-0.md)

---

## #85 · 2026-06-10 · Regulation v1 T1: smoke passed, /external-audit + 3 роли упакованы в плагин (v1.2.0)

**Tags:** harness, regulation, plugin, external-audit, test

Phase 3 T1 трека «Регламент v1»: доказать установку kit'а на чистый профиль одной командой с сохранённым провенансом и эмпирически решить отложенный с Phase 2 вопрос — паковать ли /external-audit + 3 agent-роли внутрь plugin-дира (конфликт «git-clone автозагрузка корня vs plugin…

[→ entries/0085-regulation-v1-t1-smoke-passed-external-audit-3-v1-2-0.md](entries/0085-regulation-v1-t1-smoke-passed-external-audit-3-v1-2-0.md)

---

## #84 · 2026-06-10 · Regulation v1 Phase 1→2: portable paths (R4), audit-role resolution fix (R6), plugin v1.1.0

**Tags:** harness, regulation, plugin, hooks, external-audit

Трек «Регламент v1» (план .claude/plans/standard-v1-regulation.md, прогресс .claude/progress/standard-v1.md). После Phase 1 R1–R3 (#83) оставался R4 (гигиена путей) и Phase 2 (упаковка). Session 2 нашла функц. дефект ключевой фичи: agents из ~/.claude/agents/ НЕ резолвятся как…

[→ entries/0084-regulation-v1-phase-1-2-portable-paths-r4-audit-role-resolut.md](entries/0084-regulation-v1-phase-1-2-portable-paths-r4-audit-role-resolut.md)

---

## #83 · 2026-06-10 · Regulation v1 Phase 1: operator playbook + /external-audit formalized, battle-tested on milestone-1 SGR

**Tags:** harness, regulation, external-audit, agents, dogfood

Трек «Регламент v1» (план .claude/plans/standard-v1-regulation.md), Phase 1 — сборка содержания. Цель сессии: R1 (operator playbook), R2 (/external-audit как формализованный 3-ролевой протокол + боевой verify), R3 (harness-evolution reference). Phase 0 закрыт в сессии 1 (D1–D5…

[→ entries/0083-regulation-v1-phase-1-operator-playbook-external-audit-forma.md](entries/0083-regulation-v1-phase-1-operator-playbook-external-audit-forma.md)

---

## #82 · 2026-06-10 · Package claude-code-harness as installable plugin v1.0.0

**Tags:** harness, dogfood, skills, packaging

Финал dogfood-трека (#78–#81). Исходный запрос оператора — «готовый kit для старта нового проекта» — имел две части: содержание (доказано dogfood'ом: пустое репо → работающий NL→SQL SGR-агент за 6 фич, grounded e2e, анти-паттерн избегнут) и форму (упаковка, отложенная в grill Q5…

[→ entries/0082-package-claude-code-harness-as-installable-plugin-v1-0-0.md](entries/0082-package-claude-code-harness-as-installable-plugin-v1-0-0.md)

---

## #81 · 2026-06-10 · D-cycle 2: milestone-1 closeout, 5 findings folded into kit

**Tags:** harness, dogfood, skills

Второй feedback-цикл dogfood-трека (#78/#79), запущен по сигналу оператора «D.2 сейчас» после закрытия milestone 1. Dogfood AI_analyst_sgr прошёл путь пустое-репо → работающий NL→SQL SGR-агент за 6 фич / 10 сессий: отвечает на русском, генерирует SQL, исполняет на живом Oracle…

[→ entries/0081-d-cycle-2-milestone-1-closeout-5-findings-folded-into-kit.md](entries/0081-d-cycle-2-milestone-1-closeout-5-findings-folded-into-kit.md)

---

## #80 · 2026-06-10 · Docs freshness audit: link fixes, 2.1.170 delta, archive moves

**Tags:** docs, harness

Аудит актуальности .claude/docs/ после вчерашнего re-ground на CC 2.1.169: CLI уже 2.1.170, один док пропустил актуализацию, два point-in-time дока лежали в живом слое. Сверены даты, версии, перекрёстные ссылки и упоминания ретайрнутых компонентов во всех 13 доках.

[→ entries/0080-docs-freshness-audit-link-fixes-2-1-170-delta-archive-moves.md](entries/0080-docs-freshness-audit-link-fixes-2-1-170-delta-archive-moves.md)

---

## #79 · 2026-06-09 · D-cycle 1: dogfood journal folded into bootstrap-checklist

**Tags:** harness, dogfood, skills

Первый feedback-цикл dogfood-трека (#78), запущен раньше плана (~5 сессий): после 3 продуктовых сессий AI_analyst_sgr копилка набрала 7+ подтверждённых находок, а оператор сформулировал тревогу «kit не реализует полную пред-подготовку, структура нарушена». Тревога подтвердилась…

[→ entries/0079-d-cycle-1-dogfood-journal-folded-into-bootstrap-checklist.md](entries/0079-d-cycle-1-dogfood-journal-folded-into-bootstrap-checklist.md)

---

## #78 · 2026-06-09 · Grill зон роста: dogfood-план SGR + ~/.claude под git

**Tags:** adr, harness, dogfood

Оператор: «мы очень далеки от готового kit для старта нового проекта» — при том, что #77 в тот же день записал «WINNER NEW decisively». Grill-сессия вскрыла: разрыв не в содержании kit'а, а в том, что он ни разу не прожил реальный продукт — вся валидация синтетическая…

[→ entries/0078-grill-dogfood-sgr-claude-git.md](entries/0078-grill-dogfood-sgr-claude-git.md)

---

## #77 · 2026-06-09 · Add long-running build kit to claude-code-harness Bootstrap

**Tags:** feature, harness

Анонс Fable 5 (Mythos-class, tier над Opus) заострил, что ценность способной модели максимальна на «longer and more complex tasks» — а значит критерий успеха bootstrap'а глобального skill'а claude-code-harness это «проект выдержит длинную автономную разработку», а не «есть…

[→ entries/0077-add-long-running-build-kit-to-claude-code-harness-bootstrap.md](entries/0077-add-long-running-build-kit-to-claude-code-harness-bootstrap.md)

---

## #76 · 2026-06-09 · Sync canonical claude-code-harness skill with factory knowledge

**Tags:** harness, docs

После prune глобальных skills (#75) — проверка: соответствует ли глобальный канон ~/.claude/skills/claude-code-harness/ последнему выводу «фабрики» (devlog #70–#75). Аудит выявил, что survivors (devlog/grill/tdd) конформны (tdd даже точно совпал с де-догматизированным §5), но…

[→ entries/0076-sync-canonical-claude-code-harness-skill-with-factory-knowle.md](entries/0076-sync-canonical-claude-code-harness-skill-with-factory-knowle.md)

---

## #75 · 2026-06-09 · Prune global skills delete project-docs-bootstrap and archived-skills

**Tags:** harness, cleanup

После retire project-docs-bootstrap в лабе (#74) — чистка глобального ~/.claude/skills/. Глобальный слой срабатывает во всех проектах, поэтому редундантный/баговый скилл там вреднее, чем в лабе. ~/.claude НЕ под git → удаления необратимы; перед каждым — явное подтверждение…

[→ entries/0075-prune-global-skills-delete-project-docs-bootstrap-and-archiv.md](entries/0075-prune-global-skills-delete-project-docs-bootstrap-and-archiv.md)

---

## #74 · 2026-06-09 · Retire project-docs-bootstrap skill — staleness A/B shows no lift

**Tags:** adr, harness, cleanup

После аудита и фикса скилла project-docs-bootstrap (#73) встал вопрос: чинить дальше / переписать / ретайрнуть. Применён ритуал staleness (WORKFLOW.md §125) на эмпирике (не теорией — feedback_empirical_over_theoretical_dismiss): даёт ли скилл воспроизводимый материальный лифт…

[→ entries/0074-retire-project-docs-bootstrap-skill-staleness-a-b-shows-no-l.md](entries/0074-retire-project-docs-bootstrap-skill-staleness-a-b-shows-no-l.md)

---

## #73 · 2026-06-09 · Audit fix project-docs-bootstrap skill detect-then-prescribe regression

**Tags:** docs, harness, bugfix

Скрупулёзный multi-agent аудит скилла project-docs-bootstrap (4 независимых аудитора по осям refs / actuality / harness-rules / coherence + fresh-context refuter на каждый finding) выявил регрессию уже однажды исправленного бага: скилл безусловно вписывал в артефакты…

[→ entries/0073-audit-fix-project-docs-bootstrap-skill-detect-then-prescribe.md](entries/0073-audit-fix-project-docs-bootstrap-skill-detect-then-prescribe.md)

---

## #72 · 2026-06-09 · WORKFLOW.md lifecycle expansion + spine sync

**Tags:** docs, workflow, lifecycle, sync

После актуализации #71 оператор попросил сводный плейбук «разработки проекта с Claude Code с самого начала»: как обсуждать проект, фиксировать требования, решать проектные задачи, переходить к разработке, PRD, тестирование, общий пайплайн. Затем — «расширить WORKFLOW.md» и…

[→ entries/0072-workflow-md-lifecycle-expansion-spine-sync.md](entries/0072-workflow-md-lifecycle-expansion-spine-sync.md)

---

## #71 · 2026-06-09 · Actualize → CC 2.1.169 + harness for every task + arXiv

**Tags:** harness, maintenance, versioning, sources, workflows, memory

Оператор: «проведи анализ интернет-источников — может появились обновления по Claude Code и агентной разработке; выполни все шаги и изучи статьи с arXiv». Baseline — devlog #70 (2026-06-07, срез на 2.1.168 + 3 источника), всего 2 дня назад. Research-пасс (4 параллельных…

[→ entries/0071-actualize-cc-2-1-169-harness-for-every-task-arxiv.md](entries/0071-actualize-cc-2-1-169-harness-for-every-task-arxiv.md)

---

## #70 · 2026-06-07 · Actualize harness → CC 2.1.168 + 3 fresh sources

**Tags:** harness, maintenance, versioning, hooks, sources

Оператор: «актуализируй состояние на начало сессии — вышла масса обновлений Claude Code и статей по агентной разработке». Бинарь на машине = 2.1.168, а harness-доки отставали: native-capabilities.md (canonical срез) — 2.1.154-era, lab-доки (builtins-inventory.md, все…

[→ entries/0070-actualize-harness-cc-2-1-168-3-fresh-sources.md](entries/0070-actualize-harness-cc-2-1-168-3-fresh-sources.md)

---

## #69 · 2026-06-01 · Harness bundle validation audit fixture

**Tags:** harness, measurement, validation, skills

Оператор: провести валидацию на тестовом проекте — работает ли связка claude-code-harness skill + ~/.claude/CLAUDE.md корректно и повышает ли качество (после арка #65–#68). По нашему правилу [[feedback_test_iterations_via_worktree]]: судить по acceptance против реального target…

[→ entries/0069-harness-bundle-validation-audit-fixture.md](entries/0069-harness-bundle-validation-audit-fixture.md)

---

## #68 · 2026-06-01 · claude-code-harness skill de-versioned

**Tags:** harness, principle, coherence, skills

Тот же model-agnostic триаж (#66/#67, [[feedback_model_agnostic_skills]]), теперь по глобальному канону ~/.claude/skills/claude-code-harness/ — он едет в другие проекты, поэтому version-привязки тут аукаются шире всего.

[→ entries/0068-claude-code-harness-skill-de-versioned.md](entries/0068-claude-code-harness-skill-de-versioned.md)

---

## #67 · 2026-06-01 · Foundational principle model-agnostic

**Tags:** harness, principle, coherence, docs

Продолжение #66 / [[feedback_model_agnostic_skills]]: harness-практики не привязывать к версии модели. Sweep по live-guidance выявил stale + version-bound foundational principle: в одних live-доках он был «под Opus 4.7» (устарел), в других «под Opus 4.8» — рассогласование, и…

[→ entries/0067-foundational-principle-model-agnostic.md](entries/0067-foundational-principle-model-agnostic.md)

---

## #66 · 2026-06-01 · tdd coherence model-agnostic rules

**Tags:** harness, tdd, testing, principle, coherence

Аудит согласованности: как глобальный tdd skill ложится во flow и используются ли результативные практики. Вердикт — в основном когерентно: tdd = глубокое разворачивание §5 (принцип в CLAUDE.md дёшево-всегда, методология в skill on-demand), evidence-grounded…

[→ entries/0066-tdd-coherence-model-agnostic-rules.md](entries/0066-tdd-coherence-model-agnostic-rules.md)

---

## #65 · 2026-06-01 · Fresh-context verification global principle

**Tags:** harness, principle, critique, verification

Оператор: вывод #62 (ценность critique — в свежем неякорённом контексте, не в premortem- ритуале) — это ключевой workflow-point работы с Claude Code, не менее важный, чем структурно зафиксированный подход к разработке (TDD/BDD/DDD/…). Проверка глобального слоя выявила реальный…

[→ entries/0065-fresh-context-verification-global-principle.md](entries/0065-fresh-context-verification-global-principle.md)

---

## #64 · 2026-06-01 · sync-docs retired into docs-discipline rule

**Tags:** harness, docs, skills, retire

Аудит глобальных ~/.claude/skills/ на предмет неактуальных под Opus 4.8 / расходящихся с выводами исследований. 7 скиллов; разбор по ролям.

[→ entries/0064-sync-docs-retired-into-docs-discipline-rule.md](entries/0064-sync-docs-retired-into-docs-discipline-rule.md)

---

## #63 · 2026-06-01 · Multi-session A/B: continuity-аппарат обходится стороной

**Tags:** benchmark, harness, measurement, continuity

Главный открытый трек (#52/#61): single-shot систематически зануляет continuity-столб (#54) — весь build в одном контексте, переносить нечего. Замер: разбить build NL→SQL- аналитика на 3 стадии, каждая = отдельный claude --print --no-session-persistence в одном persisted…

[→ entries/0063-multi-session-a-b-continuity.md](entries/0063-multi-session-a-b-continuity.md)

---

## #62 · 2026-05-30 · Critique-layer A/B: fresh-context — это рычаг, не premortem-ритуал

**Tags:** benchmark, harness, measurement, critique, discovery-critic

Бриф по практикам 4.8 советует «убирать скаффолдинг, который модели больше не нужен» и A/B-тестить critique/discovery-обвязку. Вопрос: субсумирует ли нативный self-check Opus 4.8 слой discovery-critic / /critique / discovery-gate.sh. Дизайн (по выбору оператора): seeded-defect…

[→ entries/0062-critique-layer-a-b-fresh-context-premortem.md](entries/0062-critique-layer-a-b-fresh-context-premortem.md)

---

## #61 · 2026-05-29 · A/B harness vs noharness single-build probe

**Tags:** benchmark, harness, measurement

Оператор: «запускай 1 для быстрой пробы». Полный A/B (#60-обвязка): claude --print строит NL→SQL-аналитик с глобальным практическим слоем ~/.claude ON (harness) vs OFF (noharness), судья — v2 на живом Oracle+ollama.

[→ entries/0061-a-b-harness-vs-noharness-single-build-probe.md](entries/0061-a-b-harness-vs-noharness-single-build-probe.md)

---

## #60 · 2026-05-29 · A/B harness test readiness (with vs without practice layer)

**Tags:** benchmark, harness, multi-agent

Оператор: «проведи все необходимые замеры и будь готов к полноценному тесту двух вариантов (с harness и без него)». Цель — измерить ценность глобального практического слоя ~/.claude на качественном оракуле v2. Дизайн зафиксирован (AskUserQuestion): агент-под-тестом = claude…

[→ entries/0060-a-b-harness-test-readiness-with-vs-without-practice-layer.md](entries/0060-a-b-harness-test-readiness-with-vs-without-practice-layer.md)

---

## #59 · 2026-05-29 · text2sql v2 live run ollama baseline

**Tags:** benchmark, feature

Оператор: «выполняй самостоятельно» по двум остаткам бенчмарка v2 — (1) закрыть live-mode _shape для wide number_map с производными ключами; (2) подключить реального агента (AgentSolver) + поднять docker-Oracle+ollama. Оператор подтвердил креды (.env)…

[→ entries/0059-text2sql-v2-live-run-ollama-baseline.md](entries/0059-text2sql-v2-live-run-ollama-baseline.md)

---

## #58 · 2026-05-29 · text2sql benchmark v2 full build and integration

**Tags:** benchmark, feature, multi-agent

После MVP (#57) оператор: «раздай задачи по проведению — бенчмарк v2». Декомпозировал остаток (задачи + оси 5-9 + live-runner) на 3 параллельных агента в изолированных worktree, по непересекающимся файлам (чистый merge), все от текущего HEAD.

[→ entries/0058-text2sql-benchmark-v2-full-build-and-integration.md](entries/0058-text2sql-benchmark-v2-full-build-and-integration.md)

---

## #57 · 2026-05-29 · text2sql benchmark v2 MVP

**Tags:** benchmark, feature

Оператор: текущий text2sql-бенчмарк примитивен (решается мгновенно), хотя просит e2e-тест против живой связки ollama+Oracle(docker); метрики надо расширить/переписать. Попросил «несколько агентов» посмотреть production-проект AI_analyst_for_work/AI_analyst_migration и…

[→ entries/0057-text2sql-benchmark-v2-mvp.md](entries/0057-text2sql-benchmark-v2-mvp.md)

---

## #56 · 2026-05-29 · system-guard simplified to DENY-only

**Tags:** refactor, harness, hooks

Сразу после hardening (#55) оператор: «system-guard можно упростить — модель умная, очевидно опасное не сделает; хук скорее формальность + дополнительный контроль». Это согласуется с central principle (минимум обвязки под Opus 4.8) и с пережитым в этой сессии трением (ASK на…

[→ entries/0056-system-guard-simplified-to-deny-only.md](entries/0056-system-guard-simplified-to-deny-only.md)

---

## #55 · 2026-05-29 · Guardrails pillar — system-guard hardening

**Tags:** feature, harness, hooks, security

Третий столб practice-слоя (после methodology #53, continuity #54): guardrails. Открытие при разведке: глобальный baseline уже существует — ~/.claude/hooks/system-guard.sh (PreToolUse, 3 tier: DENY катастрофика / ASK рискованное-обратимое / LOG sudo-audit). Значит «полная…

[→ entries/0055-guardrails-pillar-system-guard-hardening.md](entries/0055-guardrails-pillar-system-guard-hardening.md)

---

## #54 · 2026-05-29 · Continuity pillar — global SessionStart context hook

**Tags:** feature, harness, hooks

Второй столб practice-слоя (после methodology, #53): сделать «что было до» глобальным дефолтом. Раньше continuity-сёрфинг работал ТОЛЬКО в этом lab-репо через project-level .claude/hooks/session-context.sh. Цель — в ЛЮБОМ проекте Claude при старте видит недавнюю историю работы…

[→ entries/0054-continuity-pillar-global-sessionstart-context-hook.md](entries/0054-continuity-pillar-global-sessionstart-context-hook.md)

---

## #53 · 2026-05-29 · Test-quality methodology pillar (global, evidence-grounded)

**Tags:** feature, harness, adr

Оператор сформулировал недостающее звено: harness ценен как standing development-practice layer (заточить Claude под разработку), а не как разовый bootstrap; и не хватало надёжного методологического слоя (приходилось переруливать BDD/TDD в каждом проекте, чтобы не было…

[→ entries/0053-test-quality-methodology-pillar-global-evidence-grounded.md](entries/0053-test-quality-methodology-pillar-global-evidence-grounded.md)

---

## #52 · 2026-05-29 · Benchmark text2sql Opus 4.8: harness vs noharness (n=1)

**Tags:** benchmark, harness

Re-measurement cost-envelope под Opus 4.8 (триггер из devlog #50/#51 — major model upgrade). Прогон battle-test-runner.sh --task text2sql на двух армах: harness=ours vs noharness, оба --build-model opus --judge-model opus (4.8), последовательно (чтобы избежать contention на…

[→ entries/0052-benchmark-text2sql-opus-4-8-harness-vs-noharness-n-1.md](entries/0052-benchmark-text2sql-opus-4-8-harness-vs-noharness-n-1.md)

---

## #51 · 2026-05-29 · Lab docs re-grounded to Opus 4.8 + dynamic workflows

**Tags:** docs, harness

Продолжение devlog #50 (то записало «остаётся глубокий re-ground lab-доков»). Четыре on-demand reference-дока были приколочены к Opus 4.7 / CC 2.1.143 и пропускали главный новый workflow-примитив — dynamic workflows. Harness'а собственная доктрина (workflow-evolution.md)…

[→ entries/0051-lab-docs-re-grounded-to-opus-4-8-dynamic-workflows.md](entries/0051-lab-docs-re-grounded-to-opus-4-8-dynamic-workflows.md)

---

## #50 · 2026-05-29 · Harness starter consolidated under Opus 4.8

**Tags:** refactor, harness

Оператор указал, что «стартовый harness первой сессии» перегружен и местами хуже голого claude. Разведка двумя субагентами вскрыла корень: «стартер» = глобальный слой ~/.claude/, и в нём жили ДВА конкурирующих bootstrap-скилла. Глобальный harness-setup (Python-only, 19…

[→ entries/0050-harness-starter-consolidated-under-opus-4-8.md](entries/0050-harness-starter-consolidated-under-opus-4-8.md)

---

## #49 · 2026-05-18 · Working style block added to harness-setup template (A/B/C N=3×3)

**Tags:** adr, harness, experiment

Оператор сообщил, что /harness-setup (skill claude-code-harness) генерирует target-CLAUDE.md без behavioral guidance — нет «думай прежде чем кодить / минимум кода / surgical changes / verifiable goals», которые Карпати [сформулировал в…

[→ entries/0049-working-style-block-added-to-harness-setup-template-a-b-c-n.md](entries/0049-working-style-block-added-to-harness-setup-template-a-b-c-n.md)

---

## #48 · 2026-05-18 · Workflow doc split — 6-файловый layout с empirical grounding 2026 Q2

**Tags:** docs, harness, refactor

Заменили монолитный workflow.md (380 строк, 2026-05-10 vintage) на тонкий spine + 5 slice docs. Старая версия дублировала Anthropic-canonical feature-dev plugin и игнорировала весь inventory Claude Code 2.1.143 (Monitor tool, /goal, dispatch flags v2.1.142, hooks v2.1.139…

[→ entries/0048-workflow-doc-split-6-layout-empirical-grounding-2026-q2.md](entries/0048-workflow-doc-split-6-layout-empirical-grounding-2026-q2.md)

---

## #47 · 2026-05-17 · harness-setup items 1-3 closed (ruff/py-detect/B7)

**Tags:** refactor, harness, skill

Closure трёх deferred open items из devlog #46 для ~/.claude/skills/harness-setup/. Все три — разные axis того же anti-pattern #15 «prescribe-without-detect» + один scope decision. Цель — устранить friction день 1 на user'ских системах с Python ≠ 3.12 и формализовать sample-app…

[→ entries/0047-harness-setup-items-1-3-closed-ruff-py-detect-b7.md](entries/0047-harness-setup-items-1-3-closed-ruff-py-detect-b7.md)

---

## #46 · 2026-05-17 · /harness-setup audit — 13 fixes + anti-pattern #15

**Tags:** refactor, harness, skill, audit

Сессия комплексного аудита skill'а ~/.claude/skills/harness-setup/ против leader-canon (Anthropic Best Practices / Effective Harnesses / Cherny howborisusesclaudecode / NLAH arXiv 2603.25723 / Meta-Harness arXiv 2603.28052 / Chroma Context Rot). Поводом стал реальный run…

[→ entries/0046-harness-setup-audit-13-fixes-anti-pattern-15.md](entries/0046-harness-setup-audit-13-fixes-anti-pattern-15.md)

---

## #45 · 2026-05-16 · Harness-setup final outcome contract v3

**Tags:** refactor, adr, harness, skills

Pilot run /harness-setup на /home/nikita/PROJECTS/test/ (2026-05-16) выявил пять новых проблем после compact reorg v2 (#44):

[→ entries/0045-harness-setup-final-outcome-contract-v3.md](entries/0045-harness-setup-final-outcome-contract-v3.md)

---

## #44 · 2026-05-16 · Harness-setup compact reorg v2

**Tags:** refactor, adr, harness, skills

Pilot iteration 2 теста /harness-setup на пустом репо (/home/nikita/PROJECTS/test/) обнаружила два structural дефекта: (а) F8d block .venv/bin/ prefix баг — skill подставлял .venv/bin/<tool> для всех Python инструментов, не различая глобальный ruff (~/.local/bin/) от venv-bound…

[→ entries/0044-harness-setup-compact-reorg-v2.md](entries/0044-harness-setup-compact-reorg-v2.md)

---

## #43 · 2026-05-16 · harness-setup → team-ready Python-only (Windows-native, settings split, idempotent)

**Tags:** skill, harness-setup, refactor, testing

User-level skill ~/.claude/skills/harness-setup был в pre-release состоянии (создан 2026-05-15), e2e empirically tested только на Python с 4 stack-skeleton'ами (Python / Node / Rust / Go), bash-only hooks (stop-verify.sh, format.sh), single-file settings.json без team/personal…

[→ entries/0043-harness-setup-team-ready-python-only-windows-native-settings.md](entries/0043-harness-setup-team-ready-python-only-windows-native-settings.md)

---

## #42 · 2026-05-13 · Evaluator v2.0: schema enforcement — prompt + rubric layer guards

**Tags:** refactor, harness, agents, testing

Полное тестирование v2.0 как production-ready harness component выявило класс багов «schema drift в реальном critic spawn». Critic не следовал declared CRITIC.json v2.0 schema, rubric Step 3 silently fallback'ил на дефолты (// "", 0 from [].length on empty array) и выдавал…

[→ entries/0042-evaluator-v2-0-schema-enforcement-prompt-rubric-layer-guards.md](entries/0042-evaluator-v2-0-schema-enforcement-prompt-rubric-layer-guards.md)

---

## #41 · 2026-05-13 · Evaluator v2.0: class-based rubric + independent probe + EVIDENCE re-execution

**Tags:** refactor, harness, agents, hooks

Adversarial review evaluator-связки (discovery-critic agent + /critique slash command + harness-internal discovery-gate.sh hook) выявил 8 структурных слабостей v1.0 после #39: (1) PREMORTEM анкорит критика на авторском фрейминге — Phase 1 verification идёт первой, Phase 2…

[→ entries/0041-evaluator-v2-0-class-based-rubric-independent-probe-evidence.md](entries/0041-evaluator-v2-0-class-based-rubric-independent-probe-evidence.md)

---

## #40 · 2026-05-13 · Расследование gating механизма claude --bg / Agent View (2.1.140)

**Tags:** research, claude-code-builtins, factcheck, cli-gating

После релиза Claude Code 2.1.140 (changelog упоминает фикс claude --bg "connection dropped mid-request") оператор попросил протестировать функционал. Запуск claude --bg "echo test" неизменно возвращает '--bg' is not enabled. If this is unexpected, retry in a moment. — и в nested…

[→ entries/0040-gating-claude-bg-agent-view-2-1-140.md](entries/0040-gating-claude-bg-agent-view-2-1-140.md)

---

## #39 · 2026-05-13 · Evaluator decoupling: JSON artifacts + /critique slash command

**Tags:** refactor, harness, agents, hooks, adr

Evaluator-узел Planner→Generator→Evaluator (discovery-critic agent + discovery-gate.sh Stop hook) был coupled к benchmark-инфраструктуре: триггер через HARNESS_BENCH_MODE=1 / .benchmark-active marker, артефакты PREMORTEM.md / EVIDENCE.md / CRITIC.md с regex-парсимой строкой…

[→ entries/0039-evaluator-decoupling-json-artifacts-critique-slash-command.md](entries/0039-evaluator-decoupling-json-artifacts-critique-slash-command.md)

---

## #38 · 2026-05-12 · Memory layers doc and progress.md convention

**Tags:** memory, docs, harness, conventions

Запрос от оператора: «как должна реализовываться внутренняя память между сессиями и между агентами? Что советуют Boris Cherny / Matt Pocock / industry?». Triggered by предыдущий research-pass про /goal + agent view (devlog #37), где обнаружилось что чужие тексты приносят ложные…

[→ entries/0038-memory-layers-doc-and-progress-md-convention.md](entries/0038-memory-layers-doc-and-progress-md-convention.md)

---

## #37 · 2026-05-12 · Empirical fact-check /goal + agent view + continueOnBlock (Claude Code 2.1.139)

**Tags:** research, claude-code-builtins, harness-integration, factcheck

Оператор предложил «полноценный рефакторинг harness'а под built-ins Claude Code 2.1.139» на основе чужого текста про «мета-роль агента». В тексте утверждалось: /goal — built-in с Haiku-evaluator, /spec — для plan-блоков, continueOnBlock — новый hook field, agent view = TUI для…

[→ entries/0037-empirical-fact-check-goal-agent-view-continueonblock-claude.md](entries/0037-empirical-fact-check-goal-agent-view-continueonblock-claude.md)

---

## #36 · 2026-05-11 · Battle-test n=3 — sign-inversion CONFIRMED, harness wins +4pt

**Tags:** benchmark, battle-test, harness, statistical-protocol, sign-inversion, evidence-based

Phase 2.B (operator approved post-2.6) — n=3 enforcement на text2sql battle-test. Previous session (devlog #35) declared «noise band -1pt» based on n=1. Layer D protocol требует n=3 minimum для статистических claim'ов. Phase 2.B завершил 4 incremental builds (2 ours + 2…

[→ entries/0036-battle-test-n-3-sign-inversion-confirmed-harness-wins-4pt.md](entries/0036-battle-test-n-3-sign-inversion-confirmed-harness-wins-4pt.md)

---

## #35 · 2026-05-11 · Battle-test text2sql first comparison — 87 vs 88, 10 runner bugs fixed

**Tags:** benchmark, battle-test, harness, deliverable-scale, empirical, evidence-based

Phase 2.3 + 2.6 — первая end-to-end валидация battle-test infrastructure на text2sql-Oracle F-deliverable task. Ours vs no-harness, n=1 each. Operator approved sequential gates: 2.3 ours build → fix bugs → run llm-judge → 2.6 noharness full pipeline → comparison aggregate.

[→ entries/0035-battle-test-text2sql-first-comparison-87-vs-88-10-runner-bug.md](entries/0035-battle-test-text2sql-first-comparison-87-vs-88-10-runner-bug.md)

---

## #34 · 2026-05-11 · Phase 2 — battle-test-runner.sh + grade.py + llm-judge.sh complete (no OAuth burn)

**Tags:** benchmark, battle-test, harness, deliverable-scale, ralph-patterns, no-oauth

Devlog #33 — scaffolding (fixture + judge artifacts). Phase 2 — runner + grader + LLM-judge code, без OAuth. Operator явно попросил «использовать что есть из логики RALPH (.claude/loop) + провалидировать весь пайплайн» — сначала ревью loop/ patterns, потом integration. Цель…

[→ entries/0034-phase-2-battle-test-runner-sh-grade-py-llm-judge-sh-complete.md](entries/0034-phase-2-battle-test-runner-sh-grade-py-llm-judge-sh-complete.md)

---

## #33 · 2026-05-11 · Battle-test text2sql-Oracle — scaffolding (F-deliverable task type)

**Tags:** benchmark, battle-test, harness, deliverable-scale, oracle, ollama

После P4 (devlog #32) operator предложил новый task type — F-deliverable: Claude строит production-grade text2sql ассистента с нуля на реальной инфраструктуре (Oracle XE Docker + Ollama локально). Это качественно отличается от existing micro-benchmarks:

[→ entries/0033-battle-test-text2sql-oracle-scaffolding-f-deliverable-task-t.md](entries/0033-battle-test-text2sql-oracle-scaffolding-f-deliverable-task-t.md)

---

## #32 · 2026-05-11 · P4 trip-wire invariants — first behavioral validation of harness value

**Tags:** benchmark, harness, invariants, evidence-based, layer-c-validation

P1+P2 (devlog #30) + n=1 baseline (#31) показали что Layer C trajectory parser работает на synthetic stream-json, но три из четырёх метрик (skills_triggered, invariant_pings, workflow_markers) никогда не были non-zero на benign tasks T01-T04. Без adversarial probing мы не знали…

[→ entries/0032-p4-trip-wire-invariants-first-behavioral-validation-of-harne.md](entries/0032-p4-trip-wire-invariants-first-behavioral-validation-of-harne.md)

---

## #31 · 2026-05-11 · Headless runner hardening + T01-T04 trajectory baseline (n=1)

**Tags:** benchmark, harness, infrastructure, evidence-based

После P1+P2 (devlog #30) operator дал явное go на smoke-валидацию runner'а под новой stream-json + trajectory методологией и последующий re-prog T01-T04. Smoke выявил 4 проблемы в runner'е, каждая зафиксирована, после чего прогнан 8-run baseline (4 tasks × 2 harness variants)…

[→ entries/0031-headless-runner-hardening-t01-t04-trajectory-baseline-n-1.md](entries/0031-headless-runner-hardening-t01-t04-trajectory-baseline-n-1.md)

---

## #30 · 2026-05-11 · Benchmark redesign — 4-layer model + trajectory metrics (P1+P2)

**Tags:** benchmark, harness, methodology, evidence-based

Текущий бенчмарк (3-tier model, 5 задач, 4 fixture-варианта) хорошо ловил token/turn/cost deltas — empirical evidence «harness ROI ∝ exploration cost» (devlog #24-25) получено именно через него. Но методология имела 5 blind spots:

[→ entries/0030-benchmark-redesign-4-layer-model-trajectory-metrics-p1-p2.md](entries/0030-benchmark-redesign-4-layer-model-trajectory-metrics-p1-p2.md)

---

## #29 · 2026-05-11 · Ralph Loop operator review — 7 accept, 6 reject

**Tags:** adr, harness, cleanup

Ralph Loop (39 итераций, ~4ч wall-clock, $72.50) завершился штатно — RESULT:NOOP empty-backlog на iter-0038, PAUSED.md записан. На момент остановки в .claude/loop/proposals/ накопилось 13 pending PROPOSAL-диффов против protected-файлов, ожидающих человеческого ревью. Operator…

[→ entries/0029-ralph-loop-operator-review-7-accept-6-reject.md](entries/0029-ralph-loop-operator-review-7-accept-6-reject.md)

---

## #28 · 2026-05-11 · Loop iter-0001 first ACCEPT + Bug 3 fix + launch readiness

**Tags:** harness, self-improvement, loop, smoke, accept, evidence

Continuation devlog #27 (Milestone 2/3 smoke с обнаруженными bugs). User authorized автономный fix Bug 3 + re-smoke validation. Это итог: first successful iteration.

[→ entries/0028-loop-iter-0001-first-accept-bug-3-fix-launch-readiness.md](entries/0028-loop-iter-0001-first-accept-bug-3-fix-launch-readiness.md)

---

## #27 · 2026-05-11 · Self-improvement Ralph-loop — Milestone 2/3 smoke and fixes

**Tags:** harness, self-improvement, loop, ralph, smoke, benchmark, evidence

Continuation of devlog #26 (Milestone 1 scaffolding). User explicit authorization to do all Milestone 2/3 work autonomously: corpus extension, backlog generation, fixture clone, smoke loop, fixes, ADR.

[→ entries/0027-self-improvement-ralph-loop-milestone-2-3-smoke-and-fixes.md](entries/0027-self-improvement-ralph-loop-milestone-2-3-smoke-and-fixes.md)

---

## #26 · 2026-05-11 · Self-improvement Ralph-loop — Milestone 1 scaffolding

**Tags:** harness, self-improvement, loop, ralph, scaffolding

User authorized многочасовой autonomous self-improvement цикл harness'а по аналогии с Ralph-pattern ([Mishra-Sharma «Long-running Claude», Mar 2026](https://www.anthropic.com/research/long-running-Claude) + Huntley ralph-wiggum). Goal: эмпирическая эволюция harness'а для…

[→ entries/0026-self-improvement-ralph-loop-milestone-1-scaffolding.md](entries/0026-self-improvement-ralph-loop-milestone-1-scaffolding.md)

---

## #25 · 2026-05-11 · T03 FastAPI cross harness sign inversion

**Tags:** benchmark, harness, evidence, fastapi

User explicit authorization прогонять T03 на FastApi-Base (realistic FastAPI template, domain-based, async SQLAlchemy, ~30 files), сбрасывая Claude artefacts между runs. T03 spec уже существовал (tier1/tasks/T03-fastapi-health-endpoint.yaml), но ни разу не прогонялся — fixture…

[→ entries/0025-t03-fastapi-cross-harness-sign-inversion.md](entries/0025-t03-fastapi-cross-harness-sign-inversion.md)

---

## #24 · 2026-05-11 · Cross-harness empirical benchmark + headless-runner bug fixes

**Tags:** benchmark, harness, evidence

User-explicit authorization для проверки совместимости харнесов из community ecosystem (статья «HARNESSES для Claude Code», май 2026). Real-world benchmark под Opus 4.7 на одном fixture (sample-py-app), four harness variants. Previous devlog 0023 documented classifier…

[→ entries/0024-cross-harness-empirical-benchmark-headless-runner-bug-fixes.md](entries/0024-cross-harness-empirical-benchmark-headless-runner-bug-fixes.md)

---

## #23 · 2026-05-11 · Headless-runner infrastructure + classifier constraint finding

**Tags:** feature, harness

Запрос: возможность тестировать harness наработки на external projects (e.g. FastApi-Base) и замерять качество через benchmark. Без real headless invocation Tier 1 остаётся scaffolding-only (run-tier1.sh только validates structure).

[→ entries/0023-headless-runner-infrastructure-classifier-constraint-finding.md](entries/0023-headless-runner-infrastructure-classifier-constraint-finding.md)

---

## #22 · 2026-05-11 · Stop-validation multi-gate + --bare references cleanup

**Tags:** feature, harness

Phantom-completion (модель декларирует «готово», а lint/types ругаются) — реальная проблема dev-loop под Opus 4.7, не закрытая существующим stop-hook (тот гонял только pytest/npm test). Community evidence: 35% → 4% false-completion после independent verification.

[→ entries/0022-stop-validation-multi-gate-bare-references-cleanup.md](entries/0022-stop-validation-multi-gate-bare-references-cleanup.md)

---

## #21 · 2026-05-10 · benchmark infrastructure stop hook

**Tags:** feature, harness, benchmark, hooks

Пользователь дал директиву (2026-05-10) закрыть measurement gap из предыдущей сводки: «без формальных evals (Tier 1/2 task-suite runs) сравнение с industry — structural / pattern-based, не performance-quantitative». Просьба: загрузить в проект исходники для тестирования +…

[→ entries/0021-benchmark-infrastructure-stop-hook.md](entries/0021-benchmark-infrastructure-stop-hook.md)

---

## #20 · 2026-05-10 · principles.md rewrite evidence-based

**Tags:** docs, harness, refactor, research

Пользователь дал директиву (2026-05-10): «.claude/docs/principles.md отсылки к ADR — этого быть не должно, отсылки к архивной информации, ознакомься с документацией Anthropic, Claude code и полностью перепиши документ согласно лучшим рекомендациям вспомогательным докам для…

[→ entries/0020-principles-md-rewrite-evidence-based.md](entries/0020-principles-md-rewrite-evidence-based.md)

---

## #19 · 2026-05-10 · D-022 subagent isolation opt-in

**Tags:** adr, harness, workflow, research

Пользователь дал две директивы (2026-05-10):

[→ entries/0019-d-022-subagent-isolation-opt-in.md](entries/0019-d-022-subagent-isolation-opt-in.md)

---

## #18 · 2026-05-10 · workflow.md Plan→Work→Review canonical spine

**Tags:** docs, harness, workflow, research

Пользователь дал critical feedback: harness слишком опирался на свои же ранее зафиксированные ADR'ы как ground truth, не консультируясь с первоисточниками (Anthropic engineering blog, claude.com docs, GitHub репозитории, community 2026 essays). Это приводило к stale решениям и…

[→ entries/0018-workflow-md-plan-work-review-canonical-spine.md](entries/0018-workflow-md-plan-work-review-canonical-spine.md)

---

## #17 · 2026-05-10 · Harness self-contained: docs moved to .claude/docs/

**Tags:** refactor, docs, harness, portability

Harness — это переносимый pack, который инсталлируется в произвольный target-проект (/path/to/SomeProject/.claude/). У target-проекта обычно собственный docs/ (создаваемый project-docs-bootstrap skill: ARCHITECTURE.md, CODE-MAP.md, ADR/, RUNBOOKS/).

[→ entries/0017-harness-self-contained-docs-moved-to-claude-docs.md](entries/0017-harness-self-contained-docs-moved-to-claude-docs.md)

---

## #16 · 2026-05-10 · D-021: two-tier docs split (active vs archive)

**Tags:** docs, harness, refactor

Append-only history (docs-discipline rule #3, ADR-017) стал friction'ом против foundational principle. Каждый retired/superseded ADR продолжал жить в active context: HARNESS-DECISIONS.md достиг ~67 KB, 397 строк, 18 ADR'ов. CLAUDE.md ссылается на этот файл как «читать перед…

[→ entries/0016-d-021-two-tier-docs-split-active-vs-archive.md](entries/0016-d-021-two-tier-docs-split-active-vs-archive.md)

---

## #15 · 2026-05-10 · Tier 0/1 dogfood + ADR-020 fixes

**Tags:** benchmark, harness, docs, adr

Первое реальное прогон benchmark methodology из ADR-019. Tier 0 automated (static-checks.sh implementation), Tier 1 dogfood на FastApi-Base fixture с генерацией реальных docs (per project-docs-bootstrap skill workflow Phase 1-5). Three methodology gaps выявлены и зафиксированы…

[→ entries/0015-tier-0-1-dogfood-adr-020-fixes.md](entries/0015-tier-0-1-dogfood-adr-020-fixes.md)

---

## #14 · 2026-05-10 · ADR-018/019: tight format + tiered benchmark

**Tags:** adr, harness, docs, benchmark

Continuation сессии 2026-05-10. После ADR-017 (project docs bootstrap skill + discipline rule) пользователь явно дал три задачи: (а) skill-creator validation новой skill, (б) ADR-018 на refactor HARNESS-DECISIONS.md format, (в) проработка benchmark подхода для testing/validation…

[→ entries/0014-adr-018-019-tight-format-tiered-benchmark.md](entries/0014-adr-018-019-tight-format-tiered-benchmark.md)

---

## #13 · 2026-05-10 · ADR-017: project-docs-bootstrap skill + docs-discipline rule

**Tags:** adr, harness, docs

Multi-turn discussion в этой сессии: пользователь попросил deeper synthesis на тему «как Meta orchestrator руководит командами разработчиков». Первый ответ (про harness hygiene) был отвергнут как «недостаточно информации»; второй (про project-level documentation contract…

[→ entries/0013-adr-017-project-docs-bootstrap-skill-docs-discipline-rule.md](entries/0013-adr-017-project-docs-bootstrap-skill-docs-discipline-rule.md)

---

## #12 · 2026-05-10 · Trim ADR log + retire N>=3 invariant

**Tags:** cleanup, harness

Пользовательский feedback после моего предложения ADR-17 (memory taxonomy): HARNESS-DECISIONS.md «выглядит как наиболее мешающийся артефакт, раздут контекстом и часто мешает принимать решения». Это перерасставило приоритет — сначала разобраться с самим форматом, потом думать про…

[→ entries/0012-trim-adr-log-retire-n-3-invariant.md](entries/0012-trim-adr-log-retire-n-3-invariant.md)

---

## #11 · 2026-05-10 · ADR-016: multi-agent baseline + pilot validation

**Tags:** adr, harness

Сессия 2026-05-10 расширяла harness дисциплиной multi-agent под Opus 4.7. По ходу работы возникли два диалоговых поворота, изменивших scope: 1. Запрос пользователя «information should be in active access у claude through skills + reference files, не через раздутый CLAUDE.md» —…

[→ entries/0011-adr-016-multi-agent-baseline-pilot-validation.md](entries/0011-adr-016-multi-agent-baseline-pilot-validation.md)

---

## #10 · 2026-05-10 · ADR-15 retire ADR-005 implementation warm context banned · _supersedes #5_

**Tags:** adr, harness, cleanup

Внешний агент-ревью (transcript этой сессии) выявил, что ADR-005 «берём три» (managed Memory/Dreams port-over: _manifest.yml, PreToolUse exit 2 на RO-store, SessionStart hook со списком stores) принят 2026-05-09, но через сутки ни одна из трёх капабилити не материализована…

[→ entries/archive/0010-adr-15-retire-adr-005-implementation-warm-context-banned.md](entries/archive/0010-adr-15-retire-adr-005-implementation-warm-context-banned.md)

---

## #9 · 2026-05-10 · ADR-013/014 + meta-CLAUDE.md process rules (with ADR-014 rollback)

**Tags:** adr, harness

Получен детальный аудит-разбор docs/HARNESS-DECISIONS.md от внешнего рецензента: 7 пунктов — 5 process gaps + 2 эмпирические задачи. Цель: реализовать процессные дополнения, провести эмпирическую верификацию ADR-006/007 закрытия, зафиксировать решения. В процессе допущена…

[→ entries/archive/0009-adr-013-014-meta-claude-md-process-rules-with-adr-014-rollba.md](entries/archive/0009-adr-013-014-meta-claude-md-process-rules-with-adr-014-rollba.md)

---

## #8 · 2026-05-10 · Trim harness per Opus 4.7 foundational principle (ADR-010, 011, 012)

**Tags:** adr, refactor, harness

Аудит всего harness'а под цитаты Anthropic про Opus 4.7 best practices («spawns fewer subagents by default», «calls tools less often and reasons more», «response length is calibrated to task complexity») выявил 6 hooks/ skills + 1 agent + 57 строк CLAUDE.md, которые кодируют…

[→ entries/archive/0008-trim-harness-per-opus-4-7-foundational-principle-adr-010-011.md](entries/archive/0008-trim-harness-per-opus-4-7-foundational-principle-adr-010-011.md)

---

## #7 · 2026-05-09 · ADR-009 retire sandbox baseline (workflow friction)

**Tags:** refactor, harness, security, adr

ADR-008 включил sandbox в harness baseline (commit 27723e8) ссылаясь на canonical Anthropic recommendation про «84% reduction in permission prompts». Эмпирическое использование в той же сессии — несколько часов спустя — показало конкретные friction points для harness workflow:

[→ entries/archive/0007-adr-009-retire-sandbox-baseline-workflow-friction.md](entries/archive/0007-adr-009-retire-sandbox-baseline-workflow-friction.md)

---

## #6 · 2026-05-09 · ADR-008 sandbox baseline + SessionStart context hook + effort guidance

**Tags:** feature, harness, hooks, security, adr

Прогон по 6 canonical Anthropic статьям (harness-design, effective-harnesses, sandboxing, opus-4-7-best-practices, multi-agent-systems, common-workflow-patterns) выявил три baseline practice, явно рекомендованных Anthropic, у которых в harness'е НЕ было реализации. После ADR-007…

[→ entries/archive/0006-adr-008-sandbox-baseline-sessionstart-context-hook-effort-gu.md](entries/archive/0006-adr-008-sandbox-baseline-sessionstart-context-hook-effort-gu.md)

---

## #5 · 2026-05-09 · ADR-007 retire 6 skills + 2 agents как дубликаты built-ins

**Tags:** refactor, harness, adr, cleanup

Stage 2 battle-test на FastApi-Base + критический ревью пользователя выявили системное нарушение foundational principle в v0.1 expansion коммите (76c4f37). Создавая 7 user-triggered skills и 5 custom agents, я не верифицировал built-in/bundled каталог Claude Code 2.1.x…

[→ entries/archive/0005-adr-007-retire-6-skills-2-agents-built-ins.md](entries/archive/0005-adr-007-retire-6-skills-2-agents-built-ins.md)

---

## #4 · 2026-05-09 · Mandatory onboarding interview (ADR-006) после Stage 2 pilot finding

**Tags:** bugfix, agents, harness, adr

Stage 2 battle-test на pilot'е FastApi-Base выявил harness-bug: onboarding-agent в auto-mode пропустил interview phase на mature-проекте. В выводе явно: «No interview was conducted — Auto-mode prefers action over questions». Pilot'ный CLAUDE.md создан с высоким качеством…

[→ entries/archive/0004-mandatory-onboarding-interview-adr-006-stage-2-pilot-finding.md](entries/archive/0004-mandatory-onboarding-interview-adr-006-stage-2-pilot-finding.md)

---

## #3 · 2026-05-09 · Permission whitelist + quote-aware dangerous-cmd-block

**Tags:** config, hooks, harness, dx

При попытке Stage 2 install (rsync копии mature pilot) сработал встроенный auto-mode classifier Claude Code — отдельный слой ДО проектных hooks. Логи dangerous-cmd.jsonl показали: мой dangerous-cmd-block.sh пропустил оба rsync с decision="allowed". Блокировал именно built-in…

[→ entries/archive/0003-permission-whitelist-quote-aware-dangerous-cmd-block.md](entries/archive/0003-permission-whitelist-quote-aware-dangerous-cmd-block.md)

---

## #2 · 2026-05-09 · v0.1 expansion: P0 патчи гайда, skills для slash-commands, блокирующие hooks

**Tags:** feature, harness, hooks, skills, docs

После формулировки текущего этапа harness'а в .claude/plans/radiant-jingling-frost.md (v0.1 — фундамент материализован) пользователь запросил параллельное исполнение четырёх задач: применение P0-патчей к research-гайду, сборка commands, блокирующие hooks, wiring skill-creator…

[→ entries/archive/0002-v0-1-expansion-p0-skills-slash-commands-hooks.md](entries/archive/0002-v0-1-expansion-p0-skills-slash-commands-hooks.md)

---

## #1 · 2026-05-09 · Bootstrap devlog scaffold

**Tags:** feature, devlog, harness

Harness задумывался как минимальная стартовая обвязка для новых проектов под Opus 4.7. Devlog нужен с первой сессии — без него каждая последующая сессия Claude Code читает код «без памяти команды», теряет мотивацию решений и трактует squash-мерджи как однострочные изменения.

[→ entries/archive/0001-bootstrap-devlog-scaffold.md](entries/archive/0001-bootstrap-devlog-scaffold.md)
