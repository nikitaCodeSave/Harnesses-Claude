---
id: 122
date: 2026-07-16
title: "Актуализация workflow-кластера до CC 2.1.211 и /code-review"
tags: [docs, harness]
status: complete
---

# Актуализация workflow-кластера до CC 2.1.211 и /code-review

## Контекст

Оператор попросил проверить актуальность `WORKFLOW.md`. Проверка против живого бинаря 2.1.211
и канонического среза кита вскрыла **функциональную ошибку роутинга**: раздел REVIEW отправлял
каждый substantive change на `/review`, тогда как `/review` — строго GitHub-PR-поверхность,
а рабочий дифф смотрит `/code-review`. Бинарь редиректит сам: `Review a GitHub pull request;
for your working diff use /code-review`.

Ошибка жила не в одном файле: тот же дрейф был в машинном спине `.claude/docs/workflow.md`,
в `workflow-cloud-offload.md`, `multi-agent.md` и `README.md` — то есть спин продолжал бы
роутить main thread на неверную команду даже после правки одного human-facing дока. Вчерашний
drift-remediation (#121) подтянул кит (там `/review`-as-diff-rung = 0 хитов ещё с #118),
лабораторные доки — нет. Классический разрыв «канон обновлён, догфуд отстал».

## Изменения

**1. `/review` → `/code-review` как дефолтная ступень (главное).** Везде, где live-док
роутил рабочий дифф на `/review`. Граница зафиксирована явно: `/code-review` — working diff
(локально, бесплатно, `--fix`/`--comment`); `/review` — только PR на GitHub.

**2. Лестница верификации.** Добавлена пропущенная ступень `/code-review` между Stop-hook'ом
и дорогим fresh-context критиком (канон: prompt check → `/goal` → Stop hook → `/code-review`
→ fresh-context). Раньше лестница прыгала от хука сразу к критику.

**3. Экономика ultrareview — с community-цифр на first-party.** Было `~20min, $15-25/run`
(провенанс — explainx.ai, весна 2026). Стало `~5-10min, ~$5-20/run via usage credits`
+ 3 бесплатных прогона на Pro/Max, `--timeout` default 30min (источник —
`code.claude.com/docs/en/ultrareview`, Jun 2026). Первичка добавлена в Sources обоих доков;
поверхность переименована в `/code-review ultra` с пометкой алиаса `/ultrareview`.

**4. Дефолтная модель — account-dependent.** `WORKFLOW.md` утверждал «дефолт — Opus 4.8»
безусловно; по канону дефолт зависит от плана (Opus 4.8 на Max/Team Premium/Enterprise PAYG,
**Sonnet 5** на Pro/Team Standard). Для портативного гайда это важно — он читается не только
с Max-аккаунта.

**5. Version-пины** → 2.1.211 (self-пины `README.md:3`, `WORKFLOW.md:3` + футер;
refresh-ledger; ссылка на canonical-срез в спине была протухшей на v2.1.195).

**Осознанно НЕ тронуто:** devlog-записи и `.claude/audits/` — frozen episodic/provenance,
их `/review`-упоминания корректны как as-of утверждения (docs-discipline rule #3).
`benchmark.md:162` («актуально на 2.1.210») — правдивый grounding-штамп прошлого прогона;
бампать его без ре-верификации `claude agents` = фабриковать провенанс.

**Проверено и держится** (ложных срабатываний нет): `/goal`, `--safe-mode`, `ultracode`
(+ rename с `workflow` в 2.1.160), `/ultraplan` с 3 A/B-вариантами, `claude agents --json`,
5 built-in субагентов, `effort=high` дефолт, специфика Fable 5, 1M-контекст, quarantine,
Monitor вместо `sleep`, три слоя continuity. Changelog 2.1.211 содержательных противоречий
не вносит — только фиксы (ближайшие по теме: ultracode не триггерится на не-человеческий
вход; PreToolUse `ask` больше не перебивается auto-mode).

## Затронутые файлы

- `WORKFLOW.md` — §REVIEW переписан (граница `/code-review` vs `/review` + экономика cloud-прогона), диаграмма пайплайна, лестница верификации, модель-дефолт, источник [10], version-пины
- `README.md` — Review-строка + лестница верификации, self-пин, refresh-ledger
- `.claude/docs/workflow.md` — спин (диаграмма + §Review), ссылка на canonical-срез v2.1.195→v2.1.211, `last-updated`
- `.claude/docs/workflow-cloud-offload.md` — TL;DR, decision tree, секция `/code-review ultra`, anti-patterns, first-party источник, `last-updated`
- `.claude/docs/multi-agent.md` — anti-pattern-таблица (замена для custom code-reviewer)
- `.claude/CLAUDE.md` — пин canonical-среза v2.1.210→v2.1.211

## Проверка

Метод — не «прочитал и кажется норм», а grep-оракул с метод-чеком (§1 global: негативный
результат поиска — это claim, а не факт):

1. `claude --version` → 2.1.211; фичи сверены `strings $BIN | grep` (прямой grep по Bun-ELF
   даёт ложные негативы — см. #114).
2. Оракул 1 — `/review` как локальная ступень в live-слое (`WORKFLOW.md`, `README.md`,
   `.claude/docs`, `.claude/CLAUDE.md`, `.claude/rules`) → **0 хитов**.
3. Оракул 2 — старая экономика (`15-25`, `~20min`, `~20мин`) → **0 хитов**.
4. **Метод-чек** — needle, который обязан найтись: `/code-review` присутствует в 4 доках
   (WORKFLOW 5, cloud-offload 11, spine 3, README 2). Оракул способен ловить сигнал → нулям
   из п.2-3 можно верить.
5. Выравнивание ASCII-диаграммы пайплайна проверено глазами (колонка REVIEW не поехала).

## Related

- #121 — drift-remediation кита (v1.15.0); здесь — тот же дрейф в догфуде лаборатории
- #118 — внешний аудит кита, где `/review` = строго PR было зафиксировано впервые (2.1.210)
- #117 — прошлая актуализация лаборатории (до 2.1.210); эта запись продолжает ledger
