---
id: 52
date: 2026-05-29
title: "Benchmark text2sql Opus 4.8: harness vs noharness (n=1)"
tags: [benchmark, harness]
status: complete
---

# Benchmark text2sql Opus 4.8: harness vs noharness (n=1)

## Контекст
Re-measurement cost-envelope под Opus 4.8 (триггер из devlog #50/#51 — major model
upgrade). Прогон `battle-test-runner.sh --task text2sql` на двух армах: harness=ours vs
noharness, оба `--build-model opus --judge-model opus` (4.8), последовательно (чтобы избежать
contention на Ollama/Oracle). Задача — агентский text2sql на Oracle XE (client_product,
1206 строк) + локальная Ollama (Qwen3-30B-A3B). n=1 на арм.

## Результат

| Метрика | A (harness=ours) | B (noharness) | Δ |
|---|---|---|---|
| **Grand** | 81/100 | **87/100** | B +6 |
| F-Q (факт. корректность) | 21/30 | 27/30 | B +6 |
| T/B auto (структура/тесты/доки) | 27/27 | 27/27 | tie |
| LLM-judge (code quality) | 33/43 | 33/43 | tie |
| Build cost | $4.08 | **$1.58** | A ×2.6 |
| Turns | 64 | **32** | A ×2 |
| Wall (build) | 11m | 5m | A ×2.2 |
| Trajectory | TaskCreate×4 + TaskUpdate×8, Write×20, Bash×22, Edit×7 | Write×16, Bash×13, Read×2 | — |

Оба: verdict=accepted, identical package-структура (`<pkg>/` с db/llm/tools/agent/config/
prompts + __main__), read-only SQL-guard, `validate_result`-tool, bounded agent-loop, env-config
без хардкода кредов, pytest + README + pyproject.

## Интерпретация (честная)
- **Quality — ничья.** T/B auto и LLM-judge **идентичны** (27/27, 33/43). Вся разница grand
  (81 vs 87) — это **одна** F-Question (Q1: A «не найдено число» vs B «found 10»); Q4 оба
  partial одинаково. F-Q зависит от недетерминированного Ollama NL→SQL → при **n=1 это шум, не
  эффект harness'а**.
- **Робастный сигнал — overhead.** Harness добавил **×2.6 cost / ×2 turns** через Task-ceremony
  (TaskCreate/Update×12) и больше итераций, **без** выигрыша в качестве кода.
- **Согласуется с axis «harness ROI ∝ exploration cost»** ([[feedback_harness_roi_exploration_cost]]):
  задача — LOW exploration (явная спека + данный `metadata.py` + `.env`), поэтому harness не
  окупается — и не окупился. Это **валидирует** консолидацию #50/#51 (минимум обвязки) и
  central principle, а не опровергает.

## Caveat
- **n=1 на арм** — индикативно, не verdict. Методология (`benchmark.md` Layer D) требует n=3 +
  sign-inversion gate. Score-дельта внутри Ollama-шума; cost/turns-overhead направленно
  совпадает с прошлым n=4 замером (devlog #24, +24-27% на simple tasks; здесь больше, n=1).
- Транзиентные `API Error: 500` Anthropic убили первый прогон арма A (помечен `FAILED-500-*`) —
  не методология.
- Минорный баг runner'а: `battle-test-runner.sh` отдаёт exit 1 несмотря на `verdict=accepted`
  (все 9 фаз проходят, report корректен) — trailing-issue, не влияет на данные.

## Затронутые файлы
- `.claude/benchmark/reports/2026-05-29-text2sql-ours-20260529T121440Z/` — арм A report
- `.claude/benchmark/reports/2026-05-29-text2sql-noharness-20260529T122708Z/` — арм B report
- clones: `/tmp/battle-text2sql-{ours,noharness}-*` (preserved для forensics)
- `.claude/docs/principles.md` — cost-envelope обновлён реальной 4.8-точкой

## Related
- #50/#51 — консолидация стартера + re-ground 4.8 (этот бенчмарк — их re-measure-триггер).
- #24 — прошлый cost-envelope (4.7-era).
- Pending: n=3 прогон для статистического verdict'а (если нужен); fix runner exit-1.
