---
id: 78
date: 2026-06-09
title: "Grill зон роста: dogfood-план SGR + ~/.claude под git"
tags: [adr, harness, dogfood]
status: complete
---

# Grill зон роста: dogfood-план SGR + ~/.claude под git

## Контекст
Оператор: «мы очень далеки от готового kit для старта нового проекта» — при том,
что #77 в тот же день записал «WINNER NEW decisively». Grill-сессия вскрыла: разрыв
не в содержании kit'а, а в том, что он ни разу не прожил реальный продукт — вся
валидация синтетическая (seed-фикстуры, single-shot, n=1–3), трек «мульти-сессийный
замер» висит с #52. Решение: закрывать dogfood'ом, не ещё одним A/B.

## Изменения
Решения grill'а (по одному вопросу, с рекомендацией на каждый — все приняты):

1. **Dogfood-цель** — реальная рабочая нужда: переписывание `AI_analyst_migration`
   (43k LoC) на SGR-агентную архитектуру. Настоящий acceptance («мне этим
   пользоваться») ловит looks-done лучше любого судьи.
2. **Где строим** — свежий пустой репозиторий: чистый Bootstrap + Phase 5 kit.
   `AI_analyst_migration` = поведенческая спецификация; `AI_analyst_migration_sgr`
   (50k, неудачная «1 агент + 1 tool») и `sgr_analyst_l1` (29k) = read-only доноры.
   Не продолжаем в _sgr: плохая архитектура якорит, и тестировался бы Audit, а не
   Bootstrap — разрыв был именно про старт нового проекта.
3. **Сбор отказов kit'а** — `harness-journal.md` в dogfood-репо + строка в
   session-ритуале CLAUDE.md: в конце сессии 1–3 наблюдения, классификация по
   failure-modes (looks-done / context anxiety / потеря когерентности / «kit мешал»).
   Раз в ~5 сессий — lab-сессия здесь: журнал → правки skill'а + devlog.
   Конвенция+файл, не Stop-hook (машинерия исказила бы сам тест kit'а).
4. **Версионирование глобального слоя** — `git init` прямо в `~/.claude`
   (whitelist `.gitignore`: только CLAUDE.md / settings.json / skills / hooks /
   commands / statusline.js) + приватный remote `nikitaCodeSave/dot-claude`.
   Мотивация: флагман жил без истории, удаления необратимы (боль зафиксирована
   в #75), дрейф фабрика↔канон уже случался (#76). Без симлинков/sync-скриптов —
   один источник правды остаётся на месте.
5. **Форма kit'а** — упаковка (plugin/template) отложена до dogfood-эмпирики;
   entry-ритуал зафиксирован секцией «New project quick start» в README
   `dot-claude`. Упаковывать непроверенное = заморозить ошибки; пользователь
   пока один — дистрибуция решает несуществующую проблему.

Выполнено в этой сессии: `dot-claude` создан и запушен (28 файлов, секрет-скан
чистый); devlog #77 закоммичен; ветка `harness/docs-bootstrap-retire-prune`
ff-merged в `main` и запушена; заведён `.claude/progress/dogfood-sgr-kit.md`.

## Затронутые файлы
- `~/.claude/{.gitignore,README.md}` — новые; репо `dot-claude` (initial commit ecbafda)
- `.claude/progress/dogfood-sgr-kit.md` — progress-журнал dogfood-трека
- `.claude/devlog/entries/0078-*.md` — эта запись

## Проверка
- `git -C ~/.claude status --short` пуст после коммита; staged ровно 28 куратированных файлов, runtime/credentials не попали.
- `gh repo view nikitaCodeSave/dot-claude` — private, main запушен.
- Лаб-репо: `main == harness/docs-bootstrap-retire-prune`, origin/main обновлён (68 коммитов).

## Related
- #77 — kit, который dogfood проверяет
- #76 — дрейф фабрика↔канон (мотивация версионирования)
- #75 — «~/.claude не под git → удаления необратимы» (закрыто этой записью)
- #63, #52 — открытый трек мульти-сессийного замера, который dogfood закрывает
