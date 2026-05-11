---
id: 29
date: 2026-05-11
title: "Ralph Loop operator review — 7 accept, 6 reject"
tags: [adr, harness, cleanup]
status: complete
---

# Ralph Loop operator review — 7 accept, 6 reject

## Контекст

Ralph Loop (39 итераций, ~4ч wall-clock, $72.50) завершился штатно — `RESULT:NOOP empty-backlog` на iter-0038, `PAUSED.md` записан. На момент остановки в `.claude/loop/proposals/` накопилось **13 pending PROPOSAL-диффов** против protected-файлов, ожидающих человеческого ревью. Operator review session: solo-dev предпочтение «свободного конфига» (меньше Claude-control surface, минимум возврата к усложнённому corpus.yml-тюнингу) определило решения.

Артефакты ревью: `.claude/loop/REVIEW_RESULTS.md` (top-level summary) + `.claude/loop/proposals/DIGEST.md` (per-diff анализ с risk-class и recommended decision).

## Изменения

**ACCEPT (7) — применено в main**:

- **H-011** retire `.claude/hooks/dangerous-cmd-block.sh` — PreToolUse Bash-hook (91 строка).
- **H-012** retire `.claude/hooks/secret-scan.sh` — PreToolUse Edit|Write|MultiEdit (78 строк).
- **H-014** retire `.claude/hooks/auto-format.sh` — PostToolUse (39 строк, удалена вся PostToolUse секция).
- **H-016** consolidate `.claude/docs/workflow.md` + `multi-agent.md` — net -49 строк, single source of truth для spawn policy (docs-discipline rule 2).
- **H-020** extract API constraint из `CLAUDE.md` в `.claude/rules/api-constraint.md` — CLAUDE.md as indexer.
- **H-021** `retire_bias.every_k_iter` 5→3 — фиксит scheduling collision с `holdout_cadence=5` (retire-bias никогда не срабатывал в одиночку под k=5 из-за holdout precedence).
- **H-028** stale-backlog breaker — новая Phase 2 picker rule 4 в `PROMPT.md`: 3 REJECT'а подряд → `RESULT:NOOP backlog-stale-3-consecutive-rejects`.

**REJECT (6) — статус записан в `backlog.md`**:

- **H-018** opt-in `LOOP_STASH_DIRTY` в `run.sh` — добавляет ceremony без observed need; uncommitted-state между iter'ами intentional.
- **H-022** `sigma_multiplier` 2→1.5 — отложено. iter-0035 bipolar variance outlier (CV tokens 35.4%) делает σ-tightening опасным без baseline refresh.
- **H-023** `subagent_cap` 3→1 — foreclosure CLAUDE.md spawn policy (б) parallelism; cap=3 эмпирически ни разу не был достигнут — change performative.
- **H-024** `holdout_cadence` 5→7 — wrong direction после iter-0035: holdout единственный signal channel по invocation-level noise, его частоту нужно сохранять или повышать, не снижать.
- **H-025** `weighted_score_delta_max` 0.20→0.15 — та же логика что H-022; tighter accept gate небезопасен на инфлированной σ-baseline.
- **H-029** devlog auto-entry on ACCEPT — параллельный audit channel к `journal.md` добавляет runtime cost и failure surface; если нужно — offline `journal-to-devlog` rollup правильнее.

**Сопутствующая гигиена**: `CLAUDE.md` Reference materials list почищен от stale-ссылок на `deliverable-planner` агент (retired iter-0016 H-013) и три ретайренных хука. `RUN.pid` / `RUN.started` (stale-артефакты от запуска) удалены. 13 processed `.diff` файлов в `proposals/` удалены (документация решений живёт в backlog.md / journal.md / DIGEST.md).

**Метрики**:

| Метрика | До | После |
|---|---|---|
| Active extension surface | 12 (2 agents + 7 hooks + 2 skills + 1 cmd) | **9** (2 + 4 + 2 + 1) |
| Active PreToolUse hooks | 3 (Bash + 2× Edit/Write) | **1** (loop-protected-guard) |
| Active PostToolUse hooks | 1 | **0** |
| CLAUDE.md длина (строк) | 119 | **112** |
| Pending PROPOSALs | 13 | **0** |

Loop остаётся на паузе. Перед перезапуском требуется пополнение backlog'а (минимум H-031 backlog-validator для закрытия stale-rationale class — 3 из 4 REJECT'ов в прошедшем прогоне).

## Затронутые файлы

- `.claude/settings.json` — hooks section trimmed (3 entries удалены)
- `.claude/hooks/dangerous-cmd-block.sh`, `secret-scan.sh`, `auto-format.sh` — удалены
- `.claude/CLAUDE.md` — API constraint section condensed, reference materials list refreshed
- `.claude/rules/api-constraint.md` — новый файл (25 строк, structured Out-of-scope + Перенос концепций)
- `.claude/docs/workflow.md`, `.claude/docs/multi-agent.md` — консолидация
- `.claude/loop/corpus.yml` — `retire_bias.every_k_iter: 5 → 3`
- `.claude/loop/PROMPT.md` — новая picker rule 4 «Stale-backlog breaker»; Normal renumbered 4→5
- `.claude/loop/backlog.md` — 13 status flips proposed → accepted/rejected
- `.claude/loop/journal.md` — operator-review-session entry
- `.claude/loop/MONITOR.md` — добавлен в tracked (был untracked с запуска)
- `.claude/loop/REVIEW_RESULTS.md` — top-level summary review session
- `.claude/loop/proposals/DIGEST.md` — per-diff анализ с recommended decisions
- `.claude/loop/proposals/REVIEW.md` — auto-regenerated (0 pending)

## Проверка

- `bash .claude/benchmark/static-checks.sh` → **14/14 pass** (включая Tool-gating ≤ 20 → 9 active)
- `python3 -c "import json; json.load(open('.claude/settings.json'))"` → OK
- `python3 .claude/loop/proposals-review.py` → `REVIEW.md regenerated (0 pending)`
- `git log --oneline 55cb642..HEAD` → 4 atomic commits (`3a8786e`, `3533763`, `583fe16`, `77ccb2e`)
- Manual: harness self-load в новой Claude Code сессии — Tier-0 hook chain (loop-protected-guard + stop-validation + session-context) интактен.

## Related

- #28 — loop iter-0001 first ACCEPT readiness (предыдущая запись, до основного 39-iter прогона)
- `.claude/loop/REVIEW_RESULTS.md` — детальный разбор всех 13 диффов и discovered patterns (stale-rationale class, INJECT_HARNESS files-inflation, iter-0035 bipolar variance)
- `.claude/loop/proposals/DIGEST.md` — per-diff recommended decisions с обоснованием
- `.claude/loop/backlog.md` — окончательный статус H-001..H-030 (13 accepted + 13 accepted-via-review + 4 rejected-by-loop + 6 rejected-by-operator)
