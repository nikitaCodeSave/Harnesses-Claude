---
id: 121
date: 2026-07-16
title: "Drift-remediation трек исполнен (kit v1.15.0)"
tags: [harness, kit, d-cycle, verification, continuity, temp-verify]
status: complete
---

# Drift-remediation трек исполнен (kit v1.15.0)

## Контекст
Исполнение kickoff-артефакта `plans/harness-drift-remediation.md` (продолжение #115: 4
адверсариальных harvest-агента над 37 проектами). Сессия велась из репо плагина
(`~/PROJECTS/claude-code-harness`), по одному WU за раз, с обязательным refuter-чекпойнтом
перед TIER 2 и §5-протоколом A/B temp-verify. Полный WU-лог с B0/B1-дельтами —
`plans/harness-drift-remediation-execution-log.md`.

## Изменения
**Матрица «уже закрыто»** (проекты-доноры сидели на старом ките): WU-4 (.env-deny + donor-pin)
— уже в Phase 3; ядро WU-2 (двухъярусность) — уже в v1.14.2; WU-9 (harness-journal) — уже
opt-in в playbook §2. Ложных повторных фолдов нет.

**Отгружено в kit v1.15.0** (7 файлов references/, текст/схема, ноль always-on):
- WU-1: два профиля progress (task-scoped: CLOSED или delete, оба валидны; workstream
  snapshot: prune-don't-append, эпизодика → devlog); delete-мандат снят и в
  practice-baseline §6.
- WU-2 (остаток): внешне-инициированный рефьютер для silent-wrong класса + «verify passed ≠
  invariant holds» в shipped workflow.md.
- WU-3: `blocked`/`blocked_reason`/`notes` в канон-схеме features.json; skip blocked на
  session start; verify достижимых слоёв ДО записи blocked (сужённый WU-5); campaign-развилка
  «один roadmap-носитель».
- WU-6 (сужён): project-knowledge skill — одно предложение в harness-discipline + инвентарные
  факты `user-invocable: false` (misspell-ловушка `user-invokable`) / `context: fork` в
  native-capabilities (сверено с first-party docs 2026-07-16).
- WU-10: буллет в audit-checklist §3 — hand-rolled `sync-docs` ретирается в пользу
  kit-shipped docs-discipline rule 1 (эмпирика: 3 проекта построили скилл без правила;
  принявший правило — ретайрнул скилл+агента).
- WU-11: re-sync shipped-docs сравнивает header-vs-header канона (не package-версию) —
  вечный ложный «re-sync available» снят. WU-12: install-команда playbook = README.

**REJECT через refuter-гейт** (ДВА независимых fresh-context рефьютера, конвергенция 6/6;
первый агент завис в доставке, но дошёл — вердикты совпали со вторым): WU-7 `state/`-слой и
WU-8 guard-heavy карвель — N=1 + уже покрыто каноном. Остаются watch-items: триггер —
второй независимый проект.

## Проверка
- **Evidence-гейт**: 13/13 цитат дозье подтверждены (fresh-context агент + дубль main-thread).
  Поправки к дозье: F6-a — `router-federation-workstream.md` не существует (workstream-снимок
  вобрал закрытое — тезис только сильнее); F12 — 268 строк, и router мандатит «сессия/субагент»,
  не строго внешний (ровно дыра F4); **F11-a мисаттрибуция** — .env-deny-кейс живёт в
  AI_analyst_sgr (:55-63), prompt-regress — donor-pin-кейс.
- **TEMP-verify §5**: 3/3 фикстуры B1-PASS с видимой дельтой (не B0==B1): longrun — форма
  снимка распознана и названа; guard — rung 3 «инициирует оператор, вне сессии», мандат
  «инвариант, не diff» (B0 дважды: «инициирую я, субагент»); extgate — канонные blocked-поля
  вместо изобретённых `note`/HANDOFF (изобретение воспроизвелось и у живого донора, и у B0 —
  двойное независимое подтверждение нужды схемы).
- Побочные находки рига: headless untrusted workspace игнорирует settings.json allow
  (нужен `--allowedTools`, промпт через stdin — вариадика); записи в `.claude/**` в
  неинтерактивном режиме блокируются как sensitive — сессии честно паркуют и не обходят.
- Публикация: CHANGELOG/devlog/references готовы в репо кита; **bump+tag+push — сознательный
  шаг оператора** (auto-mode классификатор корректно затребовал человеческое решение на
  публикацию подписчикам; финиш: `plugins/harness/scripts/release.sh 1.15.0` → commit/tag/push).

## Related
- #115 (харвест), #116 (предыдущие фиксы), kit-repo devlog #8, `plans/harness-drift-remediation.md`
  (kickoff) + `plans/harness-drift-remediation-execution-log.md` (WU-лог).
