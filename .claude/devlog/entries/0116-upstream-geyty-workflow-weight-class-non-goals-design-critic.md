---
id: 116
date: 2026-07-02
title: "Upstream-гейты workflow: weight-class + NON-GOALS + design-critic, kit v1.12.0"
tags: [harness, workflow, kit, design]
status: complete
---

# Upstream-гейты в workflow — weight-class + NON-GOALS + design-critic-upstream (kit v1.12.0)

## Контекст
Продолжение #115. Оператор дал два входа: (1) отработать все флажки/выводы аудита; (2) свой
анализ проблемы «больших изменений» — в проектах приходится каждый раз строить свою схему
беклога, а upstream-дисциплина отсутствует. Ядро анализа оператора: **документ — не результат,
а замороженный вход (гейт) для следующего этапа; в агентной разработке доки = промпт, т.е.
самый высокорычажный вход**. Предложил two missing front gates (Discovery для brownfield +
Product-framing с NON-GOALS), design-critic вверх по течению, и weight-классы против cargo-cult.

**Напряжение, которое надо было разрешить, а не замести:** предложение *добавляет* процесс, а
наши сильнейшие выводы — минимум-обвязки (#115 F6: AI_analyst battletest **умер** от 7-агентного
pipeline + 80 планов) и F2 (прескриптивный record-формат = фрикция). Разрешение — реврейм самого
оператора: **доки = INPUT (design/spec, зарабатывают место как промпт) ≠ OUTPUT (record, git
достаточно)**, и всё это **gated by weight-class**.

## Метод (dogfood собственного тезиса)
Dynamic workflow (ultracode), 11 агентов: Investigate ∥ (builtins-consolidation · benchmark-4.8-
feasibility · workflow current-state map · kit-gap патчи), затем Design = **3 варианта** (native-
minimal / funnel-faithful / hybrid-weight-class) → **adversarial refuter на каждый** (свежий
контекст, мандат «опровергни против минимум-обвязки/F6/F2/built-ins-first») → synth. Т.е. мы
применили **design-critic-upstream к самому решению о design-critic-upstream**.

**Критики отработали — вырезали overbuild, а не проштамповали.** Все 3 вернули
SURVIVES-WITH-CUTS и сошлись на одном ядре. **CUT:** новый формат `docs/context/<f>.md`
(F2-dodge — Explore-вывод остаётся в контексте); тройное зеркало таблицы + reviewer sync-gate
(это и есть md↔json-mirror анти-паттерн); обязательный critic/ADR-freeze на **medium**
(cargo-cult F1-рычага вниз); hard-block «Work не стартует» на пустых non-goals (block-at-write);
отгрузка 7-шаговой enumeration в кит (читается как PM→Arch→Dev→QA-шаблон, запускается wholesale).

## Изменения

**Upstream-редизайн (KEEP-ядро, минимальная поверхность):**
- `WORKFLOW.md` (human-facing): `Out of scope:`→`NON-GOALS` + строка «пусто = не подумал»; §3 —
  Discovery-разведка (built-in **Explore**, brownfield∧инварианты, вывод в контексте, **без**
  нового файла) + design-lite→(large)грилл→ADR с фальсифицируемым мандатом «убей ≥1 альтернативу
  failure-сценарием/цифрой»; Спина — бинар «нетривиальное» заменён на **weight-de-escalation
  строку** (trivial→small→medium→large, дефолт вниз, полный набор = исключение); backlog-large =
  ОДИН one-way носитель из spec (не новый store, не md↔json-зеркала; A/B campaign-backlog-ab N=3 drift=0).
- `.claude/docs/workflow.md` (spine): bracket-строка обновлена (weight-class · Discovery · NON-GOALS · design-lite→ADR), без дублирования таблицы (spine = router).
- Kit shipped `references/project-docs/workflow.md`: **новая секция `## Size the change before you
  build`** — реальный пробел (у кита было **ноль** upstream). Отгружена **suppression-rule +
  non-goals + recon-behavior**, НЕ enumeration funnel'а. Verification-ladder «Fresh-context» rung
  дополнен upstream-применением (грилл дизайна до заморозки). Kit v1.11.0→**v1.12.0**.

**Флажки (#115) закрыты:**
- **builtins-inventory.md → RETIRE** (`git mv` в `.claude/docs/archive/builtins-inventory-2026-06.md`,
  frozen-header). Причина: рукописный flag-каталог кодирует «модель не может `--help`» (может) —
  второй вечно-устаревший источник, F6-дубль. Недостающие **нативные факты** свёрнуты в canonical
  `native-capabilities.md` (v2.1.173→**v2.1.195**): нативный destructive-block 2.1.183 («не
  пере-кодируй кастомным DENY», §7 нативно) + auto-mode classifier diagnosable/configurable 2.1.193
  + `Agent(x,y)` enforced/background-prompt 2.1.186. Лаб CLAUDE.md → указатель на canonical. CLI-
  эргономику/env-vars НЕ рехоумили (`--help`-live territory / уже в MEMORY).
- **features.json canonical schema** — filled JSON-пример в bootstrap-checklist Phase 5 («copy
  verbatim»; канон `title`/`description`/`verify[]`, не `steps`/`acceptance` — примирение двух дрейфов).
- **pytest/venv recipe parity** — pytest-exit-5 caveat (`pytest || fail` мис-репортит пустой suite) +
  per-tool venv-резолюция (`.venv/bin/<tool>` else PATH, НЕ блочный prefix; закрывает известный
  memory-gap, не пропагированный в рецепты).
- **secret-scan allow-list баг** — anchored fix в ДВУХ target-репо (не в ките — native-first, два
  независимых баганутых копипаста = не template-worthy): `11062026` (regex: голый `test` →
  `(^|/)test_|_test\.|\.test\.|\.spec\.`) и `AI_analyst_migration_battletest` (glob: `*test*`/`*spec*`
  → segment-anchored). `bash -n` обоих — OK.
- **Kit version-провенанс** — разъезд был **uncommitted WIP v1.11.0** (#112 steering-sync
  native-capabilities + workflow.md), не дрейф. Свёрнут в честный v1.12.0-релиз с этим devlog.

**Benchmark 4.8 — NO-GO (флажок остаётся за оператором).** `−24%`-знак жил на fixture `FastApi-Base`,
которого **нет на диске/в git/в corpus.yml** (bespoke transient 2026-05-11, не персистнут). Раннер
совместим с CC, но перед GO нужно: реконструировать+запинить domain-layered FastAPI-fixture ·
выбрать lab-`.claude` vs shipped-KIT для `--inject-harness` (иначе model-delta спутан с harness-drift
против 4.7-baseline) · `source .venv/bin/activate` (pytest-оракул не на PATH → тихий skip). Lean-
sanity команда (1 task×2 variant) готова, полный axis ≈18 прогонов/~$6-10/~25мин. Независимо от
Parts A/B — отдельный follow-up.

## Затронутые файлы
- `WORKFLOW.md`, `.claude/docs/workflow.md` — upstream-редизайн (human + spine)
- `~/.claude/skills/claude-code-harness/references/project-docs/workflow.md` — новая секция + ladder (SHIPPED)
- `~/.claude/skills/claude-code-harness/references/native-capabilities.md` — v2.1.195 fold (3 правки)
- `~/.claude/skills/claude-code-harness/references/bootstrap-checklist.md` — features.json пример + venv recipe
- `~/.claude/skills/claude-code-harness/.claude-plugin/plugin.json` — v1.12.0
- `.claude/docs/archive/builtins-inventory-2026-06.md` — retired (git mv + frozen header)
- `.claude/CLAUDE.md` — Reference materials указатель
- `PROJECTS/11062026/.claude/hooks/secret-scan.sh`, `PROJECTS/AI_analyst_migration_battletest/.claude/hooks/secret-scan.sh` — anchored allow-list (отдельные репо, не закоммичено)
- `~/.claude/projects/.../memory/feedback_continuity_format_friction.md` — дополнено weight-class-реконсиляцией

## Проверка
- 3/3 критика вернули SURVIVES-WITH-CUTS; overbuild-элементы вырезаны до имплементации (design-critic сработал на самом решении).
- `bash -n` обоих secret-scan — OK.
- kit v1.12.0 консистентен: plugin.json + shipped workflow.md shipped-by.
- Каждый добавленный элемент проходит минимум-обвязки: Discovery=Explore (built-in), design-critic=external-audit refuter (built-in), backlog=features.json (существующий), 0 новых агентов/хуков/сторов.

## Related
- #115 — эмпирический аудит (источник флажков/выводов; F1 refuter-lever, F2 format-friction, F6 overbuild-drift)
- #112 — steering-sync (uncommitted WIP v1.11.0, свёрнут сюда)
- #110/#111 — campaign single-backlog-carrier (A/B, переиспользован в A1.5)
- #114 — 2.1.195 changelog (источник fold в native-capabilities)
