---
id: 23
date: 2026-05-11
title: "Headless-runner infrastructure + classifier constraint finding"
tags: [feature, harness]
status: complete
---

# Headless-runner infrastructure + classifier constraint finding

## Контекст

Запрос: возможность тестировать harness наработки на external projects (e.g. FastApi-Base) и замерять качество через benchmark. Без real headless invocation Tier 1 остаётся scaffolding-only (`run-tier1.sh` только validates structure).

`claude --help` verified: `--print --output-format json --add-dir <dir> --no-session-persistence` все доступны на OAuth-подписке (no `--bare`). Trivial smoke `claude --print "say pong"` отработал за 1.85s, $0.19 cost — большая часть в `cache_creation` (30K tokens base context).

## Изменения

### 1. `.claude/benchmark/headless-runner.sh` (~130 строк bash)

End-to-end pipeline: clone fixture → optional harness inject → `claude --print` on clone → parse JSON metrics → optional pytest judge → write structured report → cleanup. Trap-based cleanup гарантирует removal `/tmp/bench-*` даже при failure.

Args:
- `--task <yaml>` — task definition (id + single-line prompt)
- `--fixture <dir>` — project path; cloned, не модифицируется
- `--report <path>` — output JSON; default `.claude/benchmark/reports/<task>-<fixture>-<ts>.json`
- `--no-inject-harness` — use fixture's own `.claude/` instead of ours
- `--no-judge-pytest` — skip post-run pytest verification
- `--timeout-sec` — wallclock cap (default 900)
- `--permission-mode` — Claude session permission mode (default `acceptEdits`)

Captured metrics: `num_turns`, `total_cost_usd`, `usage.{input,output,cache_creation,cache_read}_tokens`, `stop_reason`, `files_changed` (git status delta), `pytest.{status,reason}`, `result_excerpt` (1000 chars). Все в одном JSON report.

### 2. `tier1/tasks/T03-fastapi-health-endpoint.yaml`

Task adapted под FastApi-Base patterns: добавление `/health` endpoint + httpx AsyncClient integration test. Baseline_notes documents fixture pre-state (Python 3.12, FastAPI 0.115, async SQLAlchemy, no `/health` route).

## Empirical finding: classifier гарантированно блокирует nested spawn

Попытка demo run на FastApi-Base заблокирована Claude Code auto mode classifier с обоими permission modes:

| Permission mode | Classifier verdict |
|---|---|
| `bypassPermissions` | Blocked: "Spawning nested autonomous Claude session ... creates unsafe agent loop with approval gates disabled" |
| `acceptEdits`       | Blocked: "Spawning nested autonomous Claude session ... without explicit user authorization for autonomous edits in that mode" |

Verdict классификатора: in-conversation AskUserQuestion ответ **не considered durable authorization**. Требуется либо:
- Durable allow rule в `.claude/settings.local.json` (gitignored, project-local), либо
- Standalone terminal invocation вне `claude` interactive session, либо
- Disable auto mode

**Это структурное ограничение**, не bug в runner: classifier защищает от ситуации, когда long-running interactive session spawns autonomous agents которые могут drift outside user attention. Понимание: full Tier 1 automation **из interactive harness session невозможна** без settings change; manual или scheduled invocation — yes.

## Затронутые файлы

- `.claude/benchmark/headless-runner.sh` — new (130 lines, executable)
- `.claude/benchmark/tier1/tasks/T03-fastapi-health-endpoint.yaml` — new

## Проверка

- `bash -n headless-runner.sh` → SYNTAX_OK
- `claude --print "say pong"` → JSON output verified, cost ≈ $0.19 baseline
- Demo run T03/FastApi-Base → **blocked classifier** (any permission-mode); empirical evidence captured here

## Пути forward для real demo

1. **Manual run** (recommended for one-off): standalone terminal, без interactive `claude` session — classifier не вмешивается:
   ```bash
   bash .claude/benchmark/headless-runner.sh \
       --task .claude/benchmark/tier1/tasks/T03-fastapi-health-endpoint.yaml \
       --fixture /home/nikita/PROJECTS/FastApi-Base \
       --permission-mode bypassPermissions
   ```

2. **Durable allow rule**: добавить в `.claude/settings.local.json` (gitignored):
   ```json
   {"permissions": {"allow": ["Bash(bash *headless-runner.sh:*)"]}}
   ```
   После этого harness-internal invocation работает; user должен explicitly opt-in.

3. **Cron/scheduled**: `headless-runner.sh` запускается из cron — спавнится вне interactive session, classifier irrelevant. Подходит для nightly bench.

## Отложено / не сделано

- **Real cost/turns/tokens baseline для T03** — deferred до manual или authorized run; pre-built infrastructure ready
- **`--max-budget-usd`** в runner — API-only флаг, out of scope
- **Tier 1 polyglot tasks (T04-T07)** — добавляются по мере real benchmarking needs

## Related

- #21 — benchmark infrastructure foundation
- #22 — stop-validation расширение (этот runner будет питать его метрики при real runs)
