---
id: 33
date: 2026-05-11
title: "Battle-test text2sql-Oracle — scaffolding (F-deliverable task type)"
tags: [benchmark, battle-test, harness, deliverable-scale, oracle, ollama]
status: complete
---

# Battle-test text2sql-Oracle — scaffolding (F-deliverable task type)

## Контекст

После P4 (devlog #32) operator предложил новый task type — **F-deliverable**: Claude строит production-grade text2sql ассистента с нуля на реальной инфраструктуре (Oracle XE Docker + Ollama локально). Это качественно отличается от existing micro-benchmarks:

| Layer | Existing (T01-T04, TW) | Battle-test text2sql |
|---|---|---|
| Scope | one feature add / bugfix / invariant probe | full deliverable (CLI + tests + docs + multi-tool agentic system) |
| Cost | $0.07-0.85/run | $5-30/run estimated |
| Wall | 13-112s | 15-60min projected |
| Acceptance | binary (pytest pass / files=0 / pings=0) | 100-pt rubric (40 tech / 30 functional / 30 business) |
| External deps | none | Oracle XE + Ollama |
| Axis | exploration cost, invariant defense | deliverable-scale agentic build |

Hypothesis: harness ROI должен быть **максимальным** на F-deliverable — combines high exploration + multiple potential invariants + multi-step reasoning + production-quality requirements.

## Изменения

### Directory structure

```
.claude/benchmark/text2sql/         # FIXTURE (cloned to /tmp at run)
├── .env                            # Oracle + Ollama dev creds (localhost-only)
└── metadata.py                     # 507-line semantic dict, 30 cols RU/EN (operator-provided)

.claude/benchmark/text2sql-judge/   # OPERATOR-ONLY (НЕ копируется в fixture clone)
├── prompt.txt                      # task prompt → stdin для claude --print (29 lines)
├── questions.yaml                  # 5 NL-вопросов + ground-truth (130 lines)
├── acceptance.yaml                 # 100-pt rubric (230 lines)
└── README.md                       # operator docs (99 lines)
```

Ключевое решение: judge files **outside** fixture path — runner не клонирует sibling-dir, Claude никогда не видит questions/rubric во время run'а. Альтернатива (judge inside fixture + `rsync --exclude`) дороже по runner complexity, отброшена.

### Ground truth снят с живой Oracle XE

Запросил `ai-analyst-oracle` (1206 rows client_product, 103 distinct customer_id, период 2024-07-31..2025-06-30, 8 rows desk), вычислил expected answers для 5 NL questions:

| Q | Type | Expected |
|---|---|---|
| Q1 | simple count | 10 клиентов Large в июне 2025 |
| Q2 | top-N agg | Лизинг Компани → Транслогистик → Нефтехимпром → Металлинвест → Пенсионный фонд партнёр |
| Q3 | trend comparison | Large сегмент: +544.9M ₽ (+19.1%); остальные упали или мизерно выросли |
| Q4 | cross-table join | СМИРНОВ А.П. (head_rk=723384010 в desk table) + 2 клиента под командой |
| Q5 | filtered group-by | Москва=32, NORTH-WEST=17, URAL=11, SIBERIA=8, SOUTH=7, VOLGA=7 (act_1m=1, last month) |

Каждый вопрос имеет grading rubric: PASS / PARTIAL / FAIL criteria + tolerable swap rules (например для Q2, top-2 within 5% of dep_sum могут поменяться местами).

### Acceptance rubric (100 pts)

**Technical (40)**: structure 6 + deps 4 + error handling 6 + code quality 6 + tests 8 + docs 4 + SQL safety 6.

**Functional (30)**: 5 × 6pt per question, F-Q1..F-Q5.

**Business (30)**: answer formatting 6 + validation 5 + edge cases 6 + latency/cost 5 + production-readiness 8.

**Thresholds**: ≥70 = accepted; 50-69 = partial (investigate which category dropped); <50 = failure (harness не помог на deliverable scale).

**Sign-inversion gate** для harness comparison: variant total ≥ baseline + 10pt → «helps measurably». Within ±10pt → noise band.

### Prompt design

Передаётся через stdin в `claude --print`. Содержит:
- Контекст (Oracle XE + Ollama OpenAI-compat API, oracledb driver, metadata.py как schema map).
- Pipeline minimum (intent → SQL → exec → validate → NL answer).
- Архитектурная рекомендация (functions tools + Structured Output, no rigid pipeline).
- Минимальные tools (inspect_schema, execute_sql, validate_result, final_answer).
- Acceptance pointer (5 NL questions проверит operator отдельно).

Что Claude получает explicitly: structure freedom; Что constraints: oracledb версия, OpenAI-compat API, semantic schema source = metadata.py.

## Метрики работы

- Files created: 4 в `text2sql-judge/`. Total LoC: 488.
- metadata.py already provided by operator (507 lines, untouched).
- `.env` written с localhost-only dev creds (per operator's spec from chat).
- Layer A static-checks: 14/14 pass.
- 0 OAuth runs in this scaffolding phase.

## Решения / trade-offs

1. **judge files outside fixture**: prevents leakage. Cost: requires runner awareness что judge не клонируется. Cleaner than `rsync --exclude`.

2. **fixture = exactly 2 files** (`.env` + `metadata.py`) per operator's spec. Не добавлял README в fixture (operator hint «пустая директория с 2 файлами»).

3. **Localhost dev creds в .env committed**: dev_user/dev_password/localhost:1521 — public knowledge для shared Docker XE, не secret. Если бы были production creds — pattern `.env.example` + gitignore `.env`. Сейчас acceptable.

4. **Ground truth fixed в questions.yaml**: snapshot 2026-05-11. Если БД изменится, ground truth дрейфнёт. Mitigation: judge может re-compute ground truth on-the-fly при run'е (более robust но complicated). Сейчас static accepted.

5. **Не реализовал battle-test-runner.sh**: runner integration — отдельная phase (Phase 2 per README roadmap). Multi-step orchestration + post-run automated judging — non-trivial новый код, требует design session перед строительством. Scaffolding достаточен для operator review.

6. **Q2 tolerable_swap rule**: top-2 (Лизинг 5.65B, Транслогистик 5.62B) разница 0.5% → могут swap. Top-4↔Top-5 (Металлинвест 5.17B, Пенсионный 4.84B) — gap 6.4%, swap = FAIL. Это calibration для realistic grading.

7. **Не вынес metadata.py в judge/**: operator положил его в text2sql/ как fixture input. Это semantic doc (не ground truth), безопасно показывать Claude. Оставил как есть.

## Связь

- Devlog #30 — P1+P2 4-layer methodology source.
- Devlog #32 — P4 trip-wire (api-constraint behavioral validation prerequisite).
- `.claude/benchmark/text2sql-judge/README.md` — operator-facing methodology.
- `.claude/benchmark/text2sql/` — fixture (Claude's start state).
- Oracle DSN `localhost:1521/XEPDB1` (container `ai-analyst-oracle`).
- Ollama `localhost:11434/v1` (модель `alibayram/Qwen3-30B-A3B-Instruct-2507`).

## Next

**Phase 2 — battle-test runner**: дизайн отдельного `battle-test-runner.sh` (или extension `headless-runner.sh`). Требования:
- Clone только fixture (exclude judge sibling).
- Provision .env (or use as-is).
- `claude --print` с prompt.txt → stdin, stream-json output, timeout 2h.
- Post-run: invoke built deliverable on 5 questions, capture answers.
- Grade auto (F-Q1..F-Q5) + flag artifact for human/LLM review (T*, B*).
- Aggregate score 100-pt rubric.

**Phase 3 — first comparison run**: ours vs no-harness, n=1 each (cost $10-60, supervised). Если sign-inversion clear → expand. Если noise → analyze why before n increase.

Operator approval needed перед Phase 2 (runner code) и Phase 3 (OAuth-burning run). Phase 1 (scaffolding) — complete.
