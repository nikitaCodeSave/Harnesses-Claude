---
id: 30
date: 2026-05-11
title: "Benchmark redesign — 4-layer model + trajectory metrics (P1+P2)"
tags: [benchmark, harness, methodology, evidence-based]
status: complete
---

# Benchmark redesign — 4-layer model + trajectory metrics (P1+P2)

## Контекст

Текущий бенчмарк (3-tier model, 5 задач, 4 fixture-варианта) хорошо ловил token/turn/cost deltas — empirical evidence «harness ROI ∝ exploration cost» (devlog #24-25) получено именно через него. Но методология имела 5 blind spots:

1. **Fixture coverage узкий** — 1 realistic project (FastApi-Base), всё остальное toy. Один axis sampled.
2. **Все task specs explicit** — даже T04 даёт точный путь («place X in Y»). Harness compounding value именно на ambiguous tasks (per Boris Cherny: «give Claude a way to verify» → 2-3× quality).
3. **Trajectory-quality blind spot** — считаем tokens/turns/pass-fail, не считаем: какие skills triggered, был ли уместный subagent spawn, обновил ли Claude docs per discipline rule, появились ли Plan/Review markers.
4. **Нет trip-wire / negative tasks** — harness invariants (api-constraint, built-ins-first, CLAUDE.md size) валидируются только static-чеками. Поведенческая проверка отсутствует: пробует ли Claude нарушить invariant если толкнуть.
5. **Variance ad-hoc, не protocol** — CV=20.8% на нашем harness, 8.7% на baseline (T03 4×4). Single-run reports в основном корпусе — лотерея.

Источники evidence для redesign'а (community + first-party):

- **Anthropic SWE-bench-Verified** — минимальный bash+edit scaffold, real-world Python tasks, fail-to-pass / pass-to-pass criteria. Отделить вклад модели от harness'а — gold standard.
- **Boris Cherny (howborisusesclaudecode.com)** — verification → 2-3× quality. CLAUDE.md как живой регрессионный артефакт. Outcome-based, не metric-based.
- **Addy Osmani «Agent Harness Engineering» (2026)** — формулирует gap: «the gap between what today's models can do and what you see them doing is largely a harness gap», но методики не предлагает.
- **Skill Creator eval (Anthropic, март 2026, 50k+ installs)** — blind A/B Comparator subagent между skill-версиями. Eval-фреймворк теперь штатный.
- **mattpocock/skills, obra/Superpowers** — community баки testing harness'ов через workflow chains.

## Изменения

**P1 — Documentation alignment**:

- `.claude/docs/benchmark.md` переписан с 197 → 146 строк. 3-tier model заменён 4-layer моделью:
  - **Layer A** — static integrity (как было `Tier 0`).
  - **Layer B** — behavioral matrix [fixture × task type]. Заменяет узкий task suite. Введены legend-fixtures spec (toy / fastapi-domain / express / legacy-no-tests / partial-migration / cli-click / monorepo-uv) + 8-типная task taxonomy (F-easy / F-explore / F-ambiguous / B-repro / R-refactor / M-migration / D-docs / Neg-invariant).
  - **Layer C** — trajectory quality (новое): skills_triggered, subagent_dispatches, invariant_pings, workflow_markers, tool_calls_summary. Additive к существующим метрикам, не replacement.
  - **Layer D** — statistical protocol (новое): n=3 minimum, bracket [min,median,max], CV, sign-inversion gate (median outside baseline IQR + ≥2/3 same side).
- `.claude/benchmark/README.md` aligned: quick start, layer-table, trigger matrix updated.
- `.claude/benchmark/reports/README.md` — обновлён JSON schema + aggregate markdown template с обязательным bracket reporting.

**P2 — Trajectory metrics**:

- `.claude/benchmark/headless-runner.sh`: 233 → 301 строк. Изменения:
  - `--output-format json` → `--output-format stream-json --include-hook-events --verbose`. Stream-json захватывает full trajectory (tool_use blocks, assistant text, hook events), result event на последней строке carries existing metrics.
  - Result event parsing адаптирован под stream-json (jq `select(.type=="result") | ... | tail -1`).
  - Добавлен Layer C parsing блок: extract tool_uses → derive skills_triggered (`Skill` tool_use), subagent_dispatches (`Agent`/`Task` tool_use + types), tool_calls_summary, invariant_pings (grep forbidden patterns: `ANTHROPIC_API_KEY|--bare|--max-budget-usd|managed-agents-|--betas managed-agents|--no-verify`), workflow_markers (regex assistant text на Plan/Review headers).
  - Report JSON расширен `trajectory: {...}` объектом.
  - Summary printout добавляет строку `Trajectory: skills=[...] | subagents=N | invariant_pings=N | plan=bool | review=bool`.
- Graceful degradation: если stream-json parsing fails, `trajectory` remains `{}`. Существующие report consumers не ломаются (читают `.claude.cost_usd` etc. как раньше).
- Smoke test на синтетическом stream-json: ✓ skills/subagents/tool_summary/invariant_pings/workflow_markers все корректно извлекаются.

**Что НЕ делалось (отложено)**:

- **P3** — legend fixture `legacy-no-tests` (modernization scenario, 600 LoC Py2-style mix, no tests).
- **P4** — trip-wire / Neg-invariant tasks (5-8 honeypot prompts).
- **P5** — stat protocol enforced default (n=3, bracket reporting в aggregate).
- **P6** — F-ambiguous tasks (criteria-judge не binary pytest).
- **Re-prog T01–T04 с новыми метриками** — требует 20-30 OAuth runs; ждёт явного go-ahead от operator'а (cost-sensitive).

## Метрики

- Files touched: 4 (`docs/benchmark.md`, `benchmark/README.md`, `benchmark/headless-runner.sh`, `benchmark/reports/README.md`).
- Lines net: docs `-51` (197→146), runner `+68` (233→301), reports template `+59` (43→102), bench README `+8` (50→58). Net `+84` строк за trajectory infrastructure.
- Layer A static-checks: pass 14/14 после изменений.
- Smoke test trajectory parser на fake stream-json: 5/5 категорий метрик правильно извлечены.

## Решения / trade-offs

1. **Stream-json vs json output**: переключение на stream-json обязательно для Layer C — `--output-format json` возвращает только summary, без conversation transcript. Cost: stream-json производит больше I/O (NDJSON), но parsing'а ровно столько же (jq read once).

2. **Invariant pings — grep across whole stream**: ловит и tool inputs, и assistant text suggestions. False positives возможны если Claude цитирует api-constraint.md (объясняя пользователю, почему НЕ делает). Acceptable: ping count ≠ violation count, это signal-to-investigate.

3. **Workflow markers regex-based, fuzzy**: в one-shot `claude --print` сессии Plan/Review структура часто отсутствует. Plan marker — soft signal что Claude применил workflow-template. Не absence ≠ failure.

4. **Backward compat per-run JSON**: схема расширена (`trajectory` поле добавлено), не сломана. Старые reports без `trajectory` поля корректно читаются через `.trajectory // null` patterns в aggregate scripts.

5. **Не реализовали ambiguous-spec tasks (P6) сейчас**: самое ценное по research'у, но самое тяжёлое (нужны quality-judges не pytest binary). Отложено осознанно, не пропущено.

## Связь

- ADR: ADR-019 (3-tier benchmark) теперь partially superseded. Текущий redesign оставляет concept «cheap-fast static + expensive-behavioral», переименовывает tiers→layers, добавляет Layer C+D. Запись об эволюции — этот devlog.
- `.claude/docs/benchmark.md` — full methodology.
- `.claude/benchmark/headless-runner.sh` — Layer B+C runner с trajectory.
- Cross-harness comparison: `.claude/benchmark/reports/CROSS-HARNESS-COMPARISON.md` сохраняется как historical baseline для T01-T04, новые runs пойдут с trajectory.

## Next

P3 (`legacy-no-tests` fixture) выбран operator'ом как первый legend кандидат — наибольший expected harness ROI (high exploration cost + ambiguous modernization specs). Перепрогон существующих T01-T04 с trajectory metrics — ждёт явного go от operator'а перед сжиганием OAuth-токенов.
