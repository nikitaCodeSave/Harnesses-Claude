---
id: 94
date: 2026-06-11
title: "External-audit debt fold: kit v1.6.1"
tags: [canon, plugin, release, d-cycle, devlog-skill]
status: complete
---

# External-audit debt fold: kit v1.6.1

## Контекст
Оператор прогнал `/external-audit` на harness-refresh коммите dialog_analyzer (c6902fa) —
первый боевой запуск 3-ролевого аудита вне лаборатории. Вердикт confirmed_with_debt;
два minor-долга оператор принёс в лабораторию:
1. Обоснование удаления code-reviewer ссылалось на `/code-review`, которого в окружении
   нет — плагин в `~/.claude/plugins/blocklist.json` (доступен только `/review`).
2. Регенерация git-tracked `index.json`/`tldr.md` зависит от внерепозиторного
   `~/.claude/skills/devlog/rebuild-index.py` — teammate/CI без user-слоя не выполнит README.

## Закрыто в проекте (dialog_analyzer, uncommitted — коммит за оператором)
- devlog #24: формулировки `/review`/`/code-review` → `/review` + явная оговорка про
  blocklist; README devlog: зависимость задокументирована как осознанная machine-local
  (solo-проект) + рецепт vendor-копии при появлении teammate/CI; progress-долги 3/4
  отмечены закрытыми с воспроизведением.

## Закрыто в каноне
- **kit v1.6.1** (native-capabilities, Code review): review-поверхности profile-dependent —
  bundled-плагины блоклистятся per-user; проверяй наличие в живой сессии до remediation
  (применение существующего инварианта detect-then-prescribe, не новое правило).
- **devlog-skill**: «копировать скрипт не нужно» уточнено — осознанная machine-local
  зависимость для solo; исключение teammate/CI → vendor-копия в
  `<project>/.claude/devlog/`, project-копия приоритетна как pin.

## Не тронуто
Долги 1–2 аудита (undeclared monthly_run_brainstorm.md в коммите; untracked REVIEW.md) —
операторские решения, остаются в progress проекта авторской сессии.

## Verify
Blocklist воспроизведён (`code-review@claude-plugins-official`); grep подтверждает новые
формулировки; JSON plugin/marketplace валидны = 1.6.1; tag `claude-code-harness--v1.6.1`.
Боевой вывод: external-audit → progress-items → fold в канон — полный цикл Регламента
отработал на чужом проекте впервые.
