---
id: 39
date: 2026-05-13
title: "Evaluator decoupling: JSON artifacts + /critique slash command"
tags: [refactor, harness, agents, hooks, adr]
status: complete
---

# Evaluator decoupling: JSON artifacts + /critique slash command

## Контекст

Evaluator-узел Planner→Generator→Evaluator (`discovery-critic` agent + `discovery-gate.sh` Stop hook) был coupled к benchmark-инфраструктуре: триггер через `HARNESS_BENCH_MODE=1` / `.benchmark-active` marker, артефакты PREMORTEM.md / EVIDENCE.md / CRITIC.md с regex-парсимой строкой `CRITIC_VERDICT:`. Research-pass по Anthropic engineering posts (Rajasekaran «Harness Design for Long-Running Apps», «Effective Harnesses for Long-Running Agents», «Multi-Agent Research System», «Building Effective Agents») выявил три прямых нарушения canon: (а) Markdown-артефакты вместо JSON (effective-harnesses: *«model less likely to inappropriately change or overwrite JSON files compared to Markdown»*), (б) regex-парсинг verdict-строки вместо JSON schema (canonical pattern — Pydantic / jq), (в) trigger через mode-flag вместо task-quality fit / explicit user invocation. Плюс concern оператора: agent должен быть **opt-in independent verifier для high-stakes deliverables**, без смешения с функционалом конкретно этого репозитория.

## Изменения

**Decoupling — три слоя:**

- **Agent file** `.claude/agents/discovery-critic.md` — project-agnostic, копируемый куда угодно (включая `~/.claude/agents/`). Все упоминания benchmark / discovery-gate / HARNESS_BENCH_MODE удалены. Промпт фокусируется только на роли Evaluator-узла, embeds JSON schemas для PREMORTEM.json / EVIDENCE.json / CRITIC.json. Verification-step добавлен: для critical findings агент обязан продемонстрировать failure через Bash (verified vs reasoned) — per Anthropic Code Review production practice.
- **Slash command** `.claude/commands/critique.md` — новый, project-agnostic. Manual user-invoked spawn критика. Workflow: verify/produce PREMORTEM.json + EVIDENCE.json → spawn discovery-critic → parse CRITIC.json via jq → decision rubric. Полностью независим от хука — работает в чужом проекте при копировании только agent + command.
- **Hook** `.claude/hooks/discovery-gate.sh` — harness-internal (остаётся в нашей инфре для ralph-loop), но: (1) парсинг через jq, не regex; (2) advisory-by-default — `exit 0` + stderr surface; gating только через opt-in `EVALUATOR_GATE_ENFORCE=1`; (3) триггеры с neutral primary именами (`EVALUATOR_GATE_ACTIVE=1` / `.claude/.evaluator-active`), legacy `HARNESS_BENCH_MODE` / `.benchmark-active` сохранены как aliases для совместимости с battle-test-runner.

**JSON schemas** (embedded в agent и slash command):
- `PREMORTEM.json` — `{deliverable, failure_modes: [{title, category, trigger, impact, severity, mitigation_status, mitigation_note}]}`, ≥4 entries
- `EVIDENCE.json` — `{deliverable, runs: [{name, command, real_or_mock, input, observed_output, expected, outcome, notes}]}`, ≥3 entries
- `CRITIC.json` — `{premortem_verification, new_findings, evidence_quality, verdict}` со структурированным verdict-блоком вместо trailing-line regex

**Smoke test 10 сценариев** — все pass: pass-through когда не активен; advisory default; enforce mode blocks; clean allow с валидными artifact; legacy HARNESS_BENCH_MODE trigger совместим; invalid JSON корректно детектируется.

## Затронутые файлы

- `.claude/agents/discovery-critic.md` — полная переработка (107 → ~145 строк), JSON-first, project-agnostic
- `.claude/hooks/discovery-gate.sh` — переписан (204 → ~195 строк): jq-парсинг, advisory default, neutral env names + legacy aliases
- `.claude/commands/critique.md` — новый, ~120 строк
- `.claude/devlog/entries/0039-evaluator-decoupling-json-artifacts-critique-slash-command.md` — этот файл

## Проверка

- `bash -n .claude/hooks/discovery-gate.sh` — syntax OK
- Smoke test 10 сценариев в `/tmp/evaluator-gate-test-*/`: pass-through (Test 1), advisory default (Test 2), enforce blocks (Test 3), clean allow (Test 4), REQUIRE_CRITIC enforces (Test 5/6), critical findings блок в enforce / pass в advisory (Test 7/8), legacy trigger compat (Test 9), invalid JSON detection (Test 10) — все exit codes ожидаемые
- `/critique` slash command загружается Claude Code (виден в skills list)
- JSON parsing через jq verified на дамми-CRITIC.json с разными verdict значениями

## Real-world тест на самом рефакторинге (3 round adversarial review)

**Цель**: dogfooding — применить evaluator на high-stakes deliverable (этот рефакторинг). Empirical demonstration работоспособности и canonical pattern «diminishing returns».

| Round | Verdict | New findings | Key result |
|---|---|---|---|
| 1 | addressed=2 documented=2 accept_risk=3 | 1 critical + 4 major + 2 minor | Critical: hook trusted scalar `verdict.new_critical_findings` без cross-check `new_findings[]`. Это **та же integrity hole**, которую JSON-рефакторинг должен был закрыть, но replaced regex regex'ом-эквивалентом. Main thread blind spot. |
| 2 | addressed=6 documented=1 accept_risk=3 | 1 critical + 1 major + 3 minor | Round-1 fixes verified end-to-end. Новый critical: empty/malformed CRITIC.json bypasses gate (`jq empty` returns 0 на zero-byte). **Same class, different door** — schema absence вместо scalar miscount. |
| 3 | addressed=8 documented=1 accept_risk=3 | 2 critical + 3 major + 1 minor | Round-2 fixes verified. 6 новых findings adjacent-class — type/case discipline gaps: iter counter inflated schema-fails (F1), severity case-sensitive (F2), verdict case-sensitive (F3), missing severity field invisible (F4), PREMORTEM/EVIDENCE not type-checked (F5), misleading log allow_reason (F6). |

**Convergence verdict**: per slash command spec line 109 («iteration cap = 3; if 3rd pass still reports critical → surface to user, loop не сходится, human judgment»). Решение оператора: bundle-fix всех 6 round-3 findings без round 4. **No spec violation** — slash command bound honored.

**Bundle-fix** (один patch на `.claude/hooks/discovery-gate.sh`):
- F1: iteration counter filter requires `critic_new_critical > 0 OR documented > 2 OR evidence == low` — schema-fail и missing-CRITIC rounds исключены
- F2/F3: jq `ascii_downcase | gsub("\\s"; "")` нормализация severity и verdict сравнений
- F4: stricter CRITIC schema — `all(.new_findings[]; has("severity") and (.severity|type=="string"))`
- F5: PREMORTEM/EVIDENCE type-check `.failure_modes | type == "array"` (и для `.runs`)
- F6: `allow_reason` ветвится по errors[] — `errors_blocking` / `errors_advisory` / `critic_cap_reached` / `clean`

Все 6 fixes verified в isolated smoke tests:
- F1: 3 schema-fail block rounds + 4th real-critical → exit=2, Iteration 1/3 (counter NOT inflated)
- F2: severity `'Critical'`/`'CRITICAL'`/`'critical '` — все exit=2 с правильным count
- F3: 3 verdict case-variants `'Documented_Only'`/`'DOCUMENTED_ONLY'`/`'documented_only '` → blocked
- F4: missing severity field → schema check rejects, exit=2
- F5: PREMORTEM с `failure_modes` как string (length=17 проходил count) → type-check rejects
- F6: advisory + errors → log записывает `allow_reason='errors_advisory'`

## Эмпирические выводы из 3-round теста

1. **Evaluator работает идеально как Rajasekaran lever**. Каждый round нашёл реальные баги, которые main thread (= я, тот же контекст что и deliverable) не увидел. Fresh-context отделение judge от author — empirically validated.
2. **Diminishing returns в bug COUNT, не в bug CLASSES**. Каждый round находит ~2x меньше total findings, но adjacent-class bypasses появляются неограниченно. Слабое место — schema/type/case discipline. Round 4 вероятно нашёл бы Nth-class bypass того же паттерна.
3. **Iteration cap = 3 — правильный bound**. Slash command spec предусматривает «human judgment» в этой точке. Cap нарушать ради эмпирики не стоит — defeating own design.
4. **Слой PREMORTEM/EVIDENCE сам должен быть type-validated**. Round 3 показал асимметрию: CRITIC schema-checked (round 2 fix), но PREMORTEM/EVIDENCE — нет. Bundle-fix исправил.
5. **Source-of-truth principle empirically validated**. Round 1 показал что scalars нельзя trust'ить → array IS truth. Этот принцип применён ко всем последующим fix'ам. Canonical lesson.

## Чего НЕ сделано (и почему)

## Чего НЕ сделано (и почему)

- **Multi-model voting (Opus + Sonnet + Haiku judges)** — research-pass не подтвердил canonical sources для evaluator. Cognition prinсiple: parallel subagents без shared context дают inconsistent verdicts. Не вводим.
- **Fleet of specialized agents** (logic / security / regression критики раздельно) — Уровень 3 из research плана. Противоречит foundational principle «spawn fewer subagents». Anthropic Code Review fleet оправдан для cloud-managed PR service, не для CLI-local harness'а.
- **Round 4 evaluator pass** — slash command spec явно ограничивает iteration cap=3 + «human judgment» когда не сходится. Round 4 нарушает собственный design. Diminishing returns argument: 6 adjacent-class findings одного pattern, Nth-class bypass найдётся в любом раунде.
- **Single source of truth для JSON schemas** — schema всё ещё дублирован в agent prompt + slash command + hook (3 копии). Deferred — extract в `.claude/schemas/critic-verdict.schema.json` как hypothesis для ralph-loop. Issue persistent but reduced impact после array-as-truth principle.
- **Carryover backlog от round 1/2/3** (4 minor findings — `${var//[!0-9]/}` float mangling, `require_critic` jq type-drift, slash command file-existence check, agent prompt READ-ONLY contradiction) — конвертированы в hypothesis-entries для backlog/self-improvement loop. Not fixed in this session.
- **Миграция battle-test-runner.sh на neutral env names** — legacy aliases работают, deferred. Когда коснёмся ralph-loop в следующий раз — мигрируем.
- **Удаление старых .md-артефактов из benchmark/audit/** — это исторические frozen snapshots, archive layer. Не трогаем.
- **GitHub Actions external review** — out of scope текущего рефакторинга, отдельная decision.

## Related

- #34 — battle-test-runner.sh + grade.py + llm-judge.sh (где впервые появилась PREMORTEM/EVIDENCE/CRITIC дисциплина)
- #37 — empirical fact-check `/goal` (research methodology — verify first-party sources before harness changes — применена и здесь)
- #38 — memory-layers + progress.md convention (parallel pattern: документация conventions без code-coupling)
