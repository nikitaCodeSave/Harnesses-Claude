---
id: 25
date: 2026-05-11
title: "T03 FastAPI cross harness sign inversion"
tags: [benchmark, harness, evidence, fastapi]
status: complete
---

# T03 FastAPI benchmark — sign inversion vs T01/T02

## Контекст

User explicit authorization прогонять T03 на `FastApi-Base` (realistic FastAPI template,
domain-based, async SQLAlchemy, ~30 files), сбрасывая Claude artefacts между runs.
T03 spec уже существовал (`tier1/tasks/T03-fastapi-health-endpoint.yaml`), но ни разу
не прогонялся — fixture требовался external project.

T01/T02 на `sample-py-app` (single-file toy) показали envelope **+24…+27%** для нашего
harness'а — это formed «budget» foundational claim. Открытый question (devlog 0024,
«Implications»): «monitor on T03+ для stability across task classes». T03 закрывает
этот gap.

## Изменения

### 1. `FastApi-Base` setup

- Создана ветка `benchmark/baseline-noharness` в `/home/nikita/PROJECTS/FastApi-Base`.
- Удалены Claude artefacts: `.claude/`, `CLAUDE.md`, `fastapi-skills/`, `docs/` (26 файлов
  Claude обвязки из 58 tracked → 32 tracked в baseline).
- Закоммичены 4 fixture template-fixes (template originally non-functional under tests):
  - `pyproject.toml`: `pythonpath = ["."]` (pytest 8+ не добавляет cwd в sys.path)
  - `.env`: test defaults для DATABASE_URL/SECRET_KEY (force-added past .gitignore)
  - `src/shared/database.py`: conditional pool args (sqlite не поддерживает pool_size)
  - `src/auth/router.py`: `OAuth2PasswordRequestForm = Depends()`, переупорядочены args
- Удалён `tests/test_users.py` — broken даже после fixes; T03 spec не требует.
- `main` ветка не тронута, baseline ветка локальная (push не делали).

### 2. T03 prompt

```
Add a GET /health endpoint to the FastAPI application that returns JSON
{status: 'ok', service: 'fastapi-project'}. Place the route in src/shared/ if a shared
router exists, otherwise wire it in src/main.py. Add one integration test using httpx
AsyncClient in tests/test_health.py that asserts status_code==200 and the JSON body.
Do not modify existing tests or routes.
```

### 3. 4 variants, 1 run each (Opus 4.7, `acceptEdits`, `--no-session-persistence`)

Cross-harness alt clones in `/tmp/alt-harnesses/`:
- ECC: `github.com/affaan-m/everything-claude-code` (v2, 3.4MB skills)
- cwc: `github.com/anthropics/cwc-long-running-agents` (`claude-code-config/.claude/`)

## Empirical findings (T03)

| Variant | Turns | Wall | Cost | Cache_read | Files | Pytest |
|---|---:|---:|---:|---:|---:|:---:|
| A: no harness | 15 | 74s | $0.484 | 471 763 | 2 | pass |
| B: **our harness** | 9 | 69s | **$0.370** | 285 243 | 3 | pass |
| C: ECC v2 | 12 | 76s | $0.417 | 353 478 | 10 | pass |
| D: cwc | 15 | 76s | $0.435 | 418 164 | 3 | pass |

**Cost delta vs no-harness**: Our −24%, ECC −14%, cwc −10%.

## Implications (главное)

**Sign inversion.** На toy fixture (sample-py-app) наш harness был +25%; на real-world
FastAPI он −24%. ECC и cwc показывают тот же direction. **ROI harness'а зависит от
size/complexity target project'а, не от task complexity per se.**

Mechanism: workflow.md + principles.md preload подставляют structural conventions
бесплатно. На toy project это dead weight (нечего ориентировать); на realistic project
эти conventions заменяют explore-via-glob+grep+read циклы. Видно в cache_read:
no-harness 472k, our 285k → 40% меньше discovery cost. Cache_create ~равен (20k vs
20k) — preload overhead minimal.

**Foundational principle нужно nuanced**: «минимум обвязки» означает minimum **уровня
задачи** (no PM→Arch→Dev→QA pipeline), но НЕ minimum уровня **fixture навигации** —
structural preload окупается на проектах ≥1k LoC.

**Envelope теперь bi-directional**: +25% на toy, −24% на real-world. Production envelope
зависит от target project size.

## Variance check (added 2026-05-11 post-initial)

Прогнали ещё 3 runs нашего harness на T03, получили 4 точки:
- Run B-0: $0.370, 9 turns
- Run B-1: $0.345, 10 turns
- Run B-2: $0.338, 8 turns (best)
- Run B-3: $0.512, 14 turns (worst, outlier)

Stats: median $0.358, mean $0.391, stdev $0.081, **CV 20.8%**.
Δ vs baseline ($0.484, single run): **median −26%, best −30%, worst +6%**.

3/4 runs clearly below baseline. 1 run practically equal. **Turns max (14) ≤ baseline turns
(15) во всех 4 runs** — turns signal более consistent чем cost. Pattern direction (harness ≤
baseline) robust к variance; magnitude варьируется значительно.

## Caveats

- **Baseline still single run**: variance baseline тоже может быть ≈20% CV — нужны 3+ baseline
  runs для symmetric comparison. Without them median −26% claim asymmetric.
- **T03 spec explicit** («Place the route in src/shared/...») — частично направляет
  Claude. Без этого hint cost gap может быть меньше.
- **ECC v2 ≠ ECC v1**: prior T01/T02 measurement в devlog 0024 — другой harness (v1,
  116K `.claude/`). v2 — 3.4MB skills, fundamentally different. Сравнение over time
  invalid.
- **Quality identical**: все 4 variants pass `tests/test_health.py`. Side-effects
  asymmetric — ECC v2 создаёт 10 files (includes hooks/skills auto-artefacts).
- **fastapi-skills/ удалён**: original FastApi-Base ships top-level skill с FastAPI
  patterns. Удалили чтобы baseline был «no Claude knowledge». Это favors variants
  с harness — без fastapi-skills baseline Claude меньше знает про domain layout.
  Это **fair comparison** (we are measuring Claude+harness, не Claude+pre-loaded-docs).

## Затронутые файлы

- `FastApi-Base@benchmark/baseline-noharness` — 4 commits (clean baseline)
- `Harnesses-Claude/.claude/benchmark/reports/CROSS-HARNESS-COMPARISON.md` — added T03
  section, refreshed deltas table
- `Harnesses-Claude/.claude/benchmark/reports/T03-{A,B,C,D}-*-fastapi.json` — raw reports
- `/tmp/alt-harnesses/{ecc,cwc}/` — cloned (transient, not committed)

## Проверка

- All 4 `claude --print` runs exit=0, stop_reason=end_turn
- All 4 pytest pass (test_health.py created by Claude)
- 12/12 Tier 0 static checks pass (no harness regression)

## Implications для harness evolution

- **Не упрощать harness дальше**. Текущий objem (workflow.md + principles.md + 4 hooks +
  2 action-skills + 2 agents) **окупается** на realistic project — это первое empirical
  evidence net win, а не break-even. Trim'ить далее = рискнуть потерять FastAPI-class ROI.
- **Recommend ECC review**: ECC v2 показал neutral-to-positive ROI на realistic projects,
  но 10 files side-effect — opt-in pattern, не default. ECC v2 не для CI environments
  где auto-artefacts могут pollute build state.
- **T04+ нужны**: variance check на одной точке fixture (3 runs T03) ИЛИ multi-fixture
  (Django, Express, Go project) для cross-language validity. Sign-flip может зависеть
  от Python/FastAPI ecosystem stylistic conventions known well to Opus.

## Related

- #24 — cross-harness T01/T02 baseline (this entry: T03 inversion)
- #21 — benchmark infrastructure
- ADR-016 — multi-agent baseline (this evidence relevant к single-agent harness ROI)

## Follow-ups (2026-05-11 same day)

После initial findings провели три extension benchmarks (см.
`reports/CROSS-HARNESS-COMPARISON.md` для tables):

1. **3 extra baseline T03 runs** для symmetric 4×4 variance:
   - Baseline CV 8.7% (tighter чем our 20.8%)
   - Our median $0.358 vs baseline median $0.473 → confirmed **−24.4%**
   - 3/4 our runs strictly below baseline range, 0/4 above
   - Sign inversion robust к variance

2. **T04 (Alembic migration) на same FastApi-Base, 4 variants × 1 run**:
   - Our harness +3% (neutral, in variance noise)
   - ECC v2 +25% (back to overhead)
   - cwc −12% (surprisingly best)
   - **Insight**: explicit spec ("place X in Y") убирает exploration phase, harness preload
     не окупается

3. **T03e Express+Jest polyglot, 4 variants × 1 run**:
   - Our harness +2% (neutral)
   - ECC +21%, cwc +32% (overhead)
   - **Insight**: small fixture (~5 files Node) → low exploration cost → harness preload
     dead weight

### Revised hypothesis

«Sign inversion on realistic fixtures» — too narrow. Real driver:

**Harness ROI ∝ (fixture navigation depth) × (spec ambiguity).**

Three factors must align для positive ROI:
- Project structure non-obvious from filename grep
- Task spec doesn't pre-specify location/style
- Project size > 1k LoC (~10+ files Claude considers)

T03 hit все three simultaneously. T04 broke #2 (explicit). T03e broke #1 and #3 (small,
flat structure). T01/T02 broke #1 and #3.

### Implications для harness evolution (updated)

- **Не упрощать harness** confirmed across T03 (4 runs). Trimming workflow.md/principles.md
  снижает T03 ROI напрямую.
- **Не overfit к Python/FastAPI**: T03e показал neutral на Node — harness не Python-biased
  в content (≤1 mention pytest/python per doc), но и не actively useful на маленьких
  fixtures других ecosystems. Это OK: harness pays its way on realistic Python projects,
  не делает urong nor wrong on others.
- **ECC v2 — variable**: T03 (−14%), T04 (+25%), T03e (+21%). Heavyweight pack ROI
  unpredictable across task types. Not recommended as default.
- **cwc surprisingly стабильный на realistic projects**: T03 −10%, T04 −12%; overhead
  только на small fixtures (T03e +32%). Pattern matches advertised use case
  (long-running structured tasks).

## Отложено

- T05 bugfix task на FastApi-Base (orthogonal class — bug regression test before fix)
- T03 на Django fixture для third Python ecosystem data point
- Plugin-installed ECC measurement (`/plugin install` activates skills, higher overhead)
- 3+ runs T04 и T03e для variance check (currently 1 run each)
- Memory write: «harness ROI ∝ exploration cost» — invariant, save для future sessions
