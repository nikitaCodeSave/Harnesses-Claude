---
id: 89
date: 2026-06-11
title: "Kit v1.4.0: review-лестница, execution spine, maintainer/consumer split"
tags: [canon, plugin, release, audit, d-cycle]
status: complete
---

# Kit v1.4.0: review-лестница, execution spine, maintainer/consumer split

## Контекст
Перед боевым тестом kit'а на реальном проекте (dialog_analyzer) оператор заказал проверку
«всё ли перенесено из лаборатории». Два fresh-context аудита (§8): coverage-refuter —
ОПРОВЕРГНУТО (~70-75% покрытия, gap'ы G1–G10), freshness-refuter — стоит с 2 medium.
Оператор согласовал доработку; дизайн правок прошёл grill двумя свежими контекстами
(линзы: минимализм / потребитель-на-чужой-машине), оба поймали блокер в первоначальном
дизайне (см. ниже). Это fold вердиктов внешних аудитов в канон — D-цикл по форме
harness-evolution.md (источник сигналов: audit-вердикты, не journal).

## Изменения (kit, dot-claude commit + tag claude-code-harness--v1.4.0)
- **G1 (HIGH) review-лестница**: native-capabilities — новая секция «Code review — built-in
  surfaces» (`/review`, `/code-review`, `/security-review`, `claude ultrareview` — verified
  `claude --help` 2.1.173; экономика помечена community-reported + дата); `/review`-ступень
  вшита в лестницу верификации во **всех 4 местах** (SKILL.md p7, discipline ladder,
  /goal-секция, bootstrap Optional next steps); audit-checklist §3 — custom `code-reviewer`
  как классический оффендер → route to built-ins.
- **G2 (HIGH) execution spine**: harness-discipline — секция «Plan → Work → Review»
  (plan mode `Shift+Tab`×2 / `--permission-mode plan`, acceptance criteria = оракул,
  «not machinery»); вплетено в Working style шаблона bootstrap (plan-mode вход, `/review`
  выход); plan-mode mechanics у Plan-агента в native-capabilities.
- **M3 allowed-tools**: + `Bash(claude --print:*)`, `Bash(claude plugin list:*)` (Phase 7
  verify и pre-flight external-audit больше не упираются в frontmatter); Phase 7 — note
  про expected first-run approval оракула.
- **M4 maintainer vs consumer**: operator-playbook — 3 пути доставки инлайн (мёртвая ссылка
  на `~/.claude/README.md` убрана; baseline едет только git-clone'ом — отмечено); §6 D-цикл
  помечен «роль: мейнтейнер канона»; harness-evolution шаг 5 — скобка для потребителя
  плагина; lab-референты помечены «maintainer's lab, не отгружаются» (вкл. marketplace.json
  metadata).
- **G3–G10**: «Background waiting — no sleep-polling» (механика background Bash +
  task-notification; Monitor добавлен патчем v1.4.1 — см. исправленную находку ниже);
  quarantine pattern;
  subagent brief contract + model assignment в поколение-устойчивой форме («highest/mid/
  fastest tier», mapping = config fact); extension-checklist (lazy layer + retire trigger);
  docs-discipline блок в bootstrap Phase 2 (4 правила + detect-then-prescribe гейт);
  context-rot ~256K (датировано); ROI ∝ exploration cost и Multi-agent research system +
  code-review docs в evidence-base; AHE tools>prose в fold-шаге D-цикла.
- **Гигиена**: «31 events» → 30 (и в lab principles.md); «Phase 5.5» → «Phase 5, item 5»;
  typo `\.claude`; jq-fallback в external-audit Шаг 2; Cron-хедж (наблюдаемы за teams-флагом,
  недокументированы); grounding-штампы «spot re-verified v2.1.173»; tier «A harness for every
  task» приведён к собственной рубрике (claude.com/blog = T2).

## Ключевая находка прогона (исправлена оператором в тот же день → патч v1.4.1)
Изначальный вывод «Monitor tool не существует в 2.1.173» (по отсутствию в живом
tool-инвентаре main и subagent контекстов) — **ошибочен**. Оператор указал на
first-party `tools-reference#monitor-tool`: Monitor существует с v2.1.98, а в этом профиле
невидим из-за `DISABLE_TELEMETRY=1` в settings.json (док прямо называет этот gating; также
недоступен на Bedrock/Vertex/Foundry). Урок перевёрнут: **отсутствие в живом инвентаре —
факт профиля/env, не продукта**; авторитет существования — first-party tools-reference,
живой инвентарь подтверждает только доступность «здесь». Та же страница дала вторую
поправку: Cron* (session-scoped cron) и ScheduleWakeup (self-paced /loop) теперь
задокументированы first-party, Task* — обычный session task list (не teams-gated) — хедж
v1.4.0 устарел в день написания. Всё исправлено патчем v1.4.1. Grill- и verify-агенты
сделали ту же ошибку (тот же env) — независимость контекста не лечит общий слепой env;
зафиксировано feedback-memory «tool-inventory-profile-dependent».

## Verify
Финальная верификация двумя fresh-context аудиторами по обновлённому скиллу: 17/17 пунктов
CLOSED, блокирующих regressions нет; их 4 выживших находки (рассинхрон 4-го вхождения
лестницы + «advisory» vs «deterministic», tier-метка, сиротская строка, lab-референт в
marketplace) закрыты до коммита. Лестница сверена дословно во всех 4 вхождениях. Объём:
+120 строк к 1019 (в пределах бюджета +150); discipline 109→154. JSON plugin/marketplace
валидны, версии синхронны 1.4.0.

## Следующий шаг
Боевой тест: Audit-режим скилла на dialog_analyzer (см. план в memory/operator-чеклисте).
