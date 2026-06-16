---
id: 22
date: 2026-05-11
title: "Stop-validation multi-gate + --bare references cleanup"
tags: [feature, harness]
status: complete
---

# Stop-validation multi-gate + --bare references cleanup

## Контекст

Phantom-completion (модель декларирует «готово», а lint/types ругаются) — реальная проблема dev-loop под Opus 4.7, не закрытая существующим stop-hook (тот гонял только pytest/npm test). Community evidence: 35% → 4% false-completion после independent verification.

Параллельно при проверке benchmark инфраструктуры обнаружено противоречие в harness'е: `.claude/CLAUDE.md:37` и `multi-agent.md:26`, плюс 6 строк в `.claude/benchmark/` ссылались на `claude --bare --print --add-dir` как CI-mode пример. Memory `feedback_no_anthropic_api` утверждала обратное — `--bare` ломает OAuth. Фактическая проверка через `claude --help`: «`--bare`: Anthropic auth is strictly `ANTHROPIC_API_KEY` or `apiKeyHelper` via `--settings` (OAuth and keychain are never read)». Memory оказалась канонически правильной, archive devlog 0002 содержал ошибочную «коррекцию», которая распространилась на 8 файлов.

## Изменения

### 1. stop-validation.sh — 3 independent gates

Pattern: stack-detect → run if tool available → record independent status.

| Gate | Python branch | JS/TS branch |
|---|---|---|
| test | pytest (existing) | `npm test` (existing) |
| lint | `ruff check --quiet .` (sensible defaults) | `eslint . --quiet` (global или `node_modules/.bin/eslint`) |
| types | `mypy .` — only if `mypy.ini` или `[tool.mypy]` в `pyproject.toml` | `tsc --noEmit` — only if `tsconfig.json` |

Composite decision: первый `fail` wins; иначе worst non-skipped. JSON log расширен с `gates.{test,lint,types}.{status,reason}` объектом. Surfacing — single stderr line с list всех failed gates (advisory; hook exit всегда 0). Все 4 tool разрешены в `settings.json` allow-list — уже permissioned.

Mypy guard explicit config — иначе on fresh codebases выливается hundreds of diagnostics; ruff sensible defaults достаточны без конфига; tsc requires tsconfig.json по природе TypeScript projects.

### 2. `--bare` references очищены (8 файлов)

Заменено `claude --bare --print` → `claude --print` (с дополнением «`--bare` strictly требует ANTHROPIC_API_KEY per `claude --help`, OAuth-incompatible» в reference-точках). Не трогал: archive devlog 0002 (frozen layer), plans/ (transient artefacts).

## Затронутые файлы

- `.claude/hooks/stop-validation.sh` — multi-gate rewrite (полный)
- `.claude/CLAUDE.md` — API constraint строка про CI-mode (line 37)
- `.claude/docs/multi-agent.md` — layer table cell (line 26)
- `.claude/docs/benchmark.md` — roadmap line (line 187)
- `.claude/benchmark/README.md` — current automation state (line 39, 48)
- `.claude/benchmark/tier1/README.md` — runner description (line 55, 57)
- `.claude/benchmark/tier1/run-tier1.sh` — future-comment (line 3)
- `.claude/benchmark/tier2/README.md` — roadmap line (line 33)

## Проверка

- `bash -n .claude/hooks/stop-validation.sh` → SYNTAX_OK
- `.claude/benchmark/static-checks.sh` → 12/12 PASS
- Smoke pass-path (synthetic Python fixture, `def add(a,b): return a+b` + passing pytest): JSON `{decision:pass, gates.test:pass, gates.lint:pass, gates.types:skipped}` — корректно
- Smoke fail-path (broken syntax): stderr `phantom-completion check failed — tests:pytest_failed, lint:ruff_diagnostics`, exit 0, JSON `decision:fail` — корректно
- `claude --help` верифицирован для `--bare` semantics

## Отклонённые предложения (rationale)

Из исходного 5-pack предложений приняты 2/5; остальные обоснованно отклонены:

| # | Предложение | Решение | Причина |
|---|---|---|---|
| 2 | Tier 1 full automation orchestrator | **Отложено** | Только 2 task'а (T01, T02) из заявленных T01-T07 — статистики нет; нет повторяющейся эмпирики, требующей измерения каждого harness change. Premature под evidence-based threshold. |
| 3 | Seed CLAUDE.md в project-docs-bootstrap | **Отклонено** | Skill уже enriches существующий CLAUDE.md в Phase 4 step 1 (ссылки на созданные docs). Создание скелета сверх = upfront contract — противоречит memory `feedback_no_upfront_contract_interview` и ADR-014. |
| 4 | Worktree section в workflow.md | **Отклонено** | Уже задокументирован: 10+ упоминаний, dedicated раздел «Опциональное расширение: subagent isolation для high-stakes coding», cross-link на learn-claude-code s12. |
| 5 | Session telemetry в Stop-хуке | **Отложено** | Foundational principle: компонент добавляется при empirical evidence повторяющейся потребности. Сейчас нет конкретного вопроса, на который telemetry отвечает. Premature — добавим когда возникнет diagnostic need. |

## Related

- #21 — benchmark infrastructure + stop-hook initial (этот entry расширяет gates)
- ADR-014 — first-session contract как soft guidance (rationale против seed-CLAUDE.md)
- archive devlog 0002 — содержит обратное (incorrect) утверждение про `--bare`/OAuth; frozen layer, переписывать нельзя; этот entry служит canonical correction
