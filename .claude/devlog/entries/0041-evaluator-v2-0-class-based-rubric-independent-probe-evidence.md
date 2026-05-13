---
id: 41
date: 2026-05-13
title: "Evaluator v2.0: class-based rubric + independent probe + EVIDENCE re-execution"
tags: [refactor, harness, agents, hooks]
status: complete
---

# Evaluator v2.0: class-based rubric + independent probe + EVIDENCE re-execution

## Контекст

Adversarial review evaluator-связки (`discovery-critic` agent + `/critique` slash command + harness-internal `discovery-gate.sh` hook) выявил 8 структурных слабостей v1.0 после #39: (1) PREMORTEM анкорит критика на авторском фрейминге — Phase 1 verification идёт первой, Phase 2 independent probe второй; (2) `accept_risk` recorded verbatim без аудита качества обоснования — cargo-cult `"user accepted"` проходит; (3) Phase 2 probe покрывает 5 классов, security и semantics — нет, при том что security-sensitive code в trigger-домене команды; (4) EVIDENCE «real» runs верифицируются рассуждением о тексте, не re-execution — fake-real-log проходит; (5) пороги rubric произвольные (`documented_only > 2`), category spread обещан но не enforce'ится; (6) time cap «8 minutes» — самовнушение, не hard constraint (Claude Code subagent не self-limit'ится); (7) scope в большом репо — критик не знает focus area; (8) instruction «ask the main agent» — невозможный канал, subagent изолирован после spawn. Плюс (d) provenance — три прохода критика на identical state визуально неотличимы.

User explicit constraint: «связка должна работать и БЕЗ hooks» — command + agent self-sufficient, hook опциональный enforce layer для headless контекстов.

## Изменения

**`.claude/agents/discovery-critic.md`** (180 строк, было 164):

- **Phase reorder**: Phase 1 теперь *independent architectural probe* (без чтения PREMORTEM), Phase 2 — *PREMORTEM comparison*, Phase 3 — *EVIDENCE quality*. Снимает anchoring на авторском self-report.
- **Security класс добавлен** в Phase 1 probe (6-й после state/precondition/boundary/resource/concurrency): auth bypass, injection (cmd/SQL/path/template/shell metachar), privilege escalation, secrets in logs/errors/serialization, TOCTOU, trust-of-untrusted-input.
- **EVIDENCE re-execution** в Phase 3: для каждого `real_or_mock: "real"` критик классифицирует команду как `safe-to-rerun` (read-only: grep/find/ls/cat/jq/git log/curl GET-idempotent) vs `side-effect-bearing`. Re-executes как минимум одну safe-to-rerun, сравнивает с `observed_output`. Mismatch → new finding (semantics/major). Все side-effect-bearing → `reexecution_coverage: "none_all_side_effects"`.
- **`accept_risk_quality` field** в `premortem_verification[]`: `justified|weak|unjustified|n/a`. Критик не downgrade'ит статус, но добавляет orthogonal signal.
- **`severity` echo** из PREMORTEM в `premortem_verification[]` — downstream rubric использует severity для class-based blocking.
- **`context` block** в всех 3 schemas: `{git_head, dirty, iter_round}` — provenance/staleness signal. Re-spawn на identical sha без правок виден через context.
- **Removed** «8 minutes max» time cap (fiction под Claude Code subagent) — заменено «Prefer 5 sharp findings over 15 speculative» без time orientation.
- **Removed** «ask the main agent» — заменено «spec location в spawn prompt; иначе infer from README / project structure».
- **CRITIC.json schema v2.0**: добавлены `context`, `evidence_quality.reexecution_coverage`, `premortem_verification[].severity`, `premortem_verification[].accept_risk_quality`, `verdict.accept_risk_weak`, `verdict.critical_documented_only`.

**`.claude/commands/critique.md`** (165 строк, было 126):

- **Standalone operation note** наверху: command + agent самодостаточны, hooks опциональны.
- **Step 1**: provenance auto-populate (`GIT_HEAD`, `GIT_DIRTY`, `ITER_ROUND`); category-spread check `[.failure_modes[].category] | unique | length >= 3`; context-block validation.
- **Step 2**: git diff prep (`DIFF_BASE` configurable, default `HEAD~1`), prep `/tmp/critique-diff.txt`, передача в spawn prompt для focus.
- **Step 3 class-based rubric** (replaced magic threshold):
  - `NEW_CRITICAL > 0` → blocking
  - `CRITICAL_DOC_ONLY > 0` (critical-severity PREMORTEM items left documented_only) → blocking, **independent от raw count**
  - `MAJOR_RATIO > 0.3` → blocking
  - `ARISK_WEAK > 0` → surface to user, *not auto-block* (human judgment)
  - `EVIDENCE_GRADE = low` → blocking
  - `REEXEC = none_all_side_effects` → blocking
- **Iteration cap** через `context.iter_round` auto-increment из previous CRITIC.

**`.claude/hooks/discovery-gate.sh`** (294 строк, было 254):

- Category-spread check для PREMORTEM (≥3 distinct categories) — мирится с count >= 4 но не разрешает 4×boundary bypass.
- Парсинг новых полей: `critic_critical_documented`, `critic_accept_risk_weak`, `critic_reexec_coverage`.
- Class-based check: critical-severity documented_only → block, replaces threshold `documented > 2`.
- `reexecution_coverage = none_all_side_effects` → block в enforce mode.
- `accept_risk_quality = weak` → advisory note на stderr regardless of enforce mode (consistency с slash command rubric: user judgment, не auto-block).
- Iteration counter filter обновлён: real-findings filter включает `critical_documented > 0` и `reexec == none_all_side_effects`.
- Log поля расширены: `premortem_categories`, `critic_critical_documented`, `critic_accept_risk_weak`, `critic_reexec_coverage`.

## Затронутые файлы

- `.claude/agents/discovery-critic.md` — major rewrite (164 → 180 строк), schema v2.0
- `.claude/commands/critique.md` — major rewrite (126 → 165 строк), class-based rubric
- `.claude/hooks/discovery-gate.sh` — точечные правки (254 → 294 строк), aligned с v2.0
- `.claude/devlog/entries/0041-evaluator-v2-0-class-based-rubric-independent-probe.md` — этот файл

## Проверка

- `bash -n discovery-gate.sh` — syntax OK
- Smoke test 9 сценариев в `/tmp/critique-smoke-*/`:
  - Test 1: pass-through при не активном — exit 0
  - Test 2: 4 entries / 1 category — category-spread error
  - Test 3: 4 entries / 4 distinct categories — clean
  - Test 4: `critical_documented_only > 0` (severity=critical, verdict=documented_only) — enforce blocks (exit 2)
  - Test 5 (isolated): `reexecution_coverage = none_all_side_effects` — enforce blocks (exit 2)
  - Test 6 (isolated): `accept_risk_quality = weak` — advisory note, не блок (exit 0)
  - Test 7 (isolated): severity `'Critical'` case-variant — case-insensitive match, enforce blocks (exit 2)
  - Test 8: clean CRITIC v2.0 — pass
  - Test 9: log поля populated (`premortem_categories`, `critic_critical_documented`, `critic_accept_risk_weak`, `critic_reexec_coverage`)
- jq snippets из command Step 3 rubric проверены на dummy CRITIC.json: все 6 (NEW_CRITICAL, CRITICAL_DOC_ONLY, MAJOR_RATIO, ARISK_WEAK, EVIDENCE_GRADE, REEXEC) парсятся ожидаемо.

## Real-world dogfooding test (3-round adversarial review on v2.0 itself)

**Цель**: применить `/critique` workflow на сам v2.0 рефакторинг как high-stakes deliverable. Empirical validation + convergence demonstration.

**Setup**: PREMORTEM (8 entries, 7 distinct categories), EVIDENCE (6 runs, 2 safe-to-rerun). Spawn `discovery-critic` через Task tool в /tmp/critique-real-test-*/. Critic читает 3 deliverable файла по absolute paths.

| Round | New findings | Critical | Major | Verdict (rubric) | Pattern |
|---|---|---|---|---|---|
| R1 | 5 (3 maj + 2 min) | 0 | 3 verified | BLOCK (MAJOR_RATIO=0.5) | Hook input validation gaps |
| R2 | 4 (3 maj + 1 min) | 0 | 3 verified | All hard gates green; 3 majors warrant fix | **Adjacent-class — fix design itself was symptom-specific** |
| R3 | 2 (0 maj + 2 min) | 0 | 0 | **CONVERGENCE** | Backlog deferrals only |

**R1 findings (3 verified majors)**:
- F1 (semantics): Empty `premortem_verification[]` bypasses `critical_documented_only` filter — schema validation проверяет type=="array" но не length-vs-PREMORTEM. **Same class** что R2 «empty CRITIC.json bypasses» из #39, на новом уровне (inner array).
- F2 (precondition): Non-numeric `EVALUATOR_GATE_MAX_CRITIC_ITER` крашит hook exit 1 — `normalize_int` не применён к env var; asymmetric input handling.
- F3 (boundary): `MAX_CRITIC_ITER=0` → cap-reached на первой итерации → silent disable.

**R1 fix bundle**: length-mismatch elif clause + normalize_int+clamp MAX_CRITIC_ITER ≥ 1 + critical_accept_risk_weak filter (closing the PREMORTEM critical+weak gap that was документировано). 7 smoke tests verified.

**R2 findings — critic's architectural insight**: «The R2 fix for PREMORTEM #2 solved the named symptom (`weak`) but missed two adjacent labels in the same class (`unjustified` and `unclear`). Same class-vs-instance reasoning gap that originally produced the v1 "documented_only > 2" magic number. **The deeper fix is severity-dominates rule.**» Это empirical exposure of my own regression — реализуя v2.0 «class-based» refactor я повторил symptom-specific pattern.

**R2→R3 structural refactor**: заменить symptom-specific filters (`critic_critical_documented` + `critic_critical_accept_risk_weak`) одним class-based `critic_critical_unaddressed` через jq De Morgan rewrite:
```jq
[.premortem_verification[]
    | select((.severity // "" | ascii_downcase | gsub("\\s"; "")) == "critical")
    | select(
        ((.verdict // "" | ascii_downcase | gsub("\\s"; "")) != "addressed")
        and (
            ((.verdict // "" | ascii_downcase | gsub("\\s"; "")) != "accept_risk")
            or ((.accept_risk_quality // "" | ascii_downcase | gsub("\\s"; "")) != "justified")
        )
    )] | length
```

Safe set для critical-severity entry = {`addressed`, `accept_risk` + `justified`}. Всё остальное (`documented_only`, `unclear`, `accept_risk+weak`, `accept_risk+unjustified`, `accept_risk+n/a`, unknown verdict) — блокирует. Плюс whitespace gsub во всех severity/verdict/quality comparisons (R2 F3 fix — asymmetry between new_findings filter и premortem_verification filters).

**R3 11-scenario smoke test** verified class-based filter:
- critical + {addressed, accept_risk+justified} → exit 0 (safe)
- critical + {documented_only, unclear, accept_risk+weak, accept_risk+unjustified, accept_risk+n/a} → exit 2 (blocked)
- 'critical ' / 'Critical' (whitespace/case variants) → exit 2 (normalization works)
- major+documented_only, minor+documented_only → exit 0 (scope правильный — class-based filter critical-only)

**R3 critic verdict**: convergence achieved. 0 new majors. 2 minor findings оба `documented_only` для backlog:
- N1: `verdict=addressed` с `null` evidence_location accepted by hook (procedural, low probability under explicit prompt)
- N2: hook не enforce'ит `.context` block presence (carryover R1; intentional asymmetry — rubric checks it в slash command)

**Cost**: ~$0.60-0.90 total на 3 spawn'а (Opus 4.7, 18-24 tool uses / 186-239s per round). Found 9 unique bugs (6 major + 3 minor) — ROI ~$0.10/major.

## Эмпирические выводы 3-round dogfooding

1. **Convergence в 3 раундах достижим** при structural fix vs symptom-by-symptom. R1→R2 same finding count (5→4), R2→R3 sharp drop (4→2 minors only) — индикатор что the fix actually closed the class, не just instance.
2. **Adjacent-class bypass — каноническая slabost evaluator design**. Если critic flag'нул baby-X, fix'я только X оставляет X', X'' свободными. Lesson: думать в классах при fix design.
3. **De Morgan вместо `not (expr)`** — jq does not support prefix `not`. Должно быть `expr | not` postfix или De Morgan rewrite. Без этой trap пользователь увидел [FAIL] на всех тестах — value of smoke testing.
4. **Severity dominates verdict — единый rule для critical class**. {addressed, accept_risk+justified} — safe set. Это закрывает not только known cases (documented_only, weak), но и unknown future verdicts (unclear, n/a, typos) by failing closed. Анти-паттерн: enumerate каждый unsafe label by name.
5. **Provenance hash через context block работает как visible diff between rounds**. iter_round=1/2/3 + git_head делает self-respawn-on-identical-state visible. В R2 critic явно cross-checked vs R1 CRITIC.json (`Previous CRITIC.json` upload).

## Чего НЕ сделано (и почему)

- **Hard time cap через Stop hook с wall-clock kill** — пользователь explicit'но отказался: «Opus 4.7 сам разберётся с контролем процессов». Soft target в prompt'е («prefer 5 sharp findings»). Deferred — если эмпирически runaway случится, добавим Stop hook с timeout. Сейчас вред от false positives превышает hypothetical benefit.
- **Hard cap `new_findings.length <= 8` в schema** — отклонено (помельче c из критики). Hard cap дропнет legitimate cases. Soft guidance в prompt + Step 3 предупреждение «if > 10, suspect signal-to-noise».
- **`blocking_issue` как string `"none"` вместо `null`** — отклонено (помельче b). `null` — idiomatic JSON для «no blocking issue»; downstream consumer теряет null-check pattern при переходе на string.
- **`evidence_quality` naming dedup** (помельче a) — низкий приоритет, текущий defensive comment «do not duplicate inside .verdict» работает; cosmetic improvement deferred.
- **Single source of truth для JSON schemas** (carryover from #39) — всё ещё 3 копии (agent + command + hook). Deferred к `.claude/schemas/critic-verdict.schema.json` как hypothesis для ralph-loop.
- **Round 4+ adversarial review on v2.0** — diminishing returns на adjacent-class bypasses (per #39 эмпирика). Validation через smoke tests + jq rubric tests достаточна. Real-world stress via /critique on actual deliverable будет естественной валидацией.
- **Renaming PREMORTEM.json → FAILURE_MODES.json** — рассматривалось. Семантически PREMORTEM — misleading (Klein's premortem ex-ante, наш — ex-post). Решил: framing note в intro обоих файлов («post-hoc failure-mode catalog, не Klein-style premortem») закрывает confusion без legacy break. Если в будущем кто скопирует agent в другой проект — название останется стандартом нашего harness'а.

## Эмпирические выводы

1. **Smoke test cross-contamination через shared log** — повторяет паттерн round-3 теста #39. Изолированные дирректории каждый раз. Lesson: иф shared state, testing infrastructure должна быть hermetic by default.
2. **Class-based rubric clearer than threshold-based**. Magic numbers (`> 2`) уязвимы к bypass-by-volume (10 minors documented_only прошли бы как critical+minor mix). Severity-class рассуждение про блокирующее — невозможно обойти через scaling.
3. **Phase reorder — высочайший architectural impact из 8 fix'ов**. Если PREMORTEM читается первым, критик psychologically anchored на «here is what to check» вместо «what would I find independently». Switching order — single biggest lever for actually-fresh-context behavior.
4. **Re-execution gate имеет teeth, но не infinite teeth**. Все real runs side-effect-bearing — legitimate case (mutation endpoints, DB writes). Gate требует **at least one** read-only run для verification, не «все safe-to-rerun». Это compromise между rigor и practicality.

## Related

- #39 — Evaluator decoupling (JSON artifacts, /critique slash command, advisory hook) — этот рефакторинг supersedes/расширяет v1.0 → v2.0
- #34 — battle-test-runner.sh + grade.py + llm-judge.sh (где впервые появилась PREMORTEM/EVIDENCE/CRITIC дисциплина)
