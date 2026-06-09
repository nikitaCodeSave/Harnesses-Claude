---
id: 79
date: 2026-06-09
title: "D-cycle 1: dogfood journal folded into bootstrap-checklist"
tags: [harness, dogfood, skills]
status: complete
---

# D-cycle 1: dogfood journal folded into bootstrap-checklist

## Контекст
Первый feedback-цикл dogfood-трека (#78), запущен раньше плана (~5 сессий): после 3
продуктовых сессий AI_analyst_sgr копилка набрала 7+ подтверждённых находок, а оператор
сформулировал тревогу «kit не реализует полную пред-подготовку, структура нарушена».
Тревога подтвердилась наполовину: качество разработки НЕ падает (механическая
верификация сессии 2: 5 коммитов red→green, оракул 32 passed, devlog #4, пойман баг
донорского алгоритма negative-тестом), но kit как shipped действительно не давал полной
continuity-структуры — прогресс в root-файле, невидимом SessionStart-hook'у, devlog
не заводился, состояние нелегально для человека.

## Изменения
`~/.claude/skills/claude-code-harness/references/bootstrap-checklist.md` (205→222 строки,
5 правок, все evidence-grounded журналом dogfood'а — 12 наблюдений за 4 сессии):
- **Phase 3**: rewrite-with-donors — донорские репо read-only механически
  (`deny Edit/Write(//abs/path/**)`); guardrail-эпизод: deny на `.env` заблокировал
  запись кредов, которую prompt-дисциплина пропустила.
- **Phase 5.1**: domain oracle для не-web продуктов (golden inputs → expected outputs),
  negative cases обязательны — negative golden-кейс поймал донорский баг, пропущенный
  всеми позитивными тестами.
- **Phase 5.2**: verify-шаги как явные контракты (required vs default) + поле
  `preconditions` у фич (живой DB-контейнер и т.п.).
- **Phase 5.3**: прогресс предпочтительно в `.claude/progress/<slug>.md` (root-файл
  невидим hook'ам) с однострочным Quick state; **+ project devlog** как отдельный
  эпизодический слой (легитимность для оператора); сквозная нумерация сессий.
- **Phase 5.5**: периодический fresh-context аудит и принятых фич (HIGH-дефект найден
  после зелёного оракула); находки аудита — actionable-пунктами прямо в Next steps
  progress-файла (закрылись за один red→green цикл).

Сопутствующее: в dogfood поправлен ledger F3 (~30 полей в донорском репо, не ~500 —
flagged сессией 2).

## Затронутые файлы
- `~/.claude/skills/claude-code-harness/references/bootstrap-checklist.md` — 5 правок (dot-claude commit a831215)
- `AI_analyst_sgr/features.json` — F3 wording (commit 5eee5c3)
- `.claude/progress/dogfood-sgr-kit.md` — D.1 отмечен, метрики

## Проверка
- dot-claude: закоммичено и запушено (a831215); checklist 222 строки, структура фаз цела.
- Механическая верификация сессии 2 dogfood'а: git log (red→green пары), `./init.sh` →
  ORACLE GREEN 32 passed, devlog #4 существует, passes = F1/F2/F3.

## Related
- #78 — план dogfood-трека (этот цикл = его Phase D)
- #77 — kit, который правится
- #62, #65 — fresh-context evidence, усиленное находкой аудита F2
