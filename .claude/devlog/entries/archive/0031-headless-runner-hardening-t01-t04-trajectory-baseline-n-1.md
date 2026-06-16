---
id: 31
date: 2026-05-11
title: "Headless runner hardening + T01-T04 trajectory baseline (n=1)"
tags: [benchmark, harness, infrastructure, evidence-based]
status: complete
---

# Headless runner hardening + T01-T04 trajectory baseline (n=1)

## Контекст

После P1+P2 (devlog #30) operator дал явное go на smoke-валидацию runner'а под новой stream-json + trajectory методологией и последующий re-prog T01-T04. Smoke выявил 4 проблемы в runner'е, каждая зафиксирована, после чего прогнан 8-run baseline (4 tasks × 2 harness variants). Ключевая находка: **T03 harness-win sign-inversion воспроизвёлся в n=1 (-18% cost, -5 turns, -33% cache_read)** с tool-call breakdown'ом, дающим прямое объяснение mechanism'а.

## Изменения

### Runner fixes (5 шт, в `.claude/benchmark/headless-runner.sh`)

1. **Auto git init для non-git fixtures**. `sample-py-app` не git repo → runner отваливался на fallback `find -newermt`, который считал 10 файлов (cp -r mtime races + auto-memory side-effects). Fix: после fixture clone + harness inject, runner делает `git init && git add -A && git commit` (если `.git` отсутствует). Теперь git status path работает примарно для всех fixtures, accurate file count.

2. **Improved git-status filter**. Untracked `__pycache__/`, `.pytest_cache/`, `.mypy_cache/`, `.ruff_cache/`, `.claude/` (auto-memory subsystem re-creates `.claude/memory/` during runtime даже после inject-time prune) теперь исключены из files_changed. Same filters добавлены в find-fallback path.

3. **Inject pruning**. `benchmark/fixtures/external/` (6MB external repos), `benchmark/reports/`, `loop/`, `memory/`, `plans/`, `worktrees/`, `.cache/` теперь удаляются из CLONE_DIR'а сразу после `cp -r .claude/`. Это ~6+ MB I/O savings per run + reduced context pollution (Claude inside fixture не видит harness's own benchmark / self-improvement state).

4. **Stream-json output switch**. `--output-format json` → `--output-format stream-json --include-hook-events --verbose` (P2 рефактор, реализованный в devlog #30, validated в smoke прогоне). Result event на последней строке carries those же метрики что и старый json format; pre-existing report consumers continue работать через `select(.type=="result") | ...` адаптацию.

5. **Trajectory metrics parsing block**. Подтверждено end-to-end: skills_triggered / subagent_dispatches / tool_calls_summary / invariant_pings / workflow_markers корректно извлекаются. Smoke-test на синтетическом stream-json (5/5 categories), 3 production smoke runs (T01 with progressive fixes), все 8 re-prog runs.

### Cleanup intermediate smokes

3 smoke iteration reports (`smoke-T01-ourharness-traj{,-v2,-v3}.json`) удалены после re-prog — содержали intermediate runner state с fixes-in-progress. Финальные 8 reports под единым timestamp под единым (fully fixed) runner состоянием.

## T01-T04 trajectory baseline (n=1)

Все 8 runs прошли: exit=0, pytest=pass, files_changed accurate (2 везде кроме T04=3). Полный отчёт + per-cell данные → `.claude/benchmark/reports/2026-05-11-p2-trajectory-baseline/summary.md`.

### Per-cell deltas (our-harness vs no-harness)

| Cell | Δ cost | Δ turns | Δ cache_read | Status |
|---|---:|---:|---:|---|
| T01 sample | **+40.0%** | +1 | +39.5% | overhead (toy/terse, no ROI zone) |
| T02 sample | +11.5% | −1 | +5.5% | noise / marginal overhead |
| T03 fastapi | **−18.2%** | **−5** | **−32.7%** | **harness ROI confirmed** |
| T04 fastapi | −4.1% | −1 | −1.9% | noise (explicit spec) |

**Pattern reproduces «harness ROI ∝ ambient exploration cost»** (devlog #24-25, user memory). T03 sign-inversion в range предыдущего 4×4 [-30%, +6%] median −24% → direction stable, magnitude consistent.

### T03 mechanism — tool-call breakdown

| Variant | Total | Bash | Read | Glob | Edit | Write |
|---|---:|---:|---:|---:|---:|---:|
| no-harness | 17 | 8 | 4 | **2** | 1 | 1 |
| our-harness | 12 | 5 | 4 | **0** | 1 | 1 |

**Direct evidence**: harness preload (CLAUDE.md indexer + `.claude/docs/` reference) replaces 2 Glob + 3 Bash exploration calls. Claude with harness knows project structure, doesn't grep/glob interactively. Это материализация Addy Osmani'но тезиса «the gap is largely a harness gap» — для exploration-heavy tasks gap ≈ saved-exploration-cost.

### Layer C trajectory data — uniformly silent

Across all 8 runs: skills=[], subagents=0, invariant_pings=0, plan_emitted=false, review_emitted=false. **Это информативный сигнал**, не отсутствие сигнала:

1. **Skill auto-trigger не работает на этих 4 tasks**. Ни `devlog`, ни `project-docs-bootstrap` ни разу не triggered. Tasks не содержат trigger keywords. Это data point для будущего P4/P6 — нужны task'ы которые **явно должны** trigger skills, чтобы измерять accuracy. Соответствует community evidence (skills alone ~20% trigger rate без hook-reinforcement, per Scott Spence eval).

2. **Subagent discipline: perfect**. 0 dispatches across 8 runs validates CLAUDE.md «spawn fewer subagents» policy под Opus 4.7. Over-delegation flag = 0 везде.

3. **Invariant pings: 0**. Claude не предлагал forbidden patterns (`ANTHROPIC_API_KEY`, `--bare`, `managed-agents`, `--no-verify`). api-constraint behaviorally validated на benign tasks; honeypot/adversarial probing — задача P4.

4. **Workflow markers: false везде**. В `claude --print` one-shot mode Plan→Work→Review структура не эмержит из preload'а workflow.md сама по себе. Expected: workflow.md описывает interactive multi-turn workflow. Marker imeет смысл в multi-turn benchmarks (P6), not here.

### Notable findings

- **AskUserQuestion tool вызван Claude в `--print` mode** (T03/T04, обе variants). В headless нет user'а → Claude получил empty response и продолжил с defaults. Worth investigating: правильно ли это используется? Potential over-cautious pattern.
- **Cache_read sıkı correlates с cost** (R≈1.0 в этом dataset). Most cost driven by context size, not output. Подтверждает Addy Osmani «context window utilization» proxy thesis.
- **T01 +40% overhead больше предыдущего +24%** — single-run variance plausible; n=3 чтобы confirm. Direction stable.

## Метрики работы

- Runner growth: 301 → 333 строки (+32 за 5 fixes).
- 8 OAuth runs total. Total cost: $2.78 USD. Wall: ~7 минут sequential.
- Stream-json files per run: ~10-50 KB. Cleanup via `trap cleanup EXIT` — no clone files persist.
- Layer A static-checks: 14/14 pass после всех изменений.

## Решения / trade-offs

1. **n=1 baseline acceptable**: первый прогон новой методологии валидирует **инфраструктуру**, не numerical claim'ы. Per Layer D protocol, любой harness change with numerical claim требует n=3 minimum + bracket reporting + sign-inversion gate. Этот run — info-only, не conclusion.

2. **Стратегия cleanup intermediate smokes**: 3 smoke iterations (v1/v2/v3) удалены вместо архивирования. Они представляют runner с known bugs (10 files_changed, 4 files_changed, 3 files_changed) — bench reports должны быть credible point-in-time snapshots. Finальные 8 reports — единственный valid baseline под current runner.

3. **Inject pruning consensus**: удалить `loop/`, `memory/`, `plans/` агрессивно потому что эти dirs **никогда** не нужны Claude'у внутри benchmark fixture'а (это harness's own state, не project knowledge). `benchmark/fixtures/external/` особенно явный — 6MB unrelated repos.

4. **AskUserQuestion observation не actionable сейчас**: noted, but требует separate investigation про headless-mode handling. Не блокирует current benchmark methodology.

## Связь

- Devlog #30 — P1+P2 source.
- Devlog #24, #25 — original 4×4 T03 sign-inversion evidence (median −24%), variance protocol genesis.
- `.claude/benchmark/reports/2026-05-11-p2-trajectory-baseline/summary.md` — full report.
- `.claude/benchmark/headless-runner.sh` — hardened runner.
- `.claude/docs/benchmark.md` — Layer A/B/C/D methodology.

## Next

Per roadmap (devlog #30):
- **P3 — `legacy-no-tests` fixture** (operator выбрал в P1+P2 question). Создание fixture: 600 LoC Py2-style mix, no tests, mixed indents — biggest expected ROI zone для harness. Tasks: F-explore + F-ambiguous + R-refactor + M-migration variants targeting modernization scenario.
- **P4 — trip-wire / Neg-invariant tasks**: 5-8 honeypot prompts проверяющих invariants (api-constraint, built-ins-first, CLAUDE.md size, --no-verify). invariant_pings метрика currently always 0 потому что no adversarial task — P4 даст non-zero comparison ground.
- **n=3 enforcement default**: текущий n=1 baseline acceptable как infrastructure validation, но любой proposed harness change нужно прогонять n=3 minimum per cell. Этот discipline пока manual; P5 — protocol-default.
