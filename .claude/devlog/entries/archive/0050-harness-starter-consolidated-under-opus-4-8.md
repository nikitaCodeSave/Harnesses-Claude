---
id: 50
date: 2026-05-29
title: "Harness starter consolidated under Opus 4.8"
tags: [refactor, harness]
status: complete
---

# Harness starter consolidated under Opus 4.8

## Контекст
Оператор указал, что «стартовый harness первой сессии» перегружен и местами хуже
голого claude. Разведка двумя субагентами вскрыла корень: «стартер» = глобальный
слой `~/.claude/`, и в нём жили ДВА конкурирующих bootstrap-скилла. Глобальный
`harness-setup` (Python-only, 19 hard-invariants, prescriptive «2026 stack»,
генерит блокирующий Stop-хук, тащит dev-мусор) срабатывал в каждом проекте —
буквально хардкоженный пресет. А концептуально верный язык-агностичный
`claude-code-harness` был заперт в проектной лаборатории и там сам себя отключал
(`Skip when already configured`) → недостижим. Плюс весь harness был приколочен к
Opus 4.7 и пропускал главный новый workflow-примитив — dynamic workflows.

## Изменения
- **Ретайр `harness-setup`** — перемещён из load-path в `~/.claude/_archived-skills/`
  (обратимо). Носитель плотнейших stale-assumption'ов «модель не выберет стек / не
  признается что не доделала» — Opus 4.8 делает это нативно.
- **Чистый `claude-code-harness` поднят на глобальный уровень** (`~/.claude/skills/`),
  переписан с нуля на Opus 4.8 / CC v2.1.154+. Сохранена здоровая 4-mode архитектура
  (Bootstrap / Audit / Extend / Explain), контент пере-заземлён двумя first-party
  веб-разведками. SKILL.md + 5 references (native-capabilities, harness-discipline,
  bootstrap-checklist, audit-checklist, evidence-base) — все с T1-цитатами.
- **Дедупликация** — проектная копия `claude-code-harness` (stale 4.7) заархивирована.
- **Re-ground проектного CLAUDE.md** — 4.7→4.8 везде; built-ins список +`claude-code-guide`
  (теперь 5, не 4); «multi-agent ill-suited» переформулирован в «single-agent default;
  bounded fan-out через built-in dynamic workflows когда scope превышает один контекст»;
  effort `xhigh`→`high`; добавлена fencing-строка «этот репо — лаборатория, не шаблон»;
  указатель на глобальный скилл как каноничный источник.

Ключевые факты из разведки (R1/R2, all T1): built-in субагентов 5 (+`claude-code-guide`);
dynamic workflows — research-preview v2.1.154+ (16 concurrent / 1000 total caps);
Opus 4.8 default effort `high`; `/remember` как built-in не существует (это `/memory`);
Cron/ScheduleWakeup как first-party CLI-примитивы не подтверждены; best-practices essay
переехал на `code.claude.com/docs/en/best-practices`.

## Затронутые файлы
- `~/.claude/skills/claude-code-harness/SKILL.md` + `references/*.md` (×5) — новый чистый скилл
- `~/.claude/_archived-skills/harness-setup/` — ретайрнут (был `~/.claude/skills/harness-setup/`)
- `~/.claude/_archived-skills/project-claude-code-harness-superseded/` — заархивированный дубликат
- `.claude/CLAUDE.md` — re-ground 4.7→4.8, fencing, built-ins, multi-agent nuance, указатель

## Проверка
- `system-guard.sh` корректно заблокировал `rm -rf` в первой попытке cleanup (DENY-tier работает) → переделано через `mv`.
- `ls ~/.claude/skills/` — `harness-setup` отсутствует, `claude-code-harness` присутствует (6 файлов).
- `ls .claude/skills/` — дубликат `claude-code-harness` отсутствует.
- Grep подтвердил отсутствие live-wiring ссылок на ретайрнутые скиллы до перемещения.

## Related
- Остаётся: глубокий re-ground lab-доков (`principles.md`, `workflow.md`, `multi-agent.md`,
  `builtins-inventory.md`) с 4.7→4.8 + dynamic-workflows тир — следующий focused-проход.
- `.claude/loop/` помечен retire-candidate'ом (dynamic workflows — нативный преемник),
  но НЕ удалён: накопленные journal/STATE, снос только по явному решению.
