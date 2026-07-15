---
id: 115
date: 2026-07-02
title: "Эмпирический аудит harness по 8 реальным проектам — узкие места vs теория"
tags: [harness, audit, empirical, cross-project]
status: complete
---

# Эмпирический аудит harness по реальным проектам — узкие места, невидимые в теории

## Контекст
Оператор попросил свести практику: аудит текущего состояния лаборатории + сбор
артефактов с проектов, реально использующих harness, + сводный анализ для выявления
узких мест, которых не видно на чистой теории. Прогон: локальный аудит лаборатории
(main thread) + 3 параллельных harvest-агента (context-isolation) по группам
проектов-потребителей. Метод — mine devlog/progress/plans/features.json/git на
эмпирическую фрикцию, не на теорию.

**Периметр (32 `.claude/`-проекта, из них с devlog-файлами — 5):** глубокий —
Greenplun (17.5k LoC, 75 devlog за 9 дней, прод NL→SQL); battle-tests — `11062026`
(16 devlog, 3 progress), `prompt-regress` (5 devlog + bespoke harness-journal),
`AI_analyst_migration_battletest` (147 commits, старый Opus-4.7-harness), `system-user`;
adoption-breadth — Max_Confluence, Whisper-stt, bottle-android, Skills, VPN и др.

## Изменения (наблюдения; артефакты не переписывались, кроме devlog-index #114)

### Что подтвердилось (multi-source convergence — сильный сигнал)

1. **§8 fresh-context refuter — единственный компонент с бесспорным ROI, и он сильнее,
   чем его формулирует канон.** Канон: «opt-in, только high-stakes». Практика (3/3
   глубоких проекта): для парсеров/rewriter'ов недоверенного входа он нужен *каждый раз*
   и ловит реальные silent-wrong баги, которые проходят собственные тесты автора.
   Greenplun #33 (token-guard недосчитал 1.7–2.5× на digit-heavy данных → тихий truncate),
   #59 (case-fold leak: 62 клиента вместо 1) — оба поймал свежий контекст, in-context
   самопроверка прошла мимо. Greenplun *захардкодил* refuter в CLAUDE.md как обязательный
   инвариант для §12/column-guard/date-guard. prompt-regress S2#1 — свежий критик нашёл
   silent SQL loss мимо in-context recheck. `11062026` #14 — refuter *зарубил* 3/5
   предложенных дополнений как overbuild. **Вывод:** для untrusted-input кода §8 —
   структурный per-feature шаг, а не occasional.

2. **Минимум-обвязки подтверждён — но эмпирически через БОЛЬ демонтажа переросшего
   harness'а, а не через дизайн-утверждение.** `AI_analyst_migration_battletest` хранит
   в `.claude.original/` ровно тот anti-pattern, что запрещает CLAUDE.md: **7 pipeline-агентов**
   (tdd-test-writer/implementer/refactorer, test-engineer, spec-reviewer, docs-sync,
   security-auditor) + **80 авто-планов**. Коммит `8060189` — его ретайр. Greenplun: 17.5k
   LoC, 0 custom hooks/skills/agents. Нюанс: **дефолт — дрейф В СТОРОНУ overbuild**;
   battle-test-репо аккретят anti-pattern, пока аудит его не вырежет. Принцип нужно
   активно энфорсить, сам он не держится.

### Узкие места, невидимые в теории (headline)

3. **Лестница верификации имеет un-automatable терминальную ступень → фичи навсегда
   застревают в `passes:false`.** Live e2e требует внешних creds/сети (Telegram в
   `11062026`, prod-Oracle в migration). `11062026`: 3/3 фичи открыты на live-Telegram
   стене; prompt-regress: 3/5. Канон «loop until verified → done» — реальность капит цикл
   на operator-handoff. `features.json passes:false` — не transient, а **постоянное
   состояние**. Правильная адаптация (`11062026` #16: 3-слойная e2e-лестница) автоматизирует
   ДО стены и называет ручную ступень — но стена остаётся.

4. **devlog-как-`.claude/devlog/*.md` имеет ~0 органического adoption; continuity
   сходится на более дешёвый субстрат.** Devlog-файлы есть в 5/32 проектов. Где continuity
   реально ценили — её *переизобрели дешевле*: VPN — префиксы git-коммитов
   (`devlog: рецидив epoxy-краша`) + удаление отработанных планов; bottle-android — датированные
   `workspace/*-sessions/*.md`; Skills — `.claude/memory/*.json` (Memory Bank). Даже глубочайший
   потребитель (Greenplun) **не использует SessionStart-hook** — continuity через ручной
   ритуал в CLAUDE.md (`pwd`→`git log -5`→progress→features.json). AI battletest — худший
   случай: «стандартизировали на `.claude/devlog/entries/`» (#138), но новый store **пустой (0)**,
   пишут в старый JSON (127 записей) + per-initiative логи → 5 конкурирующих сторов. Confound:
   часть planning-only проектов — просто там дисциплину не применяли; но reinvention-свидетельство
   confound-устойчиво. **Вывод: цель (continuity) реальна, прескриптивный ФОРМАТ — фрикция.**

5. **Progress-journal rule #7 (convert→devlog + delete) не самоисполняется.** 0 progress-файлов
   на 32 проекта, включая месячный рефактор bottle-android (textbook-кейс). Где заводили:
   Greenplun — `progress/temporal/artifacts/` пережил удалённый журнал (orphan); `11062026` —
   `audio-fragments.md` завершён но не удалён, 3/3 журнала permanently open на внешней стене.
   Cleanup-половина правила не механизирована.

6. **doc-with-code (docs-discipline #1) сам по себе НЕ предотвращает дрейф.** Greenplun:
   дрейф рецидивировал (docs про sqlparse после миграции на sqlglot; ложный факт под
   ⚠-патчем #42) — ловили *отдельные* re-sync аудиты (`800bb2d`, `3b5f628`), не per-PR
   правило. Store-миграции **фрагментируют** вместо консолидации (dual-write без cutover —
   AI battletest 127 vs 0). Дисциплина замедляет дрейф; ловят его периодические аудиты.

7. **Acceptance-критерии как замороженные числа предают ровно тогда, когда фикс правильный.**
   prompt-regress S2: инвариант «BOTH_ERROR=13 не двигать» нарушен легитимным фиксом (13→12
   был скрытой регрессией). Greenplun #45: `verify[0]` (judge ≥80% с exec-match) *штрафовал
   прогресс*. Критерии должны быть поведенческими правилами, не снапшотами. Канонный
   «define success criteria» об этой ловушке не предупреждает.

### Фиксабельные gap'ы кита (конкретные)

8. **`features.json` не имеет канонической схемы — каждый bootstrap изобретает имена полей.**
   prompt-regress S0#1: checklist `description/steps/passes` vs контракт `title/acceptance/verify`.
   `11062026`: `devlog:[]` пустые при реализованных devlog (провенанс feature↔devlog рвётся).
9. **Рецепты кита stack-biased под vitest/JS** — pytest/venv эквиваленты (`--passWithNoTests`
   → exit 5; `python -m` vs `.venv/bin/python`) выводятся заново каждый раз. Прим.: это
   *известная* проблема (memory `feedback_per_tool_resolve_python_venv`) — значит фикс
   **не пропагировался в рецепты кита**.
10. **Guardrails over-block на первом срезе → оператор откатывает руками.** `11062026`:
    `deny Read(.env)` откачен дважды («не возвращать»); `secret-scan.sh` — allow-list баг
    (голый unanchored `test` матчит любой путь). §7 «encode reactively» работает, но первый
    срез бьёт по легитимной нужде.
11. **Пользователи доклеивают слои, которых нет в 3-layer memory:** system-user — `state/`
    (durable structured system-state, отличный от episodic/atemporal); prompt-regress —
    `harness-journal.md` (kit-didn't-suffice friction-log). Сигнал реальных пробелов модели
    devlog/progress/MEMORY.

### Состояние самой лаборатории (локальный аудит)

- **Дисциплина держится:** `progress/` чист (только `.gitkeep`), docs с `last-updated`, ни один
  не за 6-мес порогом.
- **Version-провенанс кита разъехался:** `plugin.json` = **v1.11.0**, но shipped-by-штампы
  split (workflow.md v1.11.0 / docs-discipline.md v1.10.1 / ещё v1.9.2); devlog фиксирует
  только до v1.10.0 — кит уехал на ~2 версии без devlog-записи. (Может быть намеренный
  per-file provenance — не трогал, флажок оператору.)
- **`builtins-inventory.md` отстаёт от собственного ресёрча:** пришпилен к 2.1.170/2.1.143-snapshot,
  self-flag «pending consolidation» — а #114 (2.1.195) наверифайл пачку новых фич, не свёрнутых внутрь.
- **`CROSS-HARNESS-COMPARISON.md` — на Opus 4.7, 2026-05-11:** центральный ROI-claim (+25% toy /
  −24% realistic; «ROI ∝ exploration cost») **не перепроверен на 4.8**, ~7 недель stale на старой модели.
- **devlog-гигиена at scale (Greenplun):** 75 записей, archive не начат; `supersedes` использован 1 раз
  при нескольких реальных reversal — история решений в прозе, не в ссылках.

## Затронутые файлы
- `.claude/devlog/entries/0115-*.md` — эта запись
- `.claude/devlog/{index.json,tldr.md}` — регенерация (включая ранее незакоммиченный #114)
- `~/.claude/projects/.../memory/reference_critique_fresh_context_lever.md` — cross-project confirmation
- `~/.claude/projects/.../memory/feedback_continuity_format_friction.md` — новая память (adoption-gap)
- `~/.claude/projects/.../memory/MEMORY.md` — индекс-строка новой памяти

## Проверка
- Adoption-матрица: devlog-файлы 5/32; progress 0/32; 46 планов без completion-маркеров у 6 проектов.
- Refuter-ROI: 3/3 глубоких проекта, конкретные CRITICAL-баги (Greenplun #33/#59, prompt-regress S2#1).
- passes:false-стена: `11062026/features.json` (3/3), prompt-regress (3/5) — прямое чтение артефактов.
- Кит-версия: `plugin.json` v1.11.0 vs shipped-by штампы v1.11.0/v1.10.1/v1.9.2 (grep).

## Related
- #62/#65 — critique = fresh-context lever (эта запись — cross-project подтверждение)
- #99 — валидация kit v1.9.0 (battle-test refuter)
- #52..#61 — A/B harness-vs-noharness (single-shot недомер; эта запись — мульти-сессийный empirical срез)
- #114 — агрегация 2.1.195 (источник builtins-inventory staleness-флага)
