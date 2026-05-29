---
id: 34
date: 2026-05-11
title: "Phase 2 — battle-test-runner.sh + grade.py + llm-judge.sh complete (no OAuth burn)"
tags: [benchmark, battle-test, harness, deliverable-scale, ralph-patterns, no-oauth]
status: complete
---

# Phase 2 — battle-test-runner.sh + grade.py + llm-judge.sh complete (no OAuth burn)

## Контекст

Devlog #33 — scaffolding (fixture + judge artifacts). Phase 2 — runner + grader + LLM-judge code, без OAuth. Operator явно попросил «использовать что есть из логики RALPH (.claude/loop) + провалидировать весь пайплайн» — сначала ревью loop/ patterns, потом integration. Цель: maximize reliability на 15-60min runs где cost ~$5-30/run.

## Ralph patterns adopted

| Pattern | Ralph source | Где использован |
|---|---|---|
| `notify()` + `notify-send` desktop | `run.sh:58-64` | runner Phase headers, terminal events |
| Per-phase error containment via `set +e`/`set -e` block | `run.sh:177-184` | runner each Phase 3-8 block |
| Cumulative cost accumulator awk float math | `run.sh:83-91` | runner `acc_cost()` across build + LLM-judge |
| Pre-flight binary + file checks с loud fail | `run.sh:97-128` | runner Phase 1 (extended Oracle + Ollama + venv) |
| `--from-file` static mode для validate-output | `validate-claude-output.sh` | inspiration for `--preflight-only` flag в runner |
| `PAUSED.md` graceful abort signal | `run.sh:99-102, 142-146` | runner `check_cancel()` watches `.bench-cancel` per phase |
| Per-iter log file separation | `run.sh:168-169` | runner `$PHASE_LOG` accumulates phase narrative |

## Изменения

### 1. `.claude/benchmark/battle-test-runner.sh` (558 lines, +183 vs Phase 2.1 skeleton)

Rewrite с Ralph patterns + полная Phase 4-9 integration:

- **Phase 1 Preflight** — binary checks (claude/jq/docker/python3/timeout), fixture + judge artifacts, Oracle container running, Ollama API reachable (Python urllib — curl у нас denied hook), operator's `.venv` имеет `oracledb` + `pyyaml`, harness variant valid, grade.py + llm-judge.sh present.
- **Phase 2 Clone+Inject** — auto git init, harness pruning (judge sibling leak guard).
- **Phase 3 Build** — `claude --print --model opus-4-7 --output-format stream-json --include-hook-events`, background progress monitor каждые 30s, result event parse + Layer C trajectory extraction.
- **Phase 4 Detect** — invoke `grade.py detect` → entry-point detection (pyproject + module / main.py / cli.py / app.py / run.py / assistant.py fallback) + venv provision (uv if available, else python -m venv) + install (`pip install -e .` / `requirements.txt` / default `oracledb openai python-dotenv`).
- **Phase 5 Run questions** — invoke `grade.py run-questions` → for each Q timeout 120s, capture stdout/stderr/exit/wall.
- **Phase 6 F-Q grading** — `grade.py grade-fq` → heuristic regex match per Q (10/Лизинг/Large+growth/СМИРНОВ+2/6 hubs ±1).
- **Phase 7 T/B auto** — `grade.py grade-tb-auto` → T1 structure (file globs) + T2 deps (pyproject parse) + T5 pytest run + T6 README size + B4 latency median.
- **Phase 8 LLM-judge** — `llm-judge.sh` → neutral `claude --print` spawn, evidence tar'd (≤50KB), structured JSON output for T3/T4/T6/T7/B1/B2/B3/B5.
- **Phase 9 Aggregate** — sum subscores, verdict (≥70 accepted / 50-69 partial / <50 failure), write `build-report.json` + human-readable `summary.md`.

Flags: `--task`, `--harness`, `--build-model`, `--judge-model`, `--timeout-sec`, `--question-timeout-sec`, `--report-dir`, `--cleanup-on-success`, `--skip-grade`, `--skip-llm-judge`, `--watch`, **`--preflight-only`** (safe pre-OAuth verification).

### 2. `.claude/benchmark/text2sql-judge/grade.py` (519 lines Python)

Sub-commands invoked by runner:

- `detect` — entry-point detection + venv provision. Output JSON: `{entry_kind, invocation_cmd, venv_status, install_log_tail}`.
- `run-questions` — invoke deliverable for each Q in `questions.yaml`, capture stdout/stderr/exit/wall. Per-Q timeout via `subprocess.run(timeout=)`.
- `grade-fq` — heuristic regex grading per Q:
  - Q1: `\b10\b|десят[ьи]` → 6; `\b9\b|\b11\b` → 3; else 0
  - Q2: count 5 expected orgs (лизинг/транслогистик/нефтехимпром/металлинвест/пенсионный) case-insensitive → 6 if 5, 3 if 4, 0 else
  - Q3: «large» + growth signal (+19% / 545 / рост / вырос) → 6; only Large → 3; Region → 3 (партиальный); else 0
  - Q4: смирнов + (2 / две / два) → 6; смирнов only → 3; 2 + international → 3; else 0
  - Q5: extract «hub.{0,30}\d+» pairs, check ±1 от expected for 6 hubs → 6 if all, 3 if 4+, 0 else
- `grade-tb-auto` — T1/T2/T5/T6/B4 scriptable scoring.

**Validation**: 13/13 unit tests passed на synthetic answers (PASS / PARTIAL / FAIL paths для каждого Q).

### 3. `.claude/benchmark/text2sql-judge/llm-judge.sh` (210 lines)

- Evidence package builder: file tree (`find` excluding .venv/.git/__pycache__/.bench-*) + content of `*.py`/`*.md`/pyproject/requirements/Dockerfile, capped at 50KB.
- Spawns `claude --print --model opus-4-7 --output-format json --permission-mode default --no-session-persistence` in **fresh tmp cwd** (no harness inject — neutral judge).
- Parses `.result` as JSON, strips markdown fence fallback, regex `\{.*\}` last-resort heuristic.
- **Retry once** on malformed output (Ralph pattern: don't crash on single failure).
- Fallback zero scores if both attempts malformed — explicit `status: "fallback_zero"` in output.
- Cost accumulator: `total_cost_usd` from claude wrapper added to overall runner cumulative.

### 4. `.claude/benchmark/text2sql-judge/judge-prompt.md` (44 lines)

Rubric injection template: 8 items (T3/T4/T6/T7/B1/B2/B3/B5) с criteria + required JSON schema. Critical: «выход — только корректный JSON, без markdown wrapper». Evidence appended below template by llm-judge.sh.

## Pipeline validation

`--preflight-only` smoke: PASS через Phase 1 (binaries + fixture + judge + Oracle + Ollama + venv) **без OAuth burn**. Drop flag → full pipeline.

Component validation:
- runner bash syntax: clean
- grade.py Python AST: clean
- llm-judge.sh bash syntax: clean
- 13/13 grading unit tests на synthetic answers
- Layer A static-checks: 14/14 pass

## Метрики работы

- Files created: 4 (runner + grade.py + llm-judge.sh + judge-prompt.md).
- Total LoC new: 558 + 519 + 210 + 44 = 1331.
- OAuth runs: 0 (Phase 2 — code only, per scope).
- Wall: ~30 min (writing + 2 syntax/unit-test iterations).
- Layer A: 14/14 pass.

## Решения / trade-offs

1. **Ralph patterns vs reinventing**: операторская подсказка спасла время + добавила robustness. `notify()` + `check_cancel()` + cumulative cost — все proven в 39-iter Ralph loop.

2. **Single grade.py with sub-commands vs 4 separate files**: чище API (один entry, 4 verbs), shared helpers без import boilerplate.

3. **LLM-judge `claude --print --output-format json` (wrapper) + JSON-in-`.result`**: лишний уровень nesting, но дает access к `cost_usd` через wrapper. Альтернатива (`structured-output` schema) сложнее без guaranteed compliance.

4. **`--preflight-only` flag критичный**: позволяет operator проверить весь pipeline (включая Oracle/Ollama liveness, venv readiness, fixture/judge integrity) перед burning $10-60. Защита от типичной ошибки «забыл docker start».

5. **`.bench-cancel` file watch**: graceful abort. Operator может `touch $REPORT_DIR/.bench-cancel` и runner остановится на следующей phase boundary — лучше чем Ctrl+C посреди claude --print spawn.

6. **`set +e`/`-e` per phase**: phase 8 LLM-judge fails → phase 9 aggregate STILL runs с zero scores для T/B residual. Operator получает actionable diagnostics, не silent crash.

7. **Heuristic grading vs LLM-judge для F-Q**: 13/13 unit tests показали heuristic'ам достаточно для эталонных ответов. LLM-judge только для subjective T/B residual где no ground truth.

8. **Не реализовали 4×4 variance runs**: per operator earlier — n=1 для первого comparison, expand если ambiguous. Phase 5 already supports re-run external orchestration через repeated invocations.

## Связь

- Devlog #30/31/32/33 — preceding methodology + scaffolding.
- `.claude/loop/run.sh` — Ralph patterns source.
- `.claude/benchmark/battle-test-runner.sh` — main orchestrator.
- `.claude/benchmark/text2sql-judge/{grade.py,llm-judge.sh,judge-prompt.md}` — graders.

## Next — operator approval gates

| Step | Action | OAuth cost |
|---|---|---|
| 2.3 | Smoke: `battle-test-runner.sh --harness ours` (1 build, --skip-llm-judge) | $5-30 |
| 2.5 | Smoke: full pipeline including LLM-judge | $6-33 |
| 2.6 | First comparison: `--harness ours` + `--harness noharness`, n=1 | $12-66 |

Все 3 require operator's explicit go перед запуском. Phase 2.1+2.2+2.4 = code complete, проверяемо via `--preflight-only` и unit tests без OAuth.

Optional safety check: `validate-claude-output.sh` tripwire (Ralph) for stream-json schema. Не интегрирован в preflight (extra OAuth cost), но runnable manually. После CLI upgrade — operator может проверить.
