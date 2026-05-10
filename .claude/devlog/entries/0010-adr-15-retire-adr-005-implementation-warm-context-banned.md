---
id: 10
date: 2026-05-10
title: "ADR-15 retire ADR-005 implementation warm context banned"
tags: [adr, harness, cleanup]
status: complete
supersedes: 5
---

# ADR-15 retire ADR-005 implementation warm context banned

## Контекст

Внешний агент-ревью (transcript этой сессии) выявил, что ADR-005 «берём три» (managed Memory/Dreams port-over: `_manifest.yml`, PreToolUse exit 2 на RO-store, SessionStart hook со списком stores) принят 2026-05-09, но через сутки ни одна из трёх капабилити не материализована. Параллельно в обсуждении возникло встречное предложение — skill/command «warm-context» для прогрева контекста на старте сессии. Stress-test обоих предложений через foundational principle показал: managed-memory port-over распределён по существующим built-in примитивам (auto-load `.claude/rules/`, auto-memory типизация, gitStatus inject, active inventory pattern), а warm-context — компонент с N=0 эмпирических промахов и assumption «модель не знает где найти контекст», уже снятым нативно (Opus 4.7 «reasons more, calls tools less often», 5 источников auto-loaded в системный prompt).

## Изменения

ADR-15 в `docs/HARNESS-DECISIONS.md` зафиксировал двойной запрет:

1. Локальная имплементация managed Memory/Dreams (`_manifest.yml`, store-ACL hooks, dreamer pipelines) запрещена без empirical evidence что built-in auto-load + auto-memory + `permissions.deny` недостаточны.
2. Skill/command типа `warm-context` / `recall` / `prime-session` запрещён без N≥3 эмпирических случаев, где auto-loaded источники недостаточны И prompt «дай overview» не покрывает потребность. Slash command как тонкий prompt-template — допустим после N≥3.

ADR-005 не редактируется (правило лога), но получил status header «SUPERSEDED in part by ADR-15»; out-of-scope-часть про managed-agents API остаётся в силе. Active inventory обновлён: `managed-agents API + локальный port-over (ADR-005/ADR-15)` и явное упоминание `skill/command «warm-context» прогрева сессии (ADR-15)` в out-of-scope-блоке.

Mapping капабилити ADR-005 на built-in покрытие задокументирован таблицей в ADR-15. Verified в текущей сессии: `.claude/rules/testing.md` загружен в системный prompt без явного `Read` (project instructions auto-load), `gitStatus` блок инжектится Claude Code (branch + last 5 commits + status) — это закрывает ADR-010 assumption тем же transcript-доказательством, что использовал ADR-014 для built-in `/init`.

Эффект: ноль кода добавлено или удалено; harness baseline без изменений; добавлен явный методологический guard против двух ad hoc предложений, которые иначе могли бы возродиться в будущих сессиях («давайте всё-таки сделаем _manifest.yml», «давайте сделаем skill для прогрева»).

## Затронутые файлы

- `docs/HARNESS-DECISIONS.md` — добавлен ADR-15, status header в ADR-005, обновлён active inventory.
- `.claude/devlog/entries/0010-adr-15-retire-adr-005-implementation-warm-context-banned.md` — этот entry.

## Проверка

```bash
python3 .claude/devlog/rebuild-index.py
grep -A2 "ADR-15" docs/HARNESS-DECISIONS.md | head
grep "ADR-005" docs/HARNESS-DECISIONS.md
```

Manual review: ADR-15 цитируется в active inventory (out of scope); ADR-005 заголовок содержит status header.

## Related

- #9 — ADR-013/014 + meta-CLAUDE.md процессные правила (предшествующая работа над тем же логом, ADR-13 ввёл auto-memory canonical, который сделал ADR-005 implementation редундантной)
- #2 — v0.1 expansion (исходный контекст, в котором managed Memory port-over идея появилась)
