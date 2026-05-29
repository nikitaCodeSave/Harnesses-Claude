# text2sql-Oracle battle-test

F-deliverable task type — Claude строит production-grade text2sql ассистента с нуля. Fixture = реальный Oracle XE + локальная Ollama. Acceptance — 100-pt rubric (40 tech / 30 functional / 30 business).

## Зачем это в harness

Existing Layer B/C benchmark (T01-T04 + trip-wires) тестируют **micro-behaviors** harness'а: feature add, bugfix, invariant defense. text2sql — первый **deliverable-scale** battle-test: Claude строит реальный продукт многошагово (schema discovery → tool design → SQL gen → validation → answer formatting). Это охватывает axis, который micro-tasks не покрывают: long-horizon agentic build с реальным env feedback.

Per devlog #30-32, harness ROI confirmed на:
- exploration-heavy specs (T03, -24% median)
- api-constraint invariants (TW-01/04/06, behavioral defense)

text2sql тестирует: помогает ли harness на **deliverable that combines both**? (high exploration + multiple invariants potentially relevant + multi-step reasoning).

## Что входит в fixture (Claude starts with this)

`.claude/benchmark/text2sql/` — ровно 2 файла:
- `.env` — Oracle (localhost-only dev creds) + Ollama (OpenAI-compatible API)
- `metadata.py` — 507-строчный семантический словарь 30 колонок `client_product` (RU/EN)

Всё остальное Claude собирает с нуля: pyproject, code, tests, README.

## Что входит в judge (operator-only — Claude НЕ видит)

`.claude/benchmark/text2sql-judge/`:
- `prompt.txt` — task prompt, передаётся через stdin в `claude --print` (не файл в fixture)
- `questions.yaml` — 5 NL-вопросов + ground truth (снят с живой Oracle XE)
- `acceptance.yaml` — 100-pt rubric (technical / functional / business)
- `README.md` — этот файл

## 5 NL-вопросов

| ID | Тип | Вопрос | Ground truth |
|---|---|---|---|
| Q1 | simple count | Клиенты в Large сегменте на июнь 2025 | 10 |
| Q2 | top-N aggregation | Top 5 организаций по DEP_SUM | Лизинг Компани → Транслогистик → Нефтехимпром → Металлинвест → Пенсионный фонд партнёр |
| Q3 | trend comparison | Сегмент с наибольшим ростом FX-оборота Jul-24 → Jun-25 | Large (+544.9M ₽, +19.1%) |
| Q4 | cross-table join | Глава International desk + размер команды по клиентам | СМИРНОВ А.П., 2 клиента |
| Q5 | filtered group-by | Активные клиенты по hub в последнем месяце | Москва 32 / NW 17 / Ural 11 / Sib 8 / South 7 / Volga 7 |

## Prerequisites (operator-side)

1. Oracle XE контейнер запущен: `docker start ai-analyst-oracle` (DSN `localhost:1521/XEPDB1`, dev_user/dev_password).
2. Ollama running с моделью `alibayram/Qwen3-30B-A3B-Instruct-2507` на `localhost:11434`. Verify: `curl localhost:11434/api/tags`.
3. `oracledb>=2.5.0` доступен в operator's Python (для post-run judge scripting).

## Run protocol (provisional, runner ещё не реализован)

```bash
# Concept (real runner может потребовать новых флагов в headless-runner.sh
# или отдельный battle-test-runner.sh):
bash .claude/benchmark/battle-test-runner.sh \
    --task .claude/benchmark/text2sql-judge/prompt.txt \
    --fixture .claude/benchmark/text2sql \
    --judge .claude/benchmark/text2sql-judge \
    --harness ours | noharness | ecc \
    --timeout-sec 7200      # 2h ceiling: deliverable expected 15-60min
```

Pipeline:
1. Clone fixture (2 файла) в /tmp.
2. Inject harness variant (или skip для no-harness).
3. Provision `.env` from operator's env (dev_user/dev_password — already in fixture .env, OK для smoke).
4. Run `claude --print --output-format stream-json` с prompt.txt как stdin, timeout 2h.
5. Capture stream-json + final artifact (CLONE_DIR contents post-run).
6. Run 5 questions против built deliverable: scripted CLI invocation, capture answers.
7. Compare answers to questions.yaml ground truth → per-question pass/partial/fail.
8. Score 100-pt rubric: F-Qx auto-scored, T/B require operator или LLM-judge review of artifact.
9. Aggregate report в `reports/battle-text2sql-<harness>-<date>/`.

## Cost expectation

- 1 deliverable build: $5-30 OAuth tokens (15-60 min wall, multi-turn agentic).
- 5 question evaluations × deliverable: minor incremental cost (each query ~1s).
- 2 harness variants × 1 run = $10-60 minimum для first comparison.
- n≥2 per variant: more confident but $20-120.

Это значительно дороже micro-benchmark ($0.20-0.50/run). Запуск supervised, не throwaway.

## Variance protocol

Battle-test variance higher than micro-tasks (multi-step, longer context, more decision points). Single-run результат — info only. Multi-run aggregation:
- Same task × same harness × n≥2 runs → bracket [min, median, max] of total score
- Sign-inversion gate: harness X median > baseline median + 10pt → "wins measurably"
- Within ±10pt → "noise band" (battle-test high-variance acceptable)

## What this does NOT cover

- Single-question micro-benchmarks (T01-T04 покрывают).
- Adversarial invariant probing (TW-01..08 покрывают).
- Hot-loop / continuous performance (не наш use case).
- Multi-user concurrency (этот benchmark single-session).

## Roadmap

- **Phase 1 (current)**: scaffolding done — fixture + prompt + judge + rubric written. Runner integration pending.
- **Phase 2**: dedicated `battle-test-runner.sh` или extension к `headless-runner.sh` (multi-step run + post-run judge automation).
- **Phase 3**: first comparison run (ours vs no-harness). Operator-supervised, single n=1 per variant initially.
- **Phase 4**: if ours > baseline by ≥10pt → add ECC for 3-way; if noise → expand n.
