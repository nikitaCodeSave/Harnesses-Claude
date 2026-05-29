---
id: 45
date: 2026-05-16
title: "Harness-setup final outcome contract v3"
tags: [refactor, adr, harness, skills]
status: complete
---

# Harness-setup final outcome contract v3

Two-mode contract (greenfield prescriptive / existing descriptive) + 17 hard invariants (4 новых: git lifecycle out, no auto-retry after classifier denial, `/tdd` opt-in, greenfield not neutral) + 6 calibration knobs B1-B6 как HITL one-at-a-time. Empirical worktree re-test PASS на 11/11 invariants для обоих target mode'ов.

## Контекст

Pilot run `/harness-setup` на `/home/nikita/PROJECTS/test/` (2026-05-16) выявил пять новых проблем после compact reorg v2 (#44):

1. Skill сделал `git init -q` после Write — вопреки scope «environment configurator».
2. Auto-mode classifier дважды заблокировал `.claude/hooks/stop-verify.py` Write — skill повторил без user act, ~2 turns waste.
3. `.claude/README.md` тригерил classifier denial — duplicate of CLAUDE.md.
4. Skill написал hook **inline** вместо copy template — SIM105 ruff fail на `try/except/pass`.
5. `[tool.ruff].exclude` для `.claude/` добавлен **post-fail** вместо preset в template.

Пользователь зафиксировал scope boundary: «не нужно смешивать ответственность. Не нужно никак взаимодействовать с наличием\отсутствием git». Затем в design conversation расширил mental model: «для чистых проектов стремимся предложить best practices уже с явными гарантиями повышения продуктивности и качества кодинга claude code».

Это привело к two-mode contract: greenfield prescriptive с rationale per knob vs existing descriptive с respect verbatim.

## Изменения

**SKILL.md rewritten** под финальный outcome contract:
- 17 hard invariants (расширено с 7 до 17): добавлены #7 git lifecycle out, #8 no `.claude/README.md`, #9 no `chmod +x`, #10 pyproject read-only on existing, #11 no pip install от своего имени, #12 no auto-retry after classifier denial, #13 no PostToolUse `ruff --fix`, #15 `/tdd` opt-in (не default), #16 `python-conventions.md` out (owned by `/project-docs-bootstrap`), #17 template-use discipline.
- Two-mode contract section: classifier `loc_py == 0 || not has_git` → greenfield prescriptive (apply 2026 stack с rationale); иначе existing descriptive (respect verbatim).
- 6 calibration knobs B1-B6 как HITL one-at-a-time с detection-default + rationale per knob (uv: 10× faster pip; ruff: 4 tools одной командой; mypy middle: warn_return_any + disallow_untyped_defs без full strict cascade; src-layout: unambiguous imports).
- 3 ambiguity sections A/C/D (existing `.claude/` resolution, action skills wire, Stop hook gates).
- Aggregate footprint metric — CLAUDE.md + settings.json + stop-verify.py ≤ 1500 строк (новая acceptance).

**`references/process.md` rewritten**:
- Mode classifier с edge cases (`loc_py > 0 + not has_git` → greenfield; `loc_py == 0 + has_git` → greenfield).
- HITL B1-B6 с детальной formulation per knob (greenfield default + rationale vs detected verbatim).
- Step 3 Confirm — upfront classifier warning блок («следующий шаг будет писать `.claude/hooks/`, переключи permission mode на `acceptEdits` на один шаг»).
- Step 4 Write — порядок без `git init` / `git add` / `git rm --cached` / `chmod +x`. Template-based: copy `scripts/*.skeleton` + substitute, не inline write.
- Step 5 Done — extended report template с Mode field + Best practices applied (rationale per knob, greenfield only) + Known limitations (если `.claude/settings.local.json` уже tracked в git — user responsibility).

**`references/anti-patterns.md` extended** — добавлены #11-#14 с historical evidence:
- #11 Auto git lifecycle interaction (case 2026-05-16: skill сделал `git init -q`).
- #12 Auto-retry после classifier denial (case 2026-05-16: дважды blocked `.claude/hooks/`).
- #13 Default-wire `/tdd` без HITL (per user 2026-05-16 «`/tdd` opt-in, не default»).
- #14 Greenfield neutral defaults вместо prescriptive 2026 stack (per user 2026-05-16 «явные гарантии повышения продуктивности»).

**`scripts/pyproject.skeleton.toml` создан** (new) — greenfield-only template:
- `[tool.ruff] extend-exclude = [".claude"]` preset (не post-fix).
- `[tool.mypy]` middle config: `warn_return_any = true` + `disallow_untyped_defs = true` + `exclude = ['^\.claude/']` preset.
- Не применять на existing — invariant #10.

**`scripts/claude-md.skeleton.md` rewritten** — 5 thematic sections (Stack / Structure / Commands / Sensitive paths / Conventions) + Agent skills wired + Workflow reminders + References. Indexer-only style. By default wired: `/devlog`, `/project-docs-bootstrap`. `/tdd` opt-in.

**`scripts/readme.skeleton.md` retired** → `_archive/readme.skeleton.md.2026-05-16.bak`. Per invariant #8 — `.claude/README.md` НЕ создаётся (duplicate of CLAUDE.md + classifier trigger). Информация перенесена в CLAUDE.md секции.

**`references/re-evaluation.md` создан** (new) — 5 maintenance triggers для skill-level discipline:
- Major Opus release (4.7 → 4.8 → 5.x)
- Major Python release с breaking changes
- N ≥ 3 empirical промахов одного типа
- First-party Anthropic best-practices update
- New built-in subagent в `claude agents`

Single-incident — НЕ trigger, pattern требует evidence. Документировать каждый event в devlog.

**Memory + index**:
- `feedback_harness_no_git_lifecycle.md` — scope boundary (reads OK; writes никогда).
- `feedback_no_auto_retry_after_classifier_denial.md` — upfront warning + manual permission mode switch.
- `feedback_greenfield_prescriptive_existing_descriptive.md` — two-mode contract rationale.
- `MEMORY.md` indexed all three.

## Empirical verification — worktree re-test

`Agent(isolation: "worktree", run_in_background: true)` на двух pristine Python targets:

**Target A (greenfield)**: `loc_py == 0`, `.venv` only (pytest + ruff installed), no `.git`. Mode = greenfield prescriptive.
**Target B (existing)**: `loc_py = 7`, `.git/` с initial commit, minimal pyproject + src/app/main.py greet() + tests passing. Mode = existing descriptive.

Метод: dry-run simulation per skill steps 1-5 + manual apply через `scripts/*.skeleton` templates + 11-invariant independent verification.

**PASS на всех 11 invariants для обоих targets**:

| # | Check | Target A | Target B |
|---|---|---|---|
| 1 | No `git init` on greenfield | `.git/` absent | N/A |
| 2 | No new commits on existing | N/A | git log = 1 |
| 3 | No `.claude/README.md` | absent | absent |
| 4 | Hook no `chmod +x` | `-rw-rw-r--` | `-rw-rw-r--` |
| 5 | pyproject.toml read-only on existing | N/A | empty diff |
| 6 | settings deny/ask/allow split | 24/21/17 | 24/21/16 |
| 7 | Stop hook reproduce-test (broken → block + FAILURES; restored → silent) | PASS | PASS |
| 8 | CLAUDE.md ≤200 lines | 71 | 67 |
| 9 | Footprint ≤1500 (CLAUDE.md+settings.json+hook) | 272 | 267 |
| 10 | No `/tdd` in CLAUDE.md (HITL C default=No) | 0 matches | 0 matches |
| 11 | Greenfield pyproject `.claude` excludes preset | both present | N/A |

Frozen test log: `~/.claude/skills/harness-setup/_test_logs/2026-05-16T22-45Z-final-outcome-contract-v3.md`.

## Затронутые файлы

- `~/.claude/skills/harness-setup/SKILL.md` — rewritten (17 invariants, two-mode contract, 6 knobs B1-B6)
- `~/.claude/skills/harness-setup/references/process.md` — rewritten (mode classifier + B1-B6 detail + classifier warning + no-git Step 4)
- `~/.claude/skills/harness-setup/references/anti-patterns.md` — extended +#11-#14
- `~/.claude/skills/harness-setup/references/re-evaluation.md` — created (5 triggers)
- `~/.claude/skills/harness-setup/scripts/pyproject.skeleton.toml` — created (greenfield-only)
- `~/.claude/skills/harness-setup/scripts/claude-md.skeleton.md` — rewritten (5 thematic sections)
- `~/.claude/skills/harness-setup/scripts/readme.skeleton.md` → `_archive/readme.skeleton.md.2026-05-16.bak`
- `~/.claude/skills/harness-setup/_archive/README.md` — updated index
- `~/.claude/skills/harness-setup/_backups/{SKILL.md,process.md,anti-patterns.md}.20260516T193312Z.bak` — backups
- `~/.claude/skills/harness-setup/_test_logs/2026-05-16T22-45Z-final-outcome-contract-v3.md` — frozen worktree test log
- `~/.claude/projects/-home-nikita-PROJECTS-Harnesses-Claude/memory/feedback_harness_no_git_lifecycle.md` — created
- `~/.claude/projects/-home-nikita-PROJECTS-Harnesses-Claude/memory/feedback_no_auto_retry_after_classifier_denial.md` — created
- `~/.claude/projects/-home-nikita-PROJECTS-Harnesses-Claude/memory/feedback_greenfield_prescriptive_existing_descriptive.md` — created
- `~/.claude/projects/-home-nikita-PROJECTS-Harnesses-Claude/memory/MEMORY.md` — indexed three new entries

## Проверка

Worktree re-test через `Agent(isolation: "worktree", run_in_background: true)` — frozen log в `_test_logs/`. 11/11 invariants PASS оба target mode'а.

Sanity checks:
- SKILL.md frontmatter YAML parse OK; `description` ≤ 534 chars (within discoverability cap)
- Все `scripts/` references existуют (`settings-baseline.json`, `stop-verify.py`, `claude-md.skeleton.md`, `pyproject.skeleton.toml`, helpers)
- Все `references/*.md` references existуют (`process.md`, `anti-patterns.md`, `external-gates.md`, `verify.md`, `re-evaluation.md`, `sources.md`)
- `_archive/README.md` updated с retired `readme.skeleton.md` entry

## Related

- #44 — `harness-setup-compact-reorg-v2` (предыдущий compact 514→136). Эта запись supersedes концептуально outcome contract section + invariants list, но не overwrite — #44 frozen для historical compact reorg context.
- #43 — `harness-setup-team-ready` (Windows-native + permissions split), pre-compact.
- Все три (#43, #44, #45) — sequential maturation одного skill'а через empirical iterations.
