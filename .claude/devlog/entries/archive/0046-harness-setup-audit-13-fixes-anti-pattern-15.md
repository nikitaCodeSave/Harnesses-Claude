---
id: 46
date: 2026-05-17
title: "/harness-setup audit — 13 fixes + anti-pattern #15"
tags: [refactor, harness, skill, audit]
status: complete
---

# /harness-setup audit — 13 fixes + anti-pattern #15

## Контекст

Сессия комплексного аудита skill'а `~/.claude/skills/harness-setup/` против leader-canon (Anthropic Best Practices / Effective Harnesses / Cherny howborisusesclaudecode / NLAH arXiv 2603.25723 / Meta-Harness arXiv 2603.28052 / Chroma Context Rot). Поводом стал реальный run `/harness-setup` на `/home/nikita/PROJECTS/test/`, выявивший classifier denial settings.json + множество мелких bugs. Аудит был многоисточниковый: мой static review + discovery-critic agent в fresh context (10 findings, verdict «needs-fixes») + два empirical agent'а (dry-run на synthetic greenfield+existing targets) + real-world manual e2e run против `/tmp/harness-real-test/`.

## Изменения

13 правок применены в двух фазах:

**Фаза 1 (HIGH drift + Empirical runtime bugs, 9 правок)**:
- `references/verify.md` archived → `_archive/verify.md.20260516.bak` (полностью stale: `/simplify` blocking gate — retired anti-pattern #5; `.claude/README.md` requirement — нарушение invariant #8; Phase numbering — retired anti-pattern #6). Useful structural sanity check перенесён в `process.md` Step 5.
- `references/external-gates.md` rewritten (drop mode bucketing idea/active/production — retired anti-pattern #2; drop Phase numbering; reframed вокруг HITL B6 + per-manager pre-commit/CI templates).
- `README.md` rewritten к current SKILL.md two-mode contract (drop idea/active/production language, Phase 0-5 narrative, companion-skill auto-trigger contradiction).
- `scripts/stop-verify.py` — multi-line `PROJECT_FORMAT_CHECK_CMD = (\n "<...>"\n)` template breakage → single-line assignments (BUG 1: naive `str.replace` ломался на multi-line wrapping).
- `scripts/claude-md.skeleton.md` — `/tdd` line после HTML-комментария всегда emit'ился (HTML comment invisible в rendered MD) → `/tdd` line удалена из skeleton (BUG 3).
- `scripts/claude-md.skeleton.md` — Cyrillic placeholder `<краткое описание>` вне HTML-comment → заменён на HTML-comment (BUG 4).
- `scripts/settings-baseline.json` + `references/process.md` — allow-list `<TEST_CMD>` over-narrow если включает flags → renamed placeholders в `<*_ALLOW>` + Rule 5 (flag stripping) добавлен (BUG 2).
- `references/process.md` PROD_PATHS detection — добавлен Priority 2 `[tool.setuptools.packages.find].where` (modern sub-table) — GAP fix.
- `scripts/stop-verify.py` `is_set()` — defensive recognition `<TBD:` prefix даже когда PROD_PATHS appended (edge case pre-existing).

**Фаза 2 (Prescribe-without-detect, 4 правки + #15)**:
- `references/process.md` Step 1 (Explore) — добавлен `system_toolchain` dict через `shutil.which()` для uv/poetry/pdm/conda/python3/python + `action_skills` dict через `os.path.isfile()`.
- `references/process.md` Step 2 B1 — greenfield default теперь priority-based по availability (uv > poetry > pdm > pip+venv fallback); options annotated `✓` / `(not on PATH)` + install instructions.
- `references/process.md` Step 2 B5 — venv tool options similarly annotated.
- `scripts/settings-baseline.json` — `python3 .claude/hooks/...` → `<PYTHON_BIN> .claude/hooks/...` (was hardcoded; Windows/некоторые macOS не имеют `python3` alias).
- `scripts/claude-md.skeleton.md` `## Agent skills wired` — удалены unconditional pointer-lines `/devlog`, `/project-docs-bootstrap`; заменены HTML-комментарием с pseudocode (skill append'ит conditional per `action_skills[name]==True`).
- `references/anti-patterns.md` — **новый #15 «Prescribe-without-detect»** — generalized over 4 sub-cases (manager / venv tool / action-skills / python binary) с empirical evidence 2026-05-17.
- `SKILL.md` inline anti-patterns + invariant #15 prose обновлены к "Detect-first / wired-if-installed".

**Откат** одной правки по push-back пользователя:
- `Bash(jq:*)` в `settings-baseline.json` allow-list — initially был removed (мой ошибочный framing — путал inconsistency с sources.md "Stdlib only — no jq"), затем re-added. Принцип «Stdlib only — no jq» относится **только** к скриптам skill'а (Windows-portability), не к user-side allow-list. Anti-pattern #15 явно исключает allow-list permissions: «allow-list permission ≠ enforcement. Если jq не установлен — entry never triggered».

## Затронутые файлы

Все правки в `~/.claude/skills/harness-setup/` (user-level skill, **outside** этого repo):

- `SKILL.md` (145 строк, инвариант #15 prose + inline anti-patterns updates)
- `README.md` (167 → 146 строк, rewrite)
- `references/process.md` (493 → 622 строк, B1/B5/Step1/Step4 detect-then-prescribe pseudocode + structural sanity check + Rule 5 + PROD_PATHS gap)
- `references/anti-patterns.md` (183 → 227 строк, новый #15)
- `references/external-gates.md` (174 → 176 строк, rewrite)
- `references/verify.md` → `_archive/verify.md.20260516.bak` (archived)
- `scripts/stop-verify.py` (template restructure + `is_set()` defensive)
- `scripts/settings-baseline.json` (`<PYTHON_BIN>` placeholder + `<*_ALLOW>` renames; jq kept)
- `scripts/claude-md.skeleton.md` (skill skeleton conditional wiring + Cyrillic placeholder fix)
- `references/sources.md` (unchanged this session)
- `references/re-evaluation.md` (unchanged this session)

В этом repo (`Harnesses-Claude`) — только этот devlog entry.

## Проверка

**Multi-source audit methodology** (4 источника):

1. **Static review** против сформулированного Scope (базовый Python harness, 6 layers: Permissions / Rules / CLAUDE.md / Hooks / Action-skills / Custom agents).
2. **`discovery-critic` agent в fresh context** — verified против Anthropic canon + Cherny + NLAH. CRITIC.json в `/tmp/harness-setup-critic-1778961538.json` (10 findings, verdict `needs-fixes`).
3. **Empirical agent dry-run** на synthetic greenfield+existing targets — выявил 4 BUG + 1 GAP, не пойманных static review.
4. **Real-world manual e2e** против `/tmp/harness-real-test/` (greenfield, uv detected на этой системе) — **первый раз** все 13 правок прогнаны через actual Claude Code Write/Bash против реального target, не sub-agent simulation:
   - Stop hook reproduce-test: silent on green ✓, block JSON ≤4kB starting "tests failed"/"FAILURES" on break ✓, silent on restore ✓
   - All substitutions executed correctly (`<PYTHON_BIN>` → `python3`, `<*_ALLOW>` base paths без flags, action-skills conditional wiring)
   - Footprint generated artifacts: ~276 строк (≤1500 budget)

Empirical Pass на **все** axis acceptance + footprint + invariants.

## Related

- #45 — final outcome contract v3 (предыдущая итерация — base для этого аудита)
- #44 — compact reorg v2
- #43 — team-ready Python-only Windows-native settings (baseline иerator before drift накопился)

## Open items (deferred к следующей сессии)

1. **Ruff defaults `line-length=100` без `ignore=["E501"]`** — production config user'а использует 120 + E501 ignored. Greenfield default слишком строгий → friction на день 1.
2. **Python version hardcoded `>=3.12` / `py312`** в `pyproject.skeleton.toml` (3 места) — same class что anti-pattern #15, но axis = version assumption. User's mature config = `>=3.10`.
3. **App scaffolding scope** (`src/app/sample.py`, `tests/test_sample.py` создаются без HITL и без invariant'а в SKILL.md). Debatable: scope creep или legitimate greenfield extension.
4. **`merge-settings.py` 227 строк** — F6 critic finding: может дублировать нативную Opus 4.7 JSON-merge capability. Empirical-validate-or-retire.
5. **SessionStart context-inject hook** (опциональный B7) — feature addition, мог бы съесть 3-5 discovery tool calls на каждой новой сессии.
