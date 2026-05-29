---
id: 56
date: 2026-05-29
title: "system-guard simplified to DENY-only"
tags: [refactor, harness, hooks]
status: complete
---

# system-guard simplified to DENY-only

## Контекст
Сразу после hardening (#55) оператор: «system-guard можно упростить — модель умная, очевидно
опасное не сделает; хук скорее формальность + дополнительный контроль». Это согласуется с central
principle (минимум обвязки под Opus 4.8) и с пережитым в этой сессии трением (ASK на каждый `rm`,
ложные DENY до фикса). Выбор оператора: **DENY-only + sudo LOG** (из 3 опций: DENY-only / DENY+edit-
защита секретов / удалить целиком).

## Изменение (GLOBAL `~/.claude/hooks/system-guard.sh`)
Убраны ВСЕ ASK-тиры:
- Bash ASK (любой `rm`, `systemctl stop/disable/mask`, `docker rm/rmi/prune`, `compose down -v`,
  `apt upgrade`, `reboot/shutdown`) — удалён.
- Edit/Write ASK (правки `/etc` · `/boot` · `/usr` · `/sys` · sudoers · passwd/shadow · `~/.ssh`)
  — удалён.

Оставлен твёрдый пол:
- **DENY** (катастрофика, необратимое): recursive `rm` корня/glob-root/home (закалённый `is_rm_root`
  из #55), `mkfs`, `dd of=/dev/*`, redirect `> /dev/sd|nvme|vd`, fork bomb, `--no-preserve-root`,
  запись на NTFS/Windows-mount.
- **LOG**: sudo-аудит в `~/.claude/sudo-audit.log` (non-blocking).

Reversible-but-risky середину теперь держат нативная осторожность модели + `permissions` в
settings.json (см. `~/.claude/CLAUDE.md §7`: project-danger → `permissions.deny`).

## Проверка
`.claude/benchmark/audit/test-system-guard.sh` обновлён под DENY-only семантику: бывшие ASK-кейсы
теперь ассертят `safe` (passthrough), катастрофика остаётся `deny`, regression-инвариант (hyphen-word
вроде `system-guard` НЕ даёт ложный DENY) сохранён. **29/29 GREEN**, `bash -n` OK.

## Реверсивность (blast radius: global)
`~/.claude` не под git. Откат = восстановить ASK-блоки (полная версия зафиксирована в git-истории
этого репо до #55 в `.claude/hooks/session-context.sh`-соседстве — нет; точная pre-simplification
версия описана здесь + в #55). Изменение монотонно ослабляет гейтинг (меньше блокировок), не
ужесточает — риск только в недополученном confirmation-prompt'е на reversible-операциях.

## Затронутые файлы
- `~/.claude/hooks/system-guard.sh` (GLOBAL, упрощён)
- `.claude/benchmark/audit/test-system-guard.sh` (обновлён под DENY-only)

## Related
- #55 — hardening (этот #56 его частично откатывает по объёму: ASK убран, но закалённый DENY-матчер
  сохранён — обе работы консистентны, фикс false-positive остаётся ценным и в DENY-only).
- `~/.claude/CLAUDE.md §7` (guardrails) — машинный пол + реактивный per-project deny.
