---
id: 76
date: 2026-06-09
title: "Sync canonical claude-code-harness skill with factory knowledge"
tags: [harness, docs]
status: complete
---

# Sync canonical claude-code-harness skill with factory knowledge

## Контекст
После prune глобальных skills (#75) — проверка: соответствует ли глобальный канон `~/.claude/skills/claude-code-harness/` последнему выводу «фабрики» (devlog #70–#75). Аудит выявил, что survivors (devlog/grill/tdd) конформны (tdd даже точно совпал с де-догматизированным §5), но **references канона отстали**. Замыкаю петлю «фабрика → шиппнутый канон» — его собственная Maintenance-дисциплина.

## Изменения
Аудит провёл **fresh-context критик (§8)** — обе мои гипотезы CONFIRMED + поймал over-stuffing-риск (что НЕ добавлять). Правки по его remediation-таблице (~10 строк, не rewrite):

- `evidence-base.md`: добавлены 2 **T1** июньских источника — «A harness for every task» (каноничный first-party для `ultracode`/dynamic-workflows — самый routed-to примитив скилла, citation отсутствовала) и «Harness Design for Long-Running Apps» (grounds P→G→E + headline strip-scaffolding quote). Добавлена таксономия 3 failure-mode (laziness/self-preferential bias/goal drift) как grounding для «fresh-context Evaluator ≠ self-recheck». Harness-Bench (2605.27922) — 1 строка в re-grounding note. Стамп → 2.1.169.
- `audit-checklist.md` §5: добавлен **эмпирический метод разрешения** stale-предположения (был только детект, не disposition): disable (`--safe-mode`/remove) → re-run representative task → retire on evidence-of-no-lift, judge свежим контекстом. Это дистилляция метода из #74 (НЕ полный A/B-протокол — он остаётся lab R&D). Стамп → 2.1.169.
- `bootstrap-checklist.md`: убран dangling lab-local `/critique` → «fresh-context reviewer (subagent or new session)» + parenthetical про self-preferential bias.
- `harness-discipline.md`: стамп → 2.1.169.

**Over-stuffing guard соблюдён** (по критику): НЕ добавлены surveys EMBER/externalization/code-as-harness (lab-память метит их method-out-of-scope), полный A/B-протокол, quarantine-принцип (single-incident). Канон остался lean.

## Затронутые файлы
- `~/.claude/skills/claude-code-harness/references/{evidence-base,audit-checklist,bootstrap-checklist,harness-discipline}.md` (вне git — глобальный слой)

## Проверка
- Свежий слепой критик (general-purpose, §8): H1/H2 CONFIRMED по диску + over-stuffing guard.
- Post-edit grep: 2 T1-поста добавлены; failure-modes в evidence+bootstrap; retire-метод в audit (3 hits); `/critique` = 0; 3 «grounded-for» стампа → 2.1.169 (оставшиеся 2.1.154 — корректная feature-availability provenance в native-capabilities). Запретные термины не просочились (grep-хиты — false positive на «remember»).

## Related
- #74/#75 — источник метода (staleness A/B) и контекста (prune)
- #71 — fresh-sources intake (откуда июньские T1-посты)
