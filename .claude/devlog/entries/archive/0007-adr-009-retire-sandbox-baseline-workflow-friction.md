---
id: 7
date: 2026-05-09
title: "ADR-009 retire sandbox baseline (workflow friction)"
tags: [refactor, harness, security, adr]
status: complete
---

# ADR-009 retire sandbox baseline (workflow friction)

## Контекст

ADR-008 включил sandbox в harness baseline (commit 27723e8) ссылаясь на canonical Anthropic recommendation про «84% reduction in permission prompts». Эмпирическое использование в той же сессии — несколько часов спустя — показало конкретные friction points для harness workflow:

1. Sandbox активировался автоматически после ConfigChange hook reload и **заблокировал writes в pilot-проекты** (FastApi-Base, AI_analyst_migration_battletest). Stage 2 pilot redeploy перестал работать.
2. `/tmp` стал read-only, **сломав 11/11 hook smoke tests** (которые пишут payload в /tmp). Пришлось расширять `filesystem.allowWrite` для /tmp + /var/tmp + ~/.cache — это де-факто откатывает значимую часть isolation'а.
3. Bubblewrap создавал артефакты в cwd: character device `.bash_profile` с owner `nobody`, fake overlay для других dotfiles. `git add -A` ломался на этих артефактах.
4. Network allowlist требует maintenance per-project: каждый новый dev domain — explicit add. Approval-fatigue переезжает с permission prompts на «забыл добавить в allowedDomains».

Пользователь сформулировал: «полностью удали sandbox, это лишняя защита, которая будет мешать вести нам разработку».

## Изменения

### 1. `.claude/settings.json` — удалён `sandbox` блок целиком

Settings.json теперь содержит только `permissions` + `hooks`. Обе секции остаются как primary boundary:
- `permissions.{allow,ask,deny}` whitelist (106/23/13 правил, см. devlog #3 / ADR-008 SessionStart-часть остаётся).
- 9 hooks (4 PreToolUse blocking + 1 PostToolUse + 4 lifecycle observability + SessionStart), все smoke-tested.

### 2. `.claude/CLAUDE.md` — переименована секция «Effort & sandbox defaults» → «Effort defaults»

Sandbox переехал в отдельную секцию «Boundaries posture» с явным обоснованием:
- Sandbox отключён сознательно (ADR-009).
- Boundary policy держит permissions whitelist + hooks.
- Per-project sandbox через `settings.local.json` если контекст требует.

### 3. ADR-009 в `docs/HARNESS-DECISIONS.md`

Формализует решение, supersedes ADR-008 раздел про sandbox. SessionStart hook и effort guidance из ADR-008 остаются in force. Запрет на возврат sandbox в harness baseline без empirical evidence что friction устранён.

### Что не меняется

- SessionStart hook (`session-context.sh`) — остаётся.
- Effort guidance — остаётся.
- Permission whitelist — primary boundary, не тронут.
- `secret-scan.sh`, `dangerous-cmd-block.sh` — defense-in-depth остаётся.
- Pilots — у них нет sandbox (redeploy не прошёл из-за самого sandbox), так что cleanup в пилотах не требуется.

## Затронутые файлы

- `.claude/settings.json` — удалён `sandbox` блок (43 строки → 0).
- `.claude/CLAUDE.md` — рестрactured Effort & sandbox defaults; добавлена Boundaries posture секция.
- `docs/HARNESS-DECISIONS.md` — добавлен ADR-009; ADR-008 помечен как частично superseded (sandbox-часть).

## Проверка

```bash
# settings.json валиден, без sandbox:
python3 -c "import json; d=json.load(open('.claude/settings.json')); \
  print('top-level keys:', list(d.keys())); \
  print('has sandbox:', 'sandbox' in d)"
# → top-level keys: ['permissions', 'hooks']
# → has sandbox: False

# Все hook smoke tests продолжают PASS (без sandbox /tmp снова writable):
bash /tmp/harness-hook-tests.sh
# → Results: 11 passed, 0 failed

# ADR-009 на месте:
grep -A1 'ADR-009' docs/HARNESS-DECISIONS.md | head -3

# ADR-008 sandbox-часть помечена SUPERSEDED:
grep 'SUPERSEDED' docs/HARNESS-DECISIONS.md
```

## Урок процесса (повтор паттерна)

Это **третий случай** в сессии, когда я добавлял компонент по canonical Anthropic recommendation, а пользователь корректно его отзывал:
1. Дубликаты built-ins (ADR-007) — добавил 6 skills + 2 agents, retired.
2. Sandbox baseline (ADR-009) — добавил по «84% reduction», retired через эмпирику.
3. (исключение: SessionStart hook, effort guidance, secret-scan, dangerous-cmd-block — реально полезные, остались).

Паттерн: **canonical recommendation в docs ≠ обязательно для нашего harness'а**. Каждое заимствование должно проходить foundational principle stress-test В РАБОЧЕМ КОНТЕКСТЕ, не только в обзоре статьи. Эмпирика > рекомендации.

Конкретно для будущих сессий: перед добавлением security/isolation feature — explicit user check «нужно для нашего workflow?» вместо presumption «Anthropic рекомендует, значит добавляю».

## Related

- #6 — ADR-008 (sandbox-часть теперь superseded).
- #5 — ADR-007 (другой пример «добавил → отозвал»).
- ADR-009 в `docs/HARNESS-DECISIONS.md`.
