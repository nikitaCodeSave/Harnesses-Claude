---
id: 85
date: 2026-06-10
title: "Regulation v1 T1: smoke passed, /external-audit + 3 роли упакованы в плагин (v1.2.0)"
tags: [harness, regulation, plugin, external-audit, test]
status: complete
---

# Regulation v1 T1: smoke passed, /external-audit + 3 роли упакованы в плагин (v1.2.0)

## Контекст
Phase 3 T1 трека «Регламент v1»: доказать установку kit'а на чистый профиль одной
командой с сохранённым провенансом и эмпирически решить отложенный с Phase 2 вопрос —
паковать ли `/external-audit` + 3 agent-роли внутрь plugin-дира (конфликт «git-clone
автозагрузка корня vs plugin = поддиректория»).

## Изменения

**T1 smoke (3 чистых профиля `CLAUDE_CONFIG_DIR=$(mktemp -d)`, CC 2.1.170):**
- CFG1: `marketplace add` → `install` → `details` — exit=0 каждый; bootstrap пустого
  репо по quick start: plugin-skill ТРИГГЕРНУЛСЯ на каноничную фразу (Skill-вызов
  доказан transcript'ом), создан CLAUDE.md 30 строк (indexer) + .gitignore + settings.json.
- Найдено: v1.1.0 plugin-only = dangling refs (playbook ссылается на `/external-audit`
  и `~/.claude/{commands,agents}`, которых на plugin-only профиле нет).
- CFG2 (тестовый marketplace): commands+agents ВНУТРИ plugin-дира загружаются —
  inventory Skills 2 / Agents 3; роли резолвятся НАТИВНО как
  `subagent_type: claude-code-harness:<role>`; команда видна как
  `claude-code-harness:external-audit`.
- CFG3: финальный re-smoke релиза v1.2.0 — Skills 2 / Agents 3 ✅.

**Реализация в dot-claude (commit 6036560, tag `claude-code-harness--v1.2.0`):**
- `git mv` `commands/external-audit.md` + `agents/{evidence-executor,process-auditor,
  code-refuter}.md` → `skills/claude-code-harness/{commands,agents}/`. Конфликт
  clone-vs-plugin снялся переносом без дублирования: `~/.claude/skills/<kit>`
  автозагружается как `@skills-dir` plugin и несёт то же самое.
- Шаг 1 `/external-audit` переписан native-first: спавнить `claude-code-harness:<role>`
  напрямую; fallback (general-purpose + чтение role-файла по ROLE_DIR) сохранён.
  Риск R6 закрыт сильнее ожидаемого.
- Bonus-фикс: YAML frontmatter команды был невалиден (двоеточие в plain scalar
  `argument-hint`) — runtime молча дропал метаданные; пойман `claude plugin validate`.
- README (пути доставки, v1.2.0) + operator-playbook (карта слоёв, имя команды) обновлены;
  bump 1.1.0→1.2.0 синхронно в обоих манифестах, оба validate ✔.

**Headless-граница bootstrap'а:** в `--print --permission-mode acceptEdits` запись
`.claude/settings.json` блокируется permission-слоем («settings files are protected»);
в интерактиве это обычный approve. Цена доставки аудита: always-on ~211 → ~530 tok.

## Затронутые файлы
- `~/.claude` (dot-claude 6036560) — git mv 4 файлов внутрь плагина, README,
  operator-playbook.md, external-audit.md (frontmatter + шаги 1–2), оба манифеста v1.2.0
- `.claude/audits/t1-smoke/` — T1-REPORT.md + 10 логов-провенансов (lab)
- `.claude/progress/standard-v1.md` — Phase 2 закрыта 3/3, T1 done, R5/R6 closed, Session 4

## Проверка
- `claude plugin validate` плагина и marketplace — ✔ оба (после фикса frontmatter).
- Re-smoke v1.2.0 на чистом CFG3: inventory Skills 2 / Agents 3 (лог 09).
- Runtime-опрос `claude --print` на plugin-only профиле: команда и 3 agent-типа видны (лог 08).
- Основной профиль: `claude plugin details` (source @skills-dir) несёт external-audit + 3 роли (лог 10).

## Related
- #84 — R4/R6 + v1.1.0: этот entry закрывает отложенную там упаковку
- #83 — Phase 1 (playbook, /external-audit формализован)
