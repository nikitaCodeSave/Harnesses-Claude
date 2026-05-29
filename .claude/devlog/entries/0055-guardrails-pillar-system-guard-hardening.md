---
id: 55
date: 2026-05-29
title: "Guardrails pillar — system-guard hardening"
tags: [feature, harness, hooks, security]
status: complete
---

# Guardrails pillar — system-guard hardening (tests + false-positive fix)

## Контекст
Третий столб practice-слоя (после methodology #53, continuity #54): **guardrails**. Открытие при
разведке: глобальный baseline **уже существует** — `~/.claude/hooks/system-guard.sh` (PreToolUse,
3 tier: DENY катастрофика / ASK рискованное-обратимое / LOG sudo-audit). Значит «полная реализация»
guardrails = НЕ новый спекулятивный хук (это была бы теория), а **сделать существующий guard
надёжным**: у него не было ни одного теста, и в этой же сессии он дал **false-positive**.

## Эмпирический триггер (не теория)
`system-guard` дважды заблокировал безобидные multiline-команды как DENY «Catastrophic». Root cause
из кода: рекурсивный флаг `rm` детектился регуляркой `-[a-zA-Z]*r` по **всей** строке → слово
`system-guard` содержит `-guard` (`-`+`gua`+`r`) → matches. Любая команда со словом вроде
`system-guard`/`--dry-run`/`feature-branch` + любой `rm` + любой `~/` или ` / ` → ложный DENY.
(Committer-агент независимо словил то же на commit-message с heredoc — широкий класс.)

## Изменения
1. **`.claude/benchmark/audit/test-system-guard.sh`** (new, в репо) — поведенческий тест guard'а:
   crafted PreToolUse JSON на stdin (не через реальный tool-call — иначе триггер-паттерны в моей же
   командной строке блокируются), ассертит tier (deny/ask/safe). 29 кейсов: DENY катастрофика,
   ASK рискованное, SAFE, regression false-positive, Edit protected-paths.
2. **`~/.claude/hooks/system-guard.sh`** (GLOBAL) — `is_rm_root()` рекурсивный матчер ужесточён:
   флаг теперь **токен на границе** (line-edge / whitespace / quote), ловит `-r` И `-R`, и
   quoted-флаги. Регулярка вынесена в `rec_re`-переменную (безопаснее с кавычками).

   Оригинал (для реверса): `[[ "$c" =~ (-[a-zA-Z]*r|--recursive) ]] || return 1`

## Независимая проверка (security-reviewer subagent)
Адверсариальный ревью diff'а на catastrophic-evasion поймал ДВА upgrade'а к первой версии фикса:
- **регрессия моего word-boundary фикса**: `rm '-rf' /` (флаг в кавычках) падал DENY→ASK;
- **пред-существующая HIGH-дыра**: `rm -Rf /` / `rm -R /` (заглавная GNU-флаг `-R`) ловилась только
  как ASK — валидная катастрофика мимо DENY.

Обе закрыты combined-фиксом (`[rR]` + кавычки в boundary) — в рамках surgical (та же строка).
Verdict reviewer'а: безопасно мержить, новых evasion-путей не открыто; все DENY-формы сохранены.

## Проверка
- RED→GREEN: 22/1 (regression красный) → фикс v1 → 23/0; +5 кейсов (capital-R + quoted) красные →
  combined-фикс → **29/29 GREEN**. `bash -n` синтаксис OK.
- DENY сохранён для: `rm -rf /`, `-fr`, `-R`, `~`, `$HOME`, `/*`, `~/Downloads`, double-space,
  quoted, `--no-preserve-root`, `mkfs`, `dd of=/dev/*`, fork bomb.

## §7 в `~/.claude/CLAUDE.md` (GLOBAL)
Capstone 3-столбовой модели: machine-guard = пол (не потолок); project-specific danger кодируется
**реактивно** (permissions.deny + «never touch X» в проектном CLAUDE.md), НЕ upfront-интервью
(согласно памяти про contract-interview); mechanical guard > prompt-compliance для необратимого.

## Известные пред-существующие дыры (НЕ чиню — out of scope, отдельные clause'ы)
Reviewer отметил (severity в скобках): `find / -delete` (HIGH), `truncate -s 0 /dev/sda` (med),
`chmod -R 000 /` (med), symlink-swap / `> /dev/disk/by-id/*` (med) — не покрыты guard'ом вообще.
Кандидаты на отдельный follow-up, если решим расширять покрытие.

## Реверсивность (blast radius: global, все проекты)
`~/.claude` не под git. Откат system-guard = вернуть оригинальную строку (выше); откат §7 = удалить
секцию. Изменение протестировано (29/29) и является улучшением безопасности (закрыло HIGH-дыру).

## Затронутые файлы
- `~/.claude/hooks/system-guard.sh` (GLOBAL), `~/.claude/CLAUDE.md` §7 (GLOBAL)
- `.claude/benchmark/audit/test-system-guard.sh` (new, в репо)

## Related
- #53 methodology, #54 continuity — это третий (последний) из 3 столбов practice-слоя.
- Все 3 столба теперь имеют mechanical-компонент (hook) + standing-инструкцию (CLAUDE.md §5/§6/§7).
- Pending: мульти-сессийный бенчмарк practice-слоя (single-shot зануляет ценность); опц. follow-up
  по пред-существующим дырам guard'а.
