---
id: 47
date: 2026-05-17
title: "harness-setup items 1-3 closed (ruff/py-detect/B7)"
tags: [refactor, harness, skill]
status: complete
---

# harness-setup items 1-3 closed (ruff/py-detect/B7)

## Контекст

Closure трёх deferred open items из devlog #46 для `~/.claude/skills/harness-setup/`. Все три — разные axis того же anti-pattern #15 «prescribe-without-detect» + один scope decision. Цель — устранить friction день 1 на user'ских системах с Python ≠ 3.12 и формализовать sample-app scaffolding как HITL-управляемый knob, а не неявное поведение модели.

Items 1, 2 — mechanical (ruff defaults и Python version detect). Item 3 — design decision (user выбрал HITL opt-in B7 вместо retire / status quo). Все правки + worktree validation за одну сессию.

## Изменения

**Item #1 — Ruff defaults relax** (production-aligned с user'ской mature config):
- `line-length = 100` → `line-length = 120`
- Добавлен `[tool.ruff.lint] ignore = ["E501"]` с rationale «long URLs / comments / strings — friction день 1 без relax; `ruff format` всё равно handle'ит real wrapping»

**Item #2 — Python version detect** (anti-pattern #15 sub-case (e), version axis):
- 3 hardcode `3.12`/`py312` → placeholders `<PYTHON_REQUIRES>` / `<PYTHON_TARGET>` / `<PYTHON_VERSION>` в `pyproject.skeleton.toml` (`[project] requires-python`, `[tool.ruff] target-version`, `[tool.mypy] python_version`)
- Detection logic в Step 1 Explore: `detect_python_version()` через `subprocess.check_output([bin_path, "--version"])` + regex `Python (\d+)\.(\d+)` → tuple `(">=M.m", "pyMm", "M.m")`. Fallback `(">=3.10", "py310", "3.10")` если detect failed (oldest supported per typing.TypeAlias / match-case)
- Сosmetic drift fix: stale `python_version = "3.12"` snippet в B4 section process.md L289 заменён на `<PYTHON_VERSION>` с inline note

**Item #3 — App scaffolding HITL B7 opt-in** (user choice из 3 options):
- B7 question в process.md Step 2 — default Yes, создаёт **только** `src/<pkg>/__init__.py` с `__version__ = "0.1.0"` + `tests/test_smoke.py` с `def test_smoke(): assert True`. Никакой бизнес-логики (invariant #18 explicit «harness-setup ≠ project-scaffolder»)
- `stop-verify.py` `test_gate()` функция — pytest exit 5 («no tests collected») → silent pass когда `"pytest" in cmd`. Активируется при первом написанном тесте. `_PYTEST_NO_TESTS = 5` constant с inline rationale
- Step 5 reproduce-test trigger discipline — 3 branch'а: greenfield+B7=yes (full reproduce-test), greenfield+B7=no (skip с warn), existing (full)
- Invariant #18 в SKILL.md фиксирует scope; B7 в calibration knobs list

## Затронутые файлы

Все в `~/.claude/skills/harness-setup/` (user-level skill, outside этого repo):

- `SKILL.md` — invariant #18 + B7 в calibration knobs list + anti-pattern #15 inline summary упоминает Python version axis
- `scripts/pyproject.skeleton.toml` — `line-length=120` + `ignore=["E501"]` + 3 `<PYTHON_*>` placeholders
- `scripts/stop-verify.py` — `test_gate()` + `_PYTEST_NO_TESTS=5` constant + `main()` использует `test_gate` для tests
- `references/process.md` — Step 1 `detect_python_version()` pseudocode, Step 2 B7 question, Step 4.2 substitution table обновлена, Step 5 reproduce-test trigger discipline, B4 illustrative snippet drift fix
- `references/anti-patterns.md` — #15 table sub-case (e) row + historical evidence параграф + pseudocode usage example

В этом repo (`Harnesses-Claude`) — только этот devlog entry.

## Проверка

**Multi-source validation**:

1. **Syntax checks** — `python3 -m py_compile stop-verify.py` OK; `tomllib.loads(pyproject.skeleton.toml)` OK
2. **Worktree validation Agent** (read-only, isolation: worktree, run_in_background) — explicit PASS на 3 axis:
   - Item #1: `line-length=120` + `ignore=["E501"]` present в parsed TOML
   - Item #2: все 3 hardcode заменены placeholders; `detect_python_version()` pseudocode L63-86; anti-pattern #15 sub-case (e) присутствует; manual substitution simulation `">=3.12"` → tomllib.loads parse OK
   - Item #3: B7 L335-352; invariant #18 SKILL.md L53; `test_gate()` stop-verify.py L118-127; Step 5 trigger discipline 3 branch'а
3. **Empirical reproduce-test pass** (agent выполнил 4 сценария):
   - Empty `tests/` → silent rc=0 (pytest exit 5 → test_gate ignore)
   - Passing smoke test → silent rc=0
   - Broken `assert False` → `{"decision":"block","reason":"tests failed (`pytest -q`):\n========== FAILURES ==========\n..."}` rc=0
   - Restored → silent rc=0
4. **Drift sweep** — agent обнаружил один cosmetic stale snippet (B4 section L289-296 mypy example с hardcoded "3.12"). Fixed inline.

## Related

- #46 — 13 fixes + anti-pattern #15 (parent — это closure его open items 1-3)
- #45 — final outcome contract v3 (base baseline)
- #44 — compact reorg v2

## Open items (deferred к следующей сессии)

Перенесены из devlog #46 (всё ещё не закрыты):

4. **`merge-settings.py` 227 строк** — F6 critic finding из devlog #46: может дублировать нативную Opus 4.7 JSON-merge capability. Empirical-validate-or-retire через worktree run на mature target c custom `.claude/settings.json`.
5. **SessionStart context-inject hook** (опциональный B7-альтернативный B8?) — feature addition, может съесть 3-5 discovery tool calls на каждой новой сессии. Требует ROI evaluation.

Новые открытые вопросы из этой сессии:

6. **Anti-pattern #15 как generalized invariant** — сейчас 5 sub-cases (a-e). Если появится sub-case (f) — это сигнал что pattern должен стать top-level concept («detect-then-prescribe principle»), а не table в одном anti-pattern. Watch threshold: ≥6 sub-cases или второй axis (не tool/binary/skill/python).
7. **B7=No path real-world stress** — empirical validation покрыл только B7=Yes path. B7=No (skip scaffold) проверен только через `test_gate()` exit 5 unit-test. Реальный run `/harness-setup` с user отвечающим «Skip» на B7 ещё не был.
