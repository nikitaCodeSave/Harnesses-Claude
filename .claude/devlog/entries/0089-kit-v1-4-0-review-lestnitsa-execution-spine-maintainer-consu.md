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
  task-notification; Monitor в скилл НЕ внесён — см. находку ниже); quarantine pattern;
  subagent brief contract + model assignment в поколение-устойчивой форме («highest/mid/
  fastest tier», mapping = config fact); extension-checklist (lazy layer + retire trigger);
  docs-discipline блок в bootstrap Phase 2 (4 правила + detect-then-prescribe гейт);
  context-rot ~256K (датировано); ROI ∝ exploration cost и Multi-agent research system +
  code-review docs в evidence-base; AHE tools>prose в fold-шаге D-цикла.
- **Гигиена**: «31 events» → 30 (и в lab principles.md); «Phase 5.5» → «Phase 5, item 5»;
  typo `\.claude`; jq-fallback в external-audit Шаг 2; Cron-хедж (наблюдаемы за teams-флагом,
  недокументированы); grounding-штампы «spot re-verified v2.1.173»; tier «A harness for every
  task» приведён к собственной рубрике (claude.com/blog = T2).

## Ключевая находка прогона
**`Monitor` tool не существует в 2.1.173** (ToolSearch в main и subagent контекстах — нет).
Lab-док workflow-async.md называл его «dominant primitive 2026 Q2» — claim помечен ⚠ STALE.
Grill-агенты поймали блокер в моём же дизайне: первая редакция секции background-waiting
вносила два новых непроверенных tool-claim'а (TaskOutput/ScheduleWakeup — profile-gated)
и опровержение никогда-не-сделанного claim'а (Monitor-скобка) — вырезано до наблюдаемой
механики. Урок: каждый tool-claim в native-capabilities — только из живого инвентаря.

## Verify
Финальная верификация двумя fresh-context аудиторами по обновлённому скиллу: 17/17 пунктов
CLOSED, блокирующих regressions нет; их 4 выживших находки (рассинхрон 4-го вхождения
лестницы + «advisory» vs «deterministic», tier-метка, сиротская строка, lab-референт в
marketplace) закрыты до коммита. Лестница сверена дословно во всех 4 вхождениях. Объём:
+120 строк к 1019 (в пределах бюджета +150); discipline 109→154. JSON plugin/marketplace
валидны, версии синхронны 1.4.0.

## Следующий шаг
Боевой тест: Audit-режим скилла на dialog_analyzer (см. план в memory/operator-чеклисте).
