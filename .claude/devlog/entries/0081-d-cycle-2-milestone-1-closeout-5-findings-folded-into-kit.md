---
id: 81
date: 2026-06-10
title: "D-cycle 2: milestone-1 closeout, 5 findings folded into kit"
tags: [harness, dogfood, skills]
status: complete
---

# D-cycle 2: milestone-1 closeout, 5 findings folded into kit

## Контекст
Второй feedback-цикл dogfood-трека (#78/#79), запущен по сигналу оператора «D.2 сейчас»
после закрытия milestone 1. Dogfood `AI_analyst_sgr` прошёл путь пустое-репо → работающий
NL→SQL SGR-агент за 6 фич / 10 сессий: отвечает на русском, генерирует SQL, исполняет на
живом Oracle, ответы grounded до копейки (подтверждено внешним аудитом-исполнителем).
Центральный риск переписи — повтор анти-паттерна «1 агент + 1 tool» — снят независимым
аудитом F5. Исходная тревога оператора «мы далеки от готового kit» закрыта эмпирически.

## Изменения
`~/.claude/skills/claude-code-harness/references/bootstrap-checklist.md` (222→251 строки,
5 правок, все evidence-grounded журналом + 4 внешними аудитами F2/F4/F5/F6):
- **Phase 3** — различать secret-bearing `.env` (deny оправдан) и dev-only `.env`
  (allow + gitignore + правило «без прод-кредов»): блок-deny ломает эргономику
  integration-тестов в dev-проекте, реальной безопасности не добавляя.
- **Phase 5.2** — kit-артефакты держать под `.claude/` (features.json/journal/progress/
  devlog); root — только продукт. Захламлённый root нелегитимен для оператора.
- **Phase 5.3** — handoff-заметка = претензия, не факт: потребляющая сессия обязана
  re-verify до опоры; фиксы формулировать «воспроизвести → закрыть» (кейс: заметка
  «NFKC закрывает оба» оказалась неверна — пропускала zero-width).
- **Phase 5.5** — два уточнения §8: (а) внешний Evaluator > self-orchestrated (само-
  заказанный субагент наследует фрейминг автора — пропустил Unicode-обход, который
  поймал полностью внешний аудит); (б) аудитор должен ИСПОЛНЯТЬ, не только читать
  (reader-audit переоценил «числа недоказаны», executor-audit переисполнил golden-SQL —
  совпало); + захватывать provenance golden/e2e-ожиданий артефактом.

## Цепочка доказательств (почему именно эти 5)
Независимые слои ловили то, что пропустил предыдущий: self-Evaluator F4 поймал
функции-денлист → внешний аудит поймал Unicode-обход → сессия 4 поймала неверную
handoff-заметку «проверено» → reader-audit F6 переоценил vs executor-audit. Каждый
уровень независимости добавлял улов — прямое подтверждение §8 на живом продукте.

## Затронутые файлы
- `~/.claude/skills/claude-code-harness/references/bootstrap-checklist.md` — 5 правок (dot-claude baaabd1)
- `AI_analyst_sgr/.claude/progress/build.md` — F6 Audit log (da3f77a, dogfood)
- `.claude/progress/dogfood-sgr-kit.md` — D.2 отмечен, метрики

## Проверка
- dot-claude: закоммичено+запушено (baaabd1); checklist 251 строка, 8 фаз/подзаголовков целы.
- Dogfood milestone 1: 6/6 фич passes, 120 unit + 5 integration (живой стек) passed,
  e2e-grounding переисполнен независимо — совпал до копейки.

## Related
- #79 — D.1 (первые 7 находок); этот цикл — D.2
- #78 — план dogfood-трека
- #62, #65 — fresh-context принцип, усиленный находками F4/F5/F6
