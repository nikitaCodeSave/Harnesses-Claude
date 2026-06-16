---
id: 63
date: 2026-06-01
title: "Multi-session A/B: continuity-аппарат обходится стороной"
tags: [benchmark, harness, measurement, continuity]
status: complete
---

# Multi-session A/B: continuity-аппарат обходится стороной

## Контекст
Главный открытый трек (#52/#61): single-shot систематически зануляет continuity-столб
(#54) — весь build в одном контексте, переносить нечего. Замер: разбить build NL→SQL-
аналитика на **3 стадии, каждая = отдельный `claude --print --no-session-persistence` в
одном persisted workdir**, и проверить, помогает ли глобальный practice-слой (CLAUDE.md §6
+ `session-context.sh`) через границу сессии. Toggle (#60): harness = дефолтный `~/.claude`,
noharness = bare `CLAUDE_CONFIG_DIR`+creds. Дизайн (B): полный доменный спек только в S1;
S2/S3 тонкие (называют типы вопросов, не доменные ловушки) — survival правил зависит от continuity.

## Установка
Драйвер `text2sql-v2/ab/ab_multisession.py` (надстройка над `ab_runner.py`), стадии
`ab/stages/{S1,S2,S3}.md`. Скоринг — живой v2-оракул (детерминирован 5/5/5, #60; reference
12/12 подтверждён перед прогоном). Build-модель claude-sonnet-4-6, SQL-бэкенд ollama
qwen3-30b. **n=1 на руку на условие.** Два условия: **unprimed** (промпты молчат про трейл)
и **primed** (`--prime-continuity`: идентичная нейтральная инструкция «оставь заметку
следующей сессии, способ/место — на твоё усмотрение» добавлена к S1/S2).

## Результаты (gate_pass/12)
| Условие | Рука | S1→S2→S3 | Регрессии | Трейл? | Канон `.claude/{devlog,progress}`? |
|---|---|---|---|---|---|
| unprimed | harness   | 5→5→**4** | T7 | **нет** | нет (0/0) |
| unprimed | noharness | 5→5→**4** | T7 | нет | нет |
| primed   | harness   | 5→3→**4** | T7,T10 | да (`SESSION_NOTES.md`) | **нет** (0/0) |
| primed   | noharness | 5→3→**3** | T7,T10 | да (`SESSION_NOTES.md`) | нет |

delta final: unprimed **0**, primed **+1**. Финалы: harness {4,4}, noharness {4,3}.

## Вывод (главный)
**Continuity-машинерия не задействуется ни в одном условии, ни одной рукой.** Канонические
`.claude/{devlog,progress}` (единственное, что читает `session-context.sh`) пусты на каждой
стадии. Unprimed: слой **не самозапускается** — трейл не пишется вообще, хотя §6 подтверждённо
в контексте (агент процитировал «Leave a Trail Across Sessions» под `claude --print`). Primed:
трейл пишется, но как свободный `SESSION_NOTES.md` — **включая harness-руку**, обошедшую
собственные канонические папки. Хуку нечего поднимать ни в одном прогоне. Специфический
аппарат дал ноль.

Это foundational principle в действии: под способной моделью bespoke-аппарат, кодирующий
«модель не умеет переносить состояние между сессиями», избыточен — модель делает лёгкий
handoff нативно, когда попросят (оба primed `SESSION_NOTES.md` чисто фиксируют ловушки:
остатки→AVG, потоки→SUM, `TRUNC(MONTH_DT)` для EOM, `COUNT(DISTINCT INN)`, `FETCH FIRST`).
Хук полезен **только** если трейл ложится в его канонические папки — а это требует либо явной
инструкции писать в `.claude/progress`, либо привычки из реальной итеративной human-in-the-loop
работы; ни того ни другого нет в автономном `--print`-билде.

Доп.: handoff-заметка **не предотвратила регрессию** (обе primed-руки 5→3 на S2, потеряли
T7+T10, несмотря на задокументированные правила). Структурно unprimed-harness вышел чище
(пакет `nl2sql/` + `tests/` unit+integration) против плоского noharness — но оракул судит
корректность результата и к структуре слеп; в primed обе сошлись к плоскому layout'у →
структурная дельта тоже похожа на шум сборки. `+1` (primed) — в пределах build-noise.

## Инвариантных правок не делаю
Single-incident в invariant не превращается (n=1). Замер **подтверждает** существующий
дизайн (минимум обвязки), а не требует его менять. `session-context.sh` оставляю —
он silent-degrade и полезен в реальной human-in-the-loop работе (где трейл копится в
канонических папках), просто автономный single-shot его не активирует. Это согласуется
с тем, что practice-слой = standing discipline, а не single-shot booster.

## Затронутые файлы
- `text2sql-v2/ab/ab_multisession.py` (new — мульти-сессийный драйвер), `ab/stages/{S1,S2,S3}.md` (new)
- `reports/2026-06-01-ab-multisession-continuity/` (README + 2 raw-json + 2 SESSION_NOTES + 2 лога)
- Стек: поднят `ai-analyst-oracle` (docker XE), засеяна изолированная `client_product_bench`.

## Related / next
- #52/#61 (single-shot зануляет practice-дельту) — подтверждено с continuity-стороны.
- #62 (fresh-context — рычаг для critique). Параллель: ценность слоя — не в апппарате, а в
  свежем контексте / standing-привычке, не в single-shot автоматике.
- Открытый трек закрыт на directional-уровне. Если возвращаться: (1) явно инструктировать
  писать в `.claude/progress` и мерить read-side хука; (2) Opus-4.8 build-модель; (3) n≥3.
