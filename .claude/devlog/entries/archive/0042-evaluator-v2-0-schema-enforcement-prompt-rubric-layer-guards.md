---
id: 42
date: 2026-05-13
title: "Evaluator v2.0: schema enforcement — prompt + rubric layer guards"
tags: [refactor, harness, agents, testing]
status: complete
---

# Evaluator v2.0: schema enforcement — prompt + rubric layer guards

## Контекст

Полное тестирование v2.0 как production-ready harness component выявило класс багов «schema drift в реальном critic spawn». Critic не следовал declared CRITIC.json v2.0 schema, rubric Step 3 silently fallback'ил на дефолты (`// ""`, `0` from `[].length` on empty array) и выдавал false-clean на flawed deliverable. Два коммита закрыли core gap и 3 structural дыры через двухслойную защиту prompt-level + rubric-level.

Triggered: тестирование Evaluator v2.0 после convergence #41 (commit b374da5). E2E spawn критика на mini-deliverable с известными багами показал что критик substantively findings находит правильно, но CRITIC.json структурно отличается от объявленной schema (renamed fields, invented enum values, отсутствующий `context` block, custom verdict labels `FALSE_PREMISE`). Rubric'у этого не достаточно для блокировки.

## Изменения

### Коммит 884dd46 — schema-drift gap (первый слой)

**`.claude/agents/discovery-critic.md`** (+35 строк): Schema enforcement секция с явным списком 6 forbidden variations (renamed field, custom verdict, custom severity, custom accept_risk_quality, omitted required fields, replaced arrays). Mandatory self-validation Bash snippet (10 `jq -e` проверок) — критик обязан запустить и получить `schema_ok` перед exit.

**`.claude/commands/critique.md`** (+47 строк): новый Step 3a — pre-rubric schema check на 10 path'ов + enum values. При fail: diagnostic loop, 2-strikes re-spawn policy.

### Коммит 0590aed — 3 structural gap'а (adversarial review первого слоя)

Review первого коммита выявил adjacent-class bypasses, которые проходили Step 3a:

(1) **Empty / truncated `premortem_verification[]`** — type-check passes (array is an array), per-item filters return 0 vacuously, deliverable passes даже когда критик ни одного PREMORTEM-item не верифицировал. Закрыто cross-length check `PV_LEN ≥ PM_LEN` против `PREMORTEM.failure_modes`.

(2) **`verdict.blocking_issue != null`** — критик сигналит «inputs malformed, do not trust verdict», Step 3a игнорировал. Добавлен `.verdict.blocking_issue == null` assertion.

(3) **`new_findings[].severity` / `category` / `demonstrability` не enum-validated** — асимметрия с PREMORTEM. Custom `"HIGH"`/`"P0"`/`"logic"` проскакивали rubric jq filter (`ascii_downcase` ловит `"Critical"`, не `"HIGH"`). Mirrored PREMORTEM enum validation на new_findings paths.

Косметика: diagnostic loop теперь 14/14 paths (было 8), UPPER_CASE warning reformulated (drift fails Step 3a strict enum match, не Step 3b case-folded), removed устаревшее упоминание hook как CRITIC consumer (hook reduced to PREMORTEM/EVIDENCE reminder в b374da5).

## Затронутые файлы

- `.claude/agents/discovery-critic.md` — 208 → 235 строк (commits 884dd46 + 0590aed)
- `.claude/commands/critique.md` — 217 → 252 строки (commits 884dd46 + 0590aed)

## Проверка

### Cumulative test counts (73/73 PASS)

| Слой | Тестов | PASS |
|---|---|---|
| Hook smoke (8 base + 4 Track A) | 12 | 12 |
| CRITICAL_UNADDRESSED class-based matrix | 19 | 19 |
| Остальные rubric filters (NEW_CRITICAL, MAJOR_RATIO, ARISK_WEAK, EVIDENCE_GRADE, REEXEC) | 18 | 18 |
| Step 1 PREMORTEM/EVIDENCE input validation | 12 | 12 |
| Step 3a structural fix smoke (empty pv, truncated, blocking_issue, severity HIGH, category logic, missing demonstrability) | 9 | 9 |
| E2E spawn-and-block (validate_user.sh, parse_amount.py, safe-backup.sh) | 3 | 3 |
| **Итого** | **73** | **73** |

### Empirical E2E verification

**Same deliverable, two prompts** (`/tmp/critique-e2e-MBl6/validate_user.sh` с sourcing-rc leak, eval-injection latent, fabricated EVIDENCE Run 1):
- v1 prompt → CRITIC.json drifted (renamed fields, UPPER_CASE verdicts) → SCHEMA_OK=fail (8/8 paths), rubric не выполнялся → all-clear (false negative)
- v2 prompt → SCHEMA_OK=ok → rubric BLOCK через CRITICAL_UNADDRESSED=1 (critical+accept_risk+weak) + EVIDENCE_GRADE=low (re-execution surfaced Run 1 mismatch)

**Параллельный test двух deliverable'ов** (одновременный multi-tool-call spawn):

| | Track A (parse_amount.py, hook active) | Track B (safe-backup.sh, standalone no-hook) |
|---|---|---|
| Critic self-validation | schema_ok | schema_ok |
| Step 3a | SCHEMA_OK=ok, LEN_OK=ok (5≥5) | SCHEMA_OK=ok, LEN_OK=ok (5≥5) |
| NEW_CRITICAL | 0 | **1** (idempotency contract false, empirically surfaced) |
| CRITICAL_UNADDRESSED | 1 (float precision accept_risk+weak) | 1 (TOCTOU documented_only) |
| MAJOR_RATIO | 0.5 > 0.3 | 0.5 > 0.3 |
| EVIDENCE_GRADE | low | medium |
| **Verdict** | **BLOCKED** (3 reasons) | **BLOCKED** (3 reasons) |

Hook smoke на Track A: 4/4 PASS (passthrough при inactive, silent при clean, reminder при truncated PREMORTEM, marker file activates). Hook никогда не блокирует — exit 0 во всех сценариях.

## Эмпирические выводы

1. **Prompt decree «use exact schema» недостаточно** — model дрейфит под cognitive pressure (focus на findings, не на conformance). Mandatory self-validation Bash snippet + downstream pre-rubric check = defense-in-depth работает где prompt-only failed.

2. **Adjacent-class bypass re-emerged at smaller scale** — паттерн из #41. Первый коммит закрыл «renamed fields / custom verdicts», 3 adjacent bypasses (empty array, blocking_issue, new_findings enums) проскочили — Step 3a проверял типы, не coverage и не cross-paths. Lesson: при schema enforcement думать про all paths симметрично — any field that downstream rubric reads → must be enum-checked в обе стороны.

3. **Параллельный spawn через multi-tool-call validated** — два Agent calls в одном message запустились независимо, оба conformant, изоляция контекста подтверждена. Each critic ran in fresh context без cross-contamination.

4. **Standalone-vs-hook differentiation работает** — Track B (без hook) прошёл полный workflow только через `/critique`. Hook остаётся опциональным reminder layer для headless-контекстов, не gate. Это соответствует "Standalone operation" заявлению из commands/critique.md.

5. **Schema-conformance это deliverable**, on par с findings. Critic не «just» произвёл review — он произвёл audit-trail artifact, который rubric может потреблять. Drift = corrupted artifact = invalid review, regardless of finding quality.

## Чего НЕ сделано (и почему)

- **`accept_risk_quality` XOR-consistency check** (verdict=accept_risk ⇔ quality≠"n/a") — cosmetic; fail-safe уже ловит критичный случай через CRITICAL_UNADDRESSED filter. Деферрим до first observed incident.
- **`critic_version` via `startswith("2.")` для minor-bump compatibility** — пока только major-bump planned (2.0 → 3.0), hardcoded `"2.0"` OK.
- **Single source of truth для CRITIC schemas** (carryover from #39, #41) — всё ещё 2 копии (agent + command, hook больше не consumer). Deferred к `.claude/schemas/critic-verdict.schema.json` hypothesis для ralph-loop.

## Related

- #41 — Evaluator v2.0: class-based rubric + independent probe + EVIDENCE re-execution. Этот entry — followup post-convergence testing, выявил schema drift не покрытый первоначальным design.
- #39 — Evaluator decoupling (JSON artifacts, /critique slash command, advisory hook). Schema enforcement добавляет layer которого не было в первоначальном decoupling — pre-rubric structural check.
