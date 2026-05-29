---
id: 44
date: 2026-05-16
title: "Harness-setup compact reorg v2"
tags: [refactor, adr, harness, skills]
status: complete
---

# Harness-setup compact reorg v2

SKILL.md 514→136 строк, decomposed в references/process.md (300) + references/anti-patterns.md (122), compose с action skills (`/tdd` MIT copy from mattpocock), empirical worktree test PASSED.

## Контекст

Pilot iteration 2 теста `/harness-setup` на пустом репо (`/home/nikita/PROJECTS/test/`) обнаружила два structural дефекта: (а) F8d block `.venv/bin/` prefix баг — skill подставлял `.venv/bin/<tool>` для всех Python инструментов, не различая глобальный ruff (`~/.local/bin/`) от venv-bound pytest/mypy; (б) перегруженный SKILL.md (514 строк прескриптивного narrative) душил native capability Opus 4.7.

Per Anthropic engineering blog 2026 «Effective harnesses for long-running agents» — strip scaffolding as models improve. Per memory `feedback_native_capabilities_take_precedence`: «если модель умеет X нативно — не расширять harness под X».

`/grill` сессия (transcript заморожен в `~/.claude/skills/harness-setup/_grill_log/harness-setup-redesign-2026-05-16.md`) resolved decomposition в compact outcome-contract + on-demand references + compose с action skills вместо rules-as-files.

## Изменения

**SKILL.md полностью переписан** в outcome-contract form (514→136 строк, 3.8× сжатие). Шесть body секций:

1. Outcome contract — 3 axis acceptance (↓ false-completion / ↓ token waste / ↓ risk surface)
2. Hard invariants — Python only, idempotent regenerator, never overwrite custom, single writer для baselines, mattpocock CLAUDE.md/AGENTS.md rule, permission default ASK
3. Process — 5 steps Explore → Present + ask (HITL one-at-a-time) → Confirm + edit → Write → Done
4. 4 HITL sections A-D — только на genuine ambiguity (existing .claude, ambiguous manager, action skills wired, Stop hook gates)
5. Critical anti-patterns inline (6 bullet'ов)
6. References pointers + testing discipline

**Удалено как noise** (Opus делает нативно): manager-prefix detection table, PROD_PATHS extraction logic, test layout classification, smoke-run procedure, mode bucketing (idea/active/production), phase numbering, per-phase «контрольные точки», F4/F5/F7 orthogonal offers numbered, mandatory `/simplify` blocking gate.

**Decomposed в references/** (читаются on-demand):
- `process.md` (300 строк) — детальный template для 5 steps + Section A-D вопросов formulation + per-tool resolve algorithm + treatment heuristic + allow-list rendering rules
- `anti-patterns.md` (122 строки) — 10 catalogued anti-patterns с historical evidence (F8d block prefix, mode bucketing, multi-pass PostToolUse, дубликаты built-in, mandatory /simplify, phase numbering, CLAUDE.md >200 строк, API key dependencies, auto-edit pyproject.toml, upfront contract interview)

**Compose с action skills (option e)** вместо копирования rules-as-files в target. Skill регистрирует `## Agent skills wired` block в `target/CLAUDE.md` (mattpocock pattern) с pointer'ами на global skills: `/devlog`, `/grill`, `/tdd`, `/project-docs-bootstrap`. Drift централизован — обновление одного skill'а доходит до всех target проектов.

**`/tdd` MIT copy** из `mattpocock/skills@e74f006` (6 files: SKILL.md, deep-modules.md, interface-design.md, mocking.md, refactoring.md, tests.md) + ATTRIBUTION.md с notes про broken refs на CONTEXT.md/docs/adr/ (mattpocock-specific) + LICENSE.upstream.

**Empirical verification** — Agent (isolation: worktree, run_in_background) прогнал new SKILL.md на pristine heterogeneous target (`/tmp/harness-pristine-test/`: pytest в .venv, ruff только глобально, mypy отсутствует). **PASS на всех 6 anti-pattern checks**:
- Per-tool resolve correct: pytest→`.venv/bin/pytest`, ruff→PATH `ruff`, mypy→`<TBD: ...>` placeholder, pip→`.venv/bin/pip`
- F8d trap not triggered (нет `.venv/bin/ruff` substitution)
- No spurious AskUserQuestion (нет mode-bucketing prompt)
- CLAUDE.md 56 строк (target ≤200)
- Reproduce-test Stop hook: block JSON 528 байт, начинается с `FAILURES`, restore → silent exit 0
- 3 axis acceptance в Done report: 24 deny + 21 ask + 18 allow / hook reproduce-test PASS / 56 строк

**Tightening pass** на `references/process.md` per 3 surfaced gap'а:
- Treatment heuristic: явный edge case «loc_py > 0 + no .git/» → active-light (не greenfield)
- Allow-list rendering rules 1-4: drop entry для TBD; split по subcommands для PATH-resolved ruff; single entry для venv-resolved; full prefix для uv/poetry
- Stop hook reproduce-test rationale в process.md

**Перенесено / архивировано:**
- Старый SKILL.md → `_backups/SKILL.md.20260516T181918Z.bak`
- `PILOT-TEST-PLAN.md` (manual pilot план) → `_archive/PILOT-TEST-PLAN-2026-05-12.md` (заменён self-testing через worktree)

**Memory:**
- `feedback_test_iterations_via_worktree.md` — обязательный прогон через worktree после правок skill/agent/hook, анализ output на axis acceptance, не self-confidence
- `feedback_per_tool_resolve_python_venv.md` — saved в предыдущей сессии (этот compact reorg empirically validates правило)

## Затронутые файлы

- `~/.claude/skills/harness-setup/SKILL.md` — переписан (514→136 строк)
- `~/.claude/skills/harness-setup/references/process.md` — создан (300 строк)
- `~/.claude/skills/harness-setup/references/anti-patterns.md` — создан (122 строки)
- `~/.claude/skills/harness-setup/_grill_log/harness-setup-redesign-2026-05-16.md` — создан (frozen grill transcript)
- `~/.claude/skills/harness-setup/_backups/SKILL.md.20260516T181918Z.bak` — backup pre-rewrite
- `~/.claude/skills/harness-setup/_archive/PILOT-TEST-PLAN-2026-05-12.md` — archived
- `~/.claude/skills/harness-setup/_archive/README.md` — archive index
- `~/.claude/skills/tdd/{SKILL.md,deep-modules.md,interface-design.md,mocking.md,refactoring.md,tests.md,ATTRIBUTION.md,LICENSE.upstream}` — MIT copy from mattpocock@e74f006
- `~/.claude/projects/-home-nikita-PROJECTS-Harnesses-Claude/memory/feedback_test_iterations_via_worktree.md` — saved
- `~/.claude/projects/-home-nikita-PROJECTS-Harnesses-Claude/memory/MEMORY.md` — indexed

## Проверка

Empirical через Agent worktree:

```bash
# Pristine target setup
PRISTINE=/tmp/harness-pristine-test
# pyproject + src/-layout + tests + .venv (только pytest установлен)
# ruff глобально, mypy отсутствует

# Agent invocation
Agent(isolation: "worktree", subagent_type: "general-purpose",
      run_in_background: true, prompt: "execute /harness-setup against pristine...")

# Verification (independent cross-check)
find /tmp/harness-pristine-test -type f -not -path '*/.venv/*' | sort
grep -nE '^PROJECT_' /tmp/harness-pristine-test/.claude/hooks/stop-verify.py
python3 -c "import json; print(len(json.load(open('/tmp/harness-pristine-test/.claude/settings.json'))['permissions']['deny']))"
wc -l /tmp/harness-pristine-test/CLAUDE.md
```

Результат: per-tool resolve correct (4/4 substitutions verified), 24 deny rules, 56 CLAUDE.md lines, hook reproduce-test PASS. Full report — `/tmp/harness-pristine-test-REPORT.md`.

Sanity checks SKILL.md:
- Frontmatter YAML parse OK; `description` = 534 chars (within discoverability cap)
- Все 8 `scripts/` refs существуют
- Все 5 `references/*.md` refs существуют

## Related

- #43 — `harness-setup-team-ready` preceding iteration (Windows-native + permissions split, pre-compact). Эта запись supersedes концептуально 5-фазную структуру, но не overwrite — #43 frozen для historical context. Compact reorg отвечает на frustration «структура навыка перегружена текстом» which #43 не закрыл.
- #42 / #41 / #40 — evaluator schema enforcement + gating bg agent view, orthogonal к harness-setup.
