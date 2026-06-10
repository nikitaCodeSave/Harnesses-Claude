---
plan: .claude/plans/standard-v1-regulation.md
last-updated: 2026-06-10
status: active
session-count: 1
---

# Прогресс: Регламент v1 — сборка и тестирование единого стандарта

## Quick state — Phase 1: R1+R2+R3 done (playbook + /external-audit + harness-evolution в ~/.claude, commit 9a215c3); /external-audit прогнан боевым на milestone-1 SGR — поймал verified CRITICAL (обход SQL-денлиста), вердикт REFUTED · next: R4 (гигиена путей/README) → Phase 2 упаковка · блокеров нет

## Phase checklist

### Phase 0 — Scope-фиксация (2/2 done)
- [x] Grill по D1–D5 — все решены (см. Decisions), 2026-06-10
- [x] Progress-файл заведён (этот файл); отдельный features-ledger не нужен —
      verify-шаги несёт сам план

### Phase 1 — Сборка содержания (3/4)
- [x] R1 Operator playbook (99 строк, references/operator-playbook.md) — 2026-06-10
- [x] R2 /external-audit: command + 3 агента (evidence-executor/process-auditor/code-refuter),
      контракт вердиктов унифицирован с CRITIC.json; БОЕВОЙ прогон на milestone-1 SGR прошёл,
      поймал verified CRITICAL — 2026-06-10
- [x] R3 harness-evolution.md (D-циклы + strip) как reference kit'а — 2026-06-10
- [ ] R4 Гигиена: пути hooks/settings → переносимые; README += манифесты + re-pin процедура

### Phase 2 — Упаковка (0/2)
- [ ] P1 plugin v1.1.0 (kit + playbook + command + agents), sync манифестов, tag
- [ ] P2 три пути доставки в README: git clone / plugin install / оффлайн-архив

### Phase 3 — Тестирование (0/4)
- [ ] T1 smoke чистого профиля (CLAUDE_CONFIG_DIR), провенанс-артефакт обязателен
- [ ] T2 Audit-режим на AI_analyst_migration (gap-report → approve → правки; только .claude/+docs)
- [ ] T3 n=2: prompt-validation тулза (новый репо из боли dev/-скриптов migration), journal обязателен
- [ ] T4 внешний walkthrough-аудит регламента (свежая сессия, исполнением)

### Phase 4 — D.3 и релиз (0/3)
- [ ] Находки T1–T4 → правки канона + devlog
- [ ] Финальный bump + tag + сводный devlog «Регламент v1 released»
- [ ] Strip-ревизия добавленного

## Sessions log

### Session 1 — 2026-06-10 (Phase 0: grill D1–D5)

**Done & measured**

| Артефакт | Метрика | Target | Hit |
|---|---|---|---|
| Разведка (3 параллельных Explore) | инвентари ~/.claude (30 файлов), lab (3-агентный аудит НЕ формализован), проекты A/B (gap-списки) | факты для D-вопросов | ✅ |
| План трека | .claude/plans/standard-v1-regulation.md (фазы 0–4, DoD 6 пунктов, риски R1–R5) | существует | ✅ |
| Grill D1–D5 | 5/5 решены, все по рекомендации | 5/5 | ✅ |

**Discovered**
- WORKFLOW.md лаборатории — уже готовый spine регламента; R1 = сведение, не написание с нуля.
- 3-ролевой аудит-протокол существует только прозой в devlog #78–#81 — главная цель R2.
- Memory проекта AI_analyst обновлена итогами dogfood (project_sgr_dogfood_results.md).

**Blockers** — (none)

**Next session targets** (measurable)
- [ ] R1: playbook написан (≤150 строк, wc -l), full paths, без копий checklist'а
- [ ] R2: /external-audit + 3 агента в ~/.claude; verify — боевой прогон на milestone 1
      AI_analyst_sgr (заодно закрывает долг «normalized SQL валидируется / оригинал исполняется»)
- [ ] Каждая правка канона = commit dot-claude + devlog-запись лаборатории

### Session 2 — 2026-06-10 (Phase 1: R1+R2+R3 + боевой verify R2)

**Done & measured**

| Артефакт | Метрика | Target | Hit |
|---|---|---|---|
| R1 operator-playbook.md | 99 строк, full paths, 7 разделов жизненного цикла, ссылки не копии | ≤150 строк | ✅ |
| R2 /external-audit + 3 агента | command 78 строк + 3 agent-def (79–85 строк); вердикт-контракт с jq-валидацией, унифицирован с CRITIC.json (lowercase enums, arrays) | существует + контракт | ✅ |
| R3 harness-evolution.md | 53 строки (D-цикл + strip-ревизия), D3-минимум | ≤1 reference | ✅ |
| commit dot-claude | 9a215c3, 9 файлов, 480 insertions; .gitignore whitelist += agents/ | закоммичено | ✅ |
| R2 БОЕВОЙ прогон на milestone-1 SGR | 3 роли параллельно → adjudication → AUDIT-VERDICT.json | вердикт без ручной доводки | ✅ |

**Discovered (главное)**
- **`/external-audit` поймал verified CRITICAL, который пропустили ВСЕ предыдущие слои**
  dogfood'а (F4-hardening + lab security review + self-Evaluator ×2 + reader/executor аудиты
  F6): обход SQL-денлиста через quoted identifier — `SELECT "DBMS_RANDOM".VALUE() FROM dual`
  проходит validate_sql и исполняется Oracle (демо на живом стеке). Прямое доказательство §8
  и всего регламента: полностью внешний 3-ролевой аудит ловит то, что self-orchestrated не видит.
- **Adjudication-контракт сработал как задумано**: evidence-executor CONFIRMED (продукт
  работает, golden-числа пере-выведены до копейки) + code-refuter REFUTED (verified critical)
  не конфликтуют — измеряют разные поверхности («работает ли» vs «безопасно ли»); правило
  «verified-critical ⇒ refuted» дало корректный итог без ручной доводки.
- **Закрыт открытый долг F6**: validate-vs-execute divergence (нормализованный валидируется /
  оригинал исполняется) — оба аудитора подтвердили реальность, но fail-closed (ORA-00911 на
  non-ASCII); minor, не critical. Долг провенанса golden-чисел — тоже подтверждён (minor).
- Agent type из `~/.claude/agents/` НЕ резолвится в `subagent_type` Task-tool'а из другого
  проекта (доступны только built-in + lab-local agents). Обход: spawn `general-purpose` +
  первой строкой prompt'а «прочитай ~/.claude/agents/<role>.md и следуй буквально». `/external-audit`
  как slash-command увидит глобальные агенты нормально (оператор запускает командой, не Task'ом).

**Blockers** — (none)

**Next session targets** (measurable)
- [ ] R4: пути в hooks/settings.json → `$HOME`/`$CLAUDE_PROJECT_DIR`; README += marketplace.json/
      plugin.json + re-pin процедура; `claude --print` smoke
- [ ] Phase 2: bump v1.0.0→v1.1.0 синхронно plugin.json+marketplace.json, проверить факт
      «plugin несёт commands+agents» (assumption из Phase 0); 3 пути доставки в README

## Decisions so far

- **D1 (доставка): 3 пути, ОДИН plugin.** git clone dot-claude (свои машины, дефолт) +
  plugin claude-code-harness v1.1.0 расширенного состава (чужие/вторые профили) +
  оффлайн-архив git archive (рабочая банковская машина). Не дробить на несколько plugins.
- **D2 (аудит): command + 3 агента.** `/external-audit` в ~/.claude/commands/ +
  evidence-executor / process-auditor / refuter в ~/.claude/agents/; контракт вердиктов
  унифицировать с CRITIC.json (discovery-critic). Запуск — оператором из свежей сессии.
- **D3 (канонизация): минимум.** Только harness-evolution.md (процедура D-циклов) как
  reference kit'а. testing.md / api-constraint / docs-discipline / Layer A — НЕ переносить
  (дубли baseline §1–§8, tdd-skill и принципа 9 SKILL.md; Layer A завязан на lab-фикстуры).
- **D4 (journal): opt-in опция Phase 5.** Строка в playbook/checklist, дефолт off; в своих
  проектах включать пока живы D-циклы; в T3 — обязателен (источник D.3).
- **D5 (полигон n=2): prompt-validation тулза.** Новый мини-репо из реальной боли:
  ~15 ad-hoc скриптов промпт-валидации в AI_analyst_migration/dev/ (prompt_lab, measure_*,
  batch-прогоны, CSV-сравнения) → продукт «batch-прогон вопросов + сравнение прогонов +
  отчёт регрессий», 4–6 фич. Старт после Phase 2.

## Assumptions (проверить по ходу)

- На рабочей (банковской) машине есть Claude Code — оператор не опроверг при D1; если нет,
  путь (3) сводится к переносу архива без plugin-механики. Проверить до P2.
- Plugin-формат умеет нести commands и agents помимо skills — проверить фактом при P1
  (если нет — agents/command едут только путями clone/архив, plugin остаётся skill-only).

## Risks status

| ID | Risk | Status | Notes |
|---|---|---|---|
| R1 | Over-canonization | mitigated | D3 = минимум; Phase 4 strip-ревизия |
| R2 | Продуктовая срочность вытеснит трек | open | T2/T3 несут прямую продуктовую пользу |
| R3 | T2 ломает рабочий проект | open | gap-report → approve до правок; ветка/бэкап; оракул до/после |
| R4 | Анкоринг автора регламента | open | T4 строго внешний + исполняющий |
| R5 | Пути/оффлайн сломают доставку | open | R4-гигиена, P2, T1 на чистом профиле |
