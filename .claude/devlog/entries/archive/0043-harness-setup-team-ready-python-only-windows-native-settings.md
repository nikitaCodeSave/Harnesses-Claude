---
id: 43
date: 2026-05-16
title: "harness-setup → team-ready Python-only (Windows-native, settings split, idempotent)"
tags: [skill, harness-setup, refactor, testing]
status: complete
---

# harness-setup → team-ready Python-only (Windows-native, settings split, idempotent)

## Контекст

User-level skill `~/.claude/skills/harness-setup` был в pre-release состоянии (создан 2026-05-15), e2e empirically tested только на Python с 4 stack-skeleton'ами (Python / Node / Rust / Go), bash-only hooks (`stop-verify.sh`, `format.sh`), single-file `settings.json` без team/personal split, manual backup discipline. Пользователь запросил подготовку к распространению на команду Python-разработчиков с учётом всех подводных камней.

Triggered: `/grill` сессия пошагово прошла через 7 decision-узлов (distribution mechanism / stack / OS / shipping bar / package manager / config split / drift+idempotency). Resolved decisions: per-user git clone (D); Python only (A); Windows-native через rewrite hooks на Python (B); operational+no-regression bar (A+D); detect pip/uv/poetry; full settings split (A); idempotent regeneration + автоматический backup (A).

## Изменения

### Rewrite hooks: bash → Python 3 stdlib

**`scripts/stop-verify.py`** (new, 75 lines) заменил `stop-verify.sh`. Stdlib only (`subprocess`, `json`, `sys`). Cross-platform. Decision schema `{"decision":"block","reason":"..."}` сохранена. Timeout 110s (< hook timeout 120s). `is_set()` helper для skip placeholder-shaped strings (`<...>`).

**`scripts/format.py`** (new, 56 lines) заменил `format.sh`. Stdlib only. Reads JSON `tool_input.file_path` from stdin per Anthropic hooks docs. Ruff format + `ruff check --no-fix --quiet` (warn-only, **no code removal**) — multi-pass edit safety preserved. Не блокирует никогда (exit 0 для missing file / non-.py / malformed JSON / empty stdin).

**`scripts/backup-existing.py`** (new, 47 lines) — auto-backup helper. Идемпотентно (UTC ISO timestamp), пути flatten'ятся через `__`, recursive (исключая `_backups/` саму). Вызывается Phase 0 если `.claude/` exists.

Hook command в `settings-baseline.json` обновлён: `python3 .claude/hooks/stop-verify.py` (был `bash .claude/hooks/stop-verify.sh`).

### Config split: team-shared + personal

**`scripts/settings-baseline.json`**: убран `defaultMode: "auto"` (переехал в local), добавлены lock-files в `ask` (`poetry.lock`, `uv.lock`, `Pipfile.lock`), Python-specific publish commands (`poetry publish`, `uv publish`, `twine upload`).

**`scripts/settings.local.baseline.json`** (new): `defaultMode: "auto"`, пустые allow/ask/deny под personal extensions. Inline `_comment` объясняет «НЕ КОММИТЬ».

Skill auto-update'ит `.gitignore` (idempotent append): `.claude/settings.local.json`, `.claude/_backups/`.

### SKILL.md rewrite

Phase 0 расширен: (0.1) abort early если не Python, (0.2) auto-backup при existing `.claude/`, (0.3) detect package manager по lock-файлу с табличкой соответствий, (0.4) project mode (был старый Pre-flight).

Phase 1 шаг 1 заменён на таблицу command prefix per detected manager (pip / uv / poetry × pytest / ruff / mypy). Добавлен gotcha про `extend-exclude` vs `exclude` в `[tool.ruff]` — `exclude` ломает default venv excludes и валит Stop hook на site-packages.

Phase 2 шаг 1 пишет ОБА файла (settings.json + settings.local.json). Шаг 3 — auto `.gitignore` update. Bash() substitution semantics уточнены: для multi-token (`poetry run pytest`) — full prefix, не `Bash(poetry:*)` (разрешит `poetry publish`).

Phase 5 checkpoints обновлены под новые имена файлов (`python3 -c "import json; json.load(...)"` вместо `jq`, `py_compile` вместо `bash -n`).

Skill explicit fixed как **idempotent regenerator**: пользователь меняет `pyproject.toml`, skill — единственный writer для `.claude/`. Manual edits пропадают при re-run (backup в `_backups/`).

### README + skeletons + sources обновлены под Python-only

- `README.md`: scope явно Python only; Windows native через Python (убран git-bash/WSL caveat); распределение per-user git clone, upgrade в plugin marketplace отложен; идемпотентность и re-run discipline объяснены; pre-release warning остаётся до прохождения bar.
- `scripts/claude-md.skeleton.md`: только Python stack; добавлен блок «Установка dev-зависимостей» с `<INSTALL_DEV_CMD>` placeholder.
- `scripts/readme.skeleton.md`: новые блоки «Team config vs personal config» (с таблицей какой файл что), «Re-run discipline», «Установка dev-окружения для нового dev».
- `references/sources.md`: добавлены PEP 621, Ruff docs (`--no-fix`), uv docs, Poetry docs; Anthropic Settings (split pattern) выделен отдельно.

### Auto-formatted hook scripts

`ruff format` прогнан на all 3 Python scripts (`stop-verify.py`, `format.py`, `backup-existing.py`). Critical: если hook scripts сами не отформатированы — `ruff format --check .` в Stop hook будет валить их же и зацикливать gate.

## Тестирование

3 hook-скрипта × ~4 сценариев каждый, изолированные tmp репо.

**`stop-verify.py` (4 scenarios):**
- T1 GREEN: pyproject + src/myapp + tests, pytest+ruff installed, `extend-exclude = [".claude"]` — exit 0 silent ✓
- T2 failing test: `assert add(2, 3) == 99` → block JSON `tests failed:...` ✓
- T3 lint break: unused `import os` → block JSON `lint failed: F401...` ✓
- T4 format break: `def  add(a:int,b:int)->int` → block JSON `format check failed...` ✓

**`format.py` (6 scenarios):**
- T1 valid .py с format issues + unused import — reformatted (whitespace + types), stderr warn про F401, **unused import НЕ removed** (multi-pass safety) ✓
- T2 non-existent file → exit 0 silent ✓
- T3 non-.py extension → exit 0 silent ✓
- T4 empty stdin → exit 0 silent (JSONDecodeError caught) ✓
- T5 malformed JSON → exit 0 silent ✓
- T6 missing `tool_input.file_path` → exit 0 silent ✓

**`backup-existing.py` (3 scenarios):**
- T1 first run, 3 files nested in `.claude/{hooks,agents,settings.json}` — 3 flattened *.bak files in `_backups/` с UTC timestamp ✓
- T2 re-run после sleep 1 — new timestamp, 6 файлов total, no overwrite ✓
- T3 missing `.claude/` — graceful exit 0 «nothing to back up» ✓

**JSON / Python syntax validation:**
- `python3 -c "import json; json.load(open(...))"` — `settings-baseline.json` ✓, `settings.local.baseline.json` ✓
- `python3 -m py_compile` — все 3 скрипта ✓

## Найденные bug'и в процессе

1. **Hooks сами не отформатированы** → `ruff format --check .` валит их. Фикс: `ruff format` на all 3 scripts в source skill dir.
2. **`[tool.ruff] exclude = [...]` overrides defaults** → Stop hook сканирует `.venv/` и валит на 200+ site-packages файлах. Фикс: SKILL.md Phase 1 шаг 2 явный gotcha — рекомендовать `extend-exclude`.
3. **`shlex` imported but unused** в stop-verify.py — Pyright диагностика, убран.

## E2E nested claude --print

Запущено 2 invocation'а в /tmp/e2e-greenfield-*:

- **Pure `claude --print "/harness-setup"`** — висит на AskUserQuestion в headless mode, timeout 120s, exit 143. Подтверждает: чистый slash-invoke skill'а с `disable-model-invocation: true` в headless требует AskUserQuestion bypass, иначе hang.
- **`claude --print --dangerously-skip-permissions "Invoke /harness-setup ... DO NOT call AskUserQuestion. Use heuristic..."`** — отработал корректно за ~60s. На greenfield (no git, no tests, 1 src file, pip): detected idea-mode по heuristic, создан только `CLAUDE.md` (49 lines, ≤100 limit), `.claude/_backups/` пустой (нечего бэкапить), Phase 2-4 правильно skipped. **Component-level + heuristic-mode E2E подтверждены.**

Active/production-mode сценарии (B+C) не выполнены через nested — требуют interactive AskUserQuestion для project mode / stack details. Передано в `PILOT-TEST-PLAN.md` для real-team прогона.

## Pilot iteration #3 (2026-05-16 03:50Z) — 7 findings closed

После pilot iteration #2 на том же production banking project (gap-fill mode prove-out) — ещё 7 finding'ов закрыты одной итерацией. Empirically validated F1+F10 в pilot #2; новые finding'и из re-run.

### Что закрыто

- **F11 (HIGH)** — Phase 2.5 redesign: добавлен **шаг 6 «Orthogonal enhancement offers»** (F4 extend-exclude / F5 pre-commit/CI / F7 PostToolUse). Применяется и в full mode, и в gap-fill (orthogonal к preserve-vs-regenerate). Pilot #2 показал что моя предыдущая Phase 2.5 wording «заменяет Phase 1+2» приводила к skip всех trёх AskUserQuestion'ов в gap-fill mode — fixed.
- **F12 (MEDIUM)** — Stop hook re-substitution AskUserQuestion в gap-fill: для existing `stop-verify.py` skill теперь спрашивает «re-substitute placeholders из текущего pyproject.toml или leave as-is?», default = re-substitute (idempotent).
- **F13 (LOW)** — `merge-settings.py --substitutions KEY1=VAL1,KEY2=VAL2` parameter. Substitute baseline FIRST (pre-merge), не post-merge — гарантирует idempotency: re-run с тем же `--substitutions` производит identical output. Test confirmed.
- **F14 (LOW)** — `merge-settings.py` cross-layer dedupe: если permission в `deny` → auto-removed из `ask`/`allow` с stderr warning. Если в `ask` → removed из `allow`. Logical contradictions cleaned. Test confirmed (pilot iteration #2 вручную делал этот cleanup, теперь автоматически).
- **F8c (MEDIUM)** — `/simplify` move на Phase 5 шаг 0 (BLOCKING gate, не judgment call). Усилен wording в SKILL.md и `references/verify.md`. Финал-template обязан показать `[x] /simplify invoked` явно. Pilot iteration #1 + #2 ОБА пропускали `/simplify` — finding не закрыт wording'ом, только blocking gate + accountability checkbox.
- **F8d (LOW)** — INSTALL_DEV_CMD validation в venv-prefix edge case: `pip + .venv + не activated` → все commands path-explicit (`.venv/bin/pytest`, `.venv/bin/pip install -e .[dev]`). Без префикса `pip install` мог быть глобальным (security risk).
- **F15 (LOW)** — investigated, root cause: pilot #2 emergent behavior (Skill сделал manual Edit settings.json убрать duplicate, потом перезапустил merge-settings.py что revert'нуло Edit → повторил Edit). Resolved by F13+F14 design fix: substitution + cross-layer dedupe в одном merge call, не двумя процессами.

### Tests (4 component-level + 1 pilot B-like integration)

**merge-settings.py iteration #3 features:**
- T1 cross-layer dedupe deny wins: ✓ (rm -rf в deny, removed из ask+allow)
- T2 cross-layer dedupe ask wins over allow: ✓ (git push в ask, removed из allow)
- T3 substitutions: ✓ (5 placeholders substituted, no `<...>` в JSON)
- T4 idempotency: ✓ (re-run с тем же `--substitutions` = identical output, fixed bug iteration #1)
- T5 empty target file: ✓ (24 deny entries from baseline)
- T6 malformed substitutions: ✓ (warning to stderr, valid pairs applied)

**Final integration test (pilot B-like):**
- Production-like target с PreToolUse hook + custom permissions + 3 layers с overlap
- Substitutions: 5 commands с `.venv/bin/` prefix
- All assertions: cross-layer dedupe ✓, substitutions ✓, custom preserved ✓, Stop hook added ✓, idempotent ✓

### Pilot iteration #2 — empirically validated из iteration #1

- ✅ **F1** (incremental gap-fill mode): mature detection (counts) → AskUserQuestion → gap-fill flow → preserve 7+13+2+7+80+GUIDE+3 hooks confirmed
- ✅ **F10** (structured ending): tabular «Применено / Preserved / Skipped / Reproduce-test» + 1-2 next actions + out-of-scope явно. No 5+ question menu.
- ✅ **F2** (git rm --cached): `settings.local.json` NOT TRACKED confirmed
- ✅ Reproduce-test Stop hook: silent exit 0 на baseline

### F9 — still deferred

`backup-existing.py` `_backups/<timestamp>/<rel-path>` tree structure вместо flatten names. Functional, не blocker.

## Pilot iteration #1 (2026-05-16) — 9 findings closed

После pilot A (greenfield Python с `.venv`) + pilot B (production banking system, mature `.claude/` 117 файлов) — собран список из 9 finding'ов и закрыт одной итерацией:

- **F1 (CRITICAL)** — Incremental gap-fill mode: добавлен Phase 0.2.2 (mature detection + AskUserQuestion full vs gap-fill), новый Phase 2.5 (gap-fill flow с preserve custom + MERGE settings), новый `scripts/merge-settings.py` helper (stdlib-only, idempotent, smoke-tested на 2 сценариях)
- **F2 (HIGH)** — `git rm --cached` automation в Phase 2 шаг 3 для already-tracked `settings.local.json`
- **F3 (HIGH)** — production-scoped paths: `<PROD_PATHS>` placeholder, детект из `[tool.hatch.build.targets.wheel].packages` / `[tool.setuptools].packages` / `[tool.poetry].packages` / `src/` layout
- **F4 (MEDIUM)** — `extend-exclude` AskUserQuestion offer в Phase 1 шаг 2 (auto-fix через Edit pyproject.toml)
- **F5 (MEDIUM)** — pre-commit/CI auto-create AskUserQuestion offer в `references/external-gates.md` (раньше был только template-в-README)
- **F6 (MEDIUM)** — `project-docs-bootstrap` synergy: companion section в README, soft hand-off recommendation в `references/verify.md` Phase 5+
- **F7 (LOW)** — PostToolUse format hook AskUserQuestion offer для active/production (был «opt-in только если пользователь явно просит», теперь явно offer)
- **F8 (LOW)** — `/simplify` enforcement wording: явно MANDATORY, «не judgment call», pilot-empirical observation про bypass
- **F10 (HIGH)** — structured Phase 5 ending: replaced 5+ вопросный финал на template «harness scope: 1-2 actions + out-of-scope явно scoped-out» (UX finding из pilot B где user сказал «не понимаю результатов»)

**F9 deferred** — backup-existing.py `_backups/<timestamp>/<rel-path>` tree structure вместо flatten names. Functional, не blocker.

## Что осталось manual

- **Windows native testing** — этой среды нет, проверка только через cross-platform stdlib choice (no `subprocess` `shell=` specifics, no path separators hardcoded, datetime UTC). Документировано в README.
- **Real-team pilot iteration #2** — прогнать обновлённый skill на B (mature project с gap-fill mode), убедиться что F1+F10 правильно работают end-to-end (gap-fill mode preserves custom artifacts, финал не задаёт 5+ вопросов). Подготовлен план `~/.claude/skills/harness-setup/PILOT-TEST-PLAN.md`.

## Backup пред-изменений

`/tmp/harness-setup-pre-grill-backup-1778884972/` — full snapshot предыдущего состояния skill'а. Сохранён на сессию.

## Связанные

- `/grill` сессия 2026-05-16 — decision tree resolution
- ADR-017 (active) — action-skills discipline
- [[feedback_native_capabilities_take_precedence]] — secret-scan убран ранее
- [[feedback_no_external_tools_when_inline_suffices]] — stdlib-only choice
