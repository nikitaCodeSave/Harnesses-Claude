# Промпт для переноса дельты в kit (запускать в `~/PROJECTS/claude-code-harness`)

---

Перенеси в kit подтверждённую A/B дельту спек-фазы из лаборатории.

**Провенанс.** Лаборатория `~/PROJECTS/Harnesses-Claude`, прогон 2026-07-22:
CC 2.1.217, Opus 4.8, 21 headless-прогон `claude --print`, N=3 на рукав,
детерминированные оракулы. Полные данные — `.claude/devlog/entries/0125-*.md`
и `.claude/benchmark/spec-upstream-ab/RESULTS.md` (прочитай оба до правки; сырые
выходы прогонов лежат в `probe*/runs/`). В лаборатории дельта уже внесена в
`WORKFLOW.md` §2 и `.claude/docs/workflow.md` — сверься с формулировками там,
но в kit переноси по-английски, в его стиле duty-строк.

**ADOPT — то, что переносим (подтверждено, 3/3 против 3/3, полная сепарация):**

1. Детектор «фиксируй *что* и *зачем*; *как* — не фиксируй».
2. Ограничения = инварианты с пометкой `[hard]` / `[soft]`, а не шаги.

Эффект: без правила 6/6 реализационных приманок из разговора оседали в
*обязывающих* разделах спеки в 3/3 прогонов, причём в одном реализационный ключ
подменил acceptance-критерий (идемпотентность «по хешу файла» вместо «по платежу»).
С правилом — 0/6 при полной сохранности бизнес-фактов (8/8 в обоих рукавах,
guard на класс регрессии devlog #113 чист).

**REJECT — то, что НЕ переносим (проверено и отклонено, не «не дошли руки»):**

- Ось spec-faithfulness в ревью-мандате — ничья 3/3 на двух классах дефектов
  (пахнущий и silent-spec). Baseline сам поднимает `docs/SPEC.md` и судит дифф
  против требований. Контрольный рукав без спеки в репо: 0 упоминаний требований
  при найденных смеллах → рычаг = **спека как файл в репо**, а не формулировка мандата.
- Отдельный `CONTEXT.md` как store — durable-слой уже разложен по
  GLOSSARY/ARCHITECTURE/CONVENTIONS/ADR.
- Формат запуска Input/Workflow/Output и «попроси `think` перед реализацией» —
  adaptive thinking включён по умолчанию, фиксированные бюджеты ретайрнуты.

**Куда править.**

Основное — `plugins/harness/references/project-docs/workflow.md`, секция
`## Size the change before you build`, рядом с буллетом **NON-GOALS**. Предлагаемый
текст (правь под стиль файла, смысл сохраняй):

```markdown
- **Spec what and why; leave how to the implementer.** Detector: a detail that moves
  business risk or architecture → write it down; pure implementation (class and function
  names, file paths, table schema, library choice) → don't — that is the implementer's
  call, and it beats a guess frozen into the spec. The conversation a spec grows out of
  always carries implementation asides; without the detector they settle into the
  *binding* sections and start standing in for the requirement.
- **Constraints are invariants, not steps** — "the operation is idempotent", not "add a
  dedup table". Mark each `[hard]` (non-negotiable) or `[soft]` (may be traded away for
  simplicity — that mark is an explicit licence to simplify, not decoration).
```

Обнови `shipped-by` в шапке этого файла на выпускаемую версию (сейчас там v1.16.1).

Второе место, по желанию — `plugins/harness/references/harness-discipline.md`,
буллет **Plan** в «The execution spine»: одна фраза, что план фиксирует *что/зачем*,
а не имена/пути/схему. Только если она не дублирует уже сказанное.

**Чего НЕ делать:**

- Не добавлять строку в duty-lines шаблона CLAUDE.md
  (`bootstrap-checklist.md` Phase 2, ~стр. 102-104). Это per-turn контекст, а правило
  нужно ровно в момент написания спеки — on-demand `workflow.md` для этого и существует.
  Если считаешь иначе — сначала обоснуй, потом правь.
- Не трогать `practice-baseline.md` §1: baseline — operator-global слой, дельта
  относится к спек-фазе, а не к поведению вообще. Вынеси как вопрос оператору, не решай сам.

**Релиз (ритуал репо, см. `.claude/CLAUDE.md`):**

1. `plugins/harness/scripts/release.sh 1.18.0` — minor: добавлено правило + элемент
   каркаса, поведение сессий меняется. (Скрипт бампит оба плагина в локстепе и
   проверяет, что затронутые project-docs несут новый `shipped-by`.)
2. CHANGELOG-запись в существующем стиле: нарративный заголовок с уроком + `### Changed`.
   Урок здесь — «спека, написанная из разговора, по умолчанию проектирует за
   исполнителя», и что дельта прошла adopt-on-proof, а её соседка по брифу — нет.
3. Devlog-запись в `.claude/devlog/` кита.
4. Commit + tag + push по тому, что напечатает `release.sh` (он намеренно не коммитит сам).

**Верификация перед коммитом:** `release.sh` стережёт штампы; глазами проверь, что
нетронутые project-docs сохранили свои старые `shipped-by` (per-file provenance),
и что новый текст не противоречит соседним буллетам секции.
