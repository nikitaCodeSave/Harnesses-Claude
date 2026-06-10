---
plan: .claude/plans/standard-v1-regulation.md
last-updated: 2026-06-10
status: active
session-count: 4
---

# Прогресс: Регламент v1 — сборка и тестирование единого стандарта

## Quick state — Регламент v1 RELEASED (plugin v1.3.0, tag создан, dot-claude 5f9734e, devlog #86): Phase 3 закрыта T1✅ T2✅(корзина A; B/C ждут approve) T3✅(confirmed_with_debt) T4✅(confirmed_with_debt, 0 blockers) + Phase 4 D.3 fold выполнен (2 major + 7 minor T4-находок в канон, 3 T3-journal находки в канон, strip: нечего удалять) · ОСТАЛОСЬ ОПЕРАТОРУ: (1) push dot-claude main + теги v1.2.0/v1.3.0; (2) approve корзин B/C gap-report'а migration + ревью незакоммиченной корзины A в working tree; (3) 1-строчный фикс pre-existing red в migration (test_settings 0.5≠0.7) — тогда init.sh зелёный; (4) push lab · блокеров нет

## Phase checklist

### Phase 0 — Scope-фиксация (2/2 done)
- [x] Grill по D1–D5 — все решены (см. Decisions), 2026-06-10
- [x] Progress-файл заведён (этот файл); отдельный features-ledger не нужен —
      verify-шаги несёт сам план

### Phase 1 — Сборка содержания (4/4 done)
- [x] R1 Operator playbook (99 строк, references/operator-playbook.md) — 2026-06-10
- [x] R2 /external-audit: command + 3 агента (evidence-executor/process-auditor/code-refuter),
      контракт вердиктов унифицирован с CRITIC.json; БОЕВОЙ прогон на milestone-1 SGR прошёл,
      поймал verified CRITICAL — 2026-06-10
- [x] R3 harness-evolution.md (D-циклы + strip) как reference kit'а — 2026-06-10
- [x] R4 Гигиена: settings.json пути → `$HOME/.claude`; README += манифесты + re-pin + 3 пути;
      R6 (резолвинг аудит-ролей) сделан здесь же — commit 2e4a1f2, devlog #84 — 2026-06-10

### Phase 2 — Упаковка (3/3 done)
- [x] P1 plugin v1.0.0→v1.1.0 синхронно (plugin.json+marketplace.json), оба validate — 2026-06-10
- [x] P2 три пути доставки в README: git clone / plugin install / оффлайн-архив — 2026-06-10
- [x] Перенос command+agents ВНУТРЬ `skills/claude-code-harness/{commands,agents}/` — решён
      эмпирикой T1 и реализован (v1.2.0, dot-claude 6036560): конфликт clone-vs-plugin снялся
      переносом без дублирования (skills-dir автозагрузка несёт то же, что plugin install);
      роли резолвятся нативно `claude-code-harness:<role>` — 2026-06-10

### Phase 3 — Тестирование (1/4)
- [x] T1 smoke чистого профиля — PASSED с правками; провенанс: `.claude/audits/t1-smoke/`
      (10 логов + T1-REPORT.md); 3 чистых профиля, bootstrap по quick start сработал
      (skill-триггер доказан transcript'ом); v1.2.0 re-smoke: Skills 2 / Agents 3 — 2026-06-10
- [x] T2 Audit-режим на AI_analyst_migration — gap-report 24 гэпа (5 A / 13 B / 6 C) в
      `migration/.claude/audit/gap-report-2026-06-10.md` + lab `.claude/audits/t2-migration/`;
      корзина A применена (G1 permissions, G2 init.sh-оракул, G3 features.json, G4 progress/,
      G5 gitignore) БЕЗ коммитов, оракул identical до/после (1397 passed + 1 pre-existing fail
      на HEAD: test_settings response_temperature 0.5≠0.7 — НЕ от правок); scope-чист по git diff;
      **корзины B (13 reversible) и C (6 destructive per-component) — ЖДУТ approve оператора** —
      2026-06-10
- [x] T3 n=2: prompt-regress (`~/PROJECTS/prompt-regress`) — bootstrap по playbook (commit 49cefce)
      → F1 promptdiff compare строгим TDD (RED-коммит 4a7eb18 до реализации → GREEN c328f5a,
      17/17, smoke на реальных прод-CSV, exit-code контракт 1/0/2) → fresh-context Evaluator:
      **confirmed_with_debt** (major: CI-gate нем на 4-кол. экспорте — долг в progress
      «reproduce→close»); harness-journal: 6 наблюдений «kit-не-хватило» — 3 уже зафолжены в канон
      (dot-claude 8b809be: canonical features.json schema, per-runner empty-suite guard,
      contract-vs-disk rule) — 2026-06-10
- [x] T4 внешний walkthrough-аудит — 2 наивных исполнителя (новый проект ∥ легаси,
      исполнением: bootstrap+Phase 5+TDD-микрофича / fabricated-легаси+audit-режим+§5-§7)
      → adjudication R2: **confirmed_with_debt, 0 blockers**, 2 major + 10 minor, 0 dismissed;
      `AUDIT-VERDICT.json` + `T4-REPORT.md` в `.claude/audits/t4-walkthrough/` — 2026-06-10

### Phase 4 — D.3 и релиз (3/3 done)
- [x] Находки T1–T4 → канон: T4 2 major (README→playbook entry-point; approval-gate headless
      резолюция) + 7 minor (Phase 0 git-guard, Phase 7 crisp criteria, §2 ledger ownership,
      §3 PATH-hygiene, §4 SKILL.md routing, external-audit legacy-branch + ROLE_DIR role-files
      + plugin-list pre-flight, harness-evolution journal-less trigger); 1 minor skipped как
      single-incident (src-layout/conftest — watch). T3-journal 3 находки зафолжены ранее
      (8b809be) — 2026-06-10
- [x] Финальный bump v1.2.0→v1.3.0 синхронно, оба манифеста validate, tag
      `claude-code-harness--v1.3.0`, re-smoke на чистом профиле (лог 11: Skills 2 / Agents 3),
      commit dot-claude 5f9734e + сводный devlog #86 — 2026-06-10
- [x] Strip-ревизия: всё добавленное в Phase 1 использовано (playbook = объект T4,
      harness-evolution = источник §6-§7 walker'ов, /external-audit = боевой прогон + T1,
      ROLE_DIR fallback = страховка локальных ролей) — удалять нечего — 2026-06-10

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

**Приоритизация оператора 2026-06-10:** фокус = регламент + harness. **Track A (прод-расследование
migration) ИСКЛЮЧЁН из трека** — security-находка прода сохранена в memory
`security-sql-validator-quoted-bypass` (R7) для отдельной работы, к регламенту не относится.
**Track B (фикс SGR CRITICAL)** понижен до ОПЦИОНАЛЬНОГО worked-example: не блокер релиза v1; если
нужен живой пример «петля замыкается» для playbook — сделать reproduce→close в SGR; иначе F4 SGR
остаётся REFUTED как honest open-debt (зафиксировано аудит-артефактом). Решение по B — за оператором.

**Основная линия — Track C (регламент). Next session targets (порядок по приоритету):**
- [ ] **R6 ПЕРВЫМ (функц. дефект ключевой фичи):** `/external-audit.md` должен сам спавнить
      `general-purpose` + «прочитай ~/.claude/agents/<role>.md и следуй буквально» — agents из
      `~/.claude/agents/` НЕ резолвятся как `subagent_type` Task'а из чужого проекта. Без этого
      plugin-доставленный аудит не заработает в целевом проекте. Зашить в команду, не в заметку.
      Verify: спавн-блок присутствует в external-audit.md; smoke — команда видит 3 роли.
- [ ] **R4:** пути в hooks/settings.json → `$HOME`/`$CLAUDE_PROJECT_DIR`; README += marketplace.json/
      plugin.json + re-pin процедура; `claude --print` smoke.
- [ ] **Phase 2 (P1+P2):** bump v1.0.0→v1.1.0 синхронно plugin.json+marketplace.json; проверить
      факт «plugin несёт commands+agents» (assumption Phase 0; если нет — agents/command едут
      clone/архивом, plugin skill-only); 3 пути доставки в README; tag.
- [ ] Каждая правка канона = commit dot-claude + devlog-запись лаборатории.

### Session 4 — 2026-06-10 (Phase 3: T1 smoke + эмпирическое закрытие Phase 2)

(Session 3 — R4+R6+P1+P2, commit 2e4a1f2 — залогирован в Quick state и devlog #84,
отдельной session-записи не имел.)

**Done & measured**

| Артефакт | Метрика | Target | Hit |
|---|---|---|---|
| T1 smoke: 3 чистых профиля (mktemp CLAUDE_CONFIG_DIR) | marketplace add → install → details: exit=0 каждый; провенанс 10 логов + T1-REPORT.md в `.claude/audits/t1-smoke/` | установка одной командой + артефакт | ✅ |
| Bootstrap по quick start на чистом профиле | plugin-skill триггернулся (Skill-вызов в transcript), CLAUDE.md 30 строк + .gitignore + settings.json | skill срабатывает, минимум создан | ✅ |
| Эмпирика упаковки (CFG2, тестовый marketplace) | commands+agents внутри plugin-дира: Skills 2 / Agents 3; роли резолвятся как `subagent_type: claude-code-harness:<role>`; команда = `claude-code-harness:external-audit` | факт вместо assumption | ✅ |
| Реализация: v1.2.0 (git mv внутрь плагина) | dot-claude 6036560 + tag `claude-code-harness--v1.2.0`; оба манифеста validate; re-smoke CFG3: Skills 2 / Agents 3; skills-dir на основном профиле несёт то же | оба пути доставки без дублирования | ✅ |
| Bonus-фикс | YAML frontmatter `/external-audit` был невалиден (двоеточие в plain scalar argument-hint) — runtime молча дропал метаданные; пойман `claude plugin validate`, исправлен квотированием | validate ✔ | ✅ |

**Discovered**
- Роли из плагина — полноценные agent-типы (`claude-code-harness:<role>`) даже на чистом
  профиле → R6-обход (general-purpose + чтение role-файла) нужен только как fallback;
  шаг 1 `/external-audit` переписан native-first.
- Конфликт «git-clone корень vs plugin-поддиректория» снимается ПЕРЕНОСОМ (не дублированием):
  `~/.claude/skills/<kit>` автозагружается как `@skills-dir` plugin и несёт commands+agents.
- Headless-граница bootstrap'а: в `--print --permission-mode acceptEdits` запись
  `.claude/settings.json` блокируется permission-слоем («settings files are protected») —
  в интерактиве это обычный approve; для headless-прогонов нужен bypass.
- `claude plugin validate` ловит то, что runtime глотает молча (frontmatter) — добавить
  в релизный ритуал README уже отражено.
- Цена доставки аудита plugin-потребителю: always-on ~211 → ~530 tok.

**Blockers** — (none)

**Next session targets**
- [ ] T2: audit-режим на AI_analyst_migration — gap-report → approve оператора → правки
      отдельными сессиями (только `.claude/`+CLAUDE.md+docs; ветка/бэкап; оракул до/после)
- [ ] T3 (∥ T2): bootstrap n=2 prompt-validation тулзы строго по playbook, journal обязателен
- [ ] push dot-claude commit 6036560 + tag claude-code-harness--v1.2.0 — за оператором

### Session 5 — 2026-06-10 (T2∥T3 → T4 → Phase 4: мультиагентные workflow, релиз v1.3.0)

**Done & measured**

| Артефакт | Метрика | Target | Hit |
|---|---|---|---|
| WF1: T2 gap-report (6 read-only аудиторов ∥ + synthesizer) | 24 гэпа (5 A / 13 B / 6 C), per-component вердикты 7 agents + 13 skills; отчёт в migration и lab | gap-report по шаблону SKILL.md | ✅ |
| WF2a: корзина A применена | 6 файлов ровно по scope (git diff), оракул identical до/после (1397 passed + 1 pre-existing fail HEAD), без коммитов | оракул не хуже + scope чист | ✅ |
| WF2b: T3 полный цикл | bootstrap 49cefce → F1 RED 4a7eb18 → GREEN c328f5a (17/17, smoke на прод-CSV, exit-коды 1/0/2) → Evaluator confirmed_with_debt | первая фича passes без ручного изобретательства | ✅ |
| WF3: T4 walkthrough (2 наивных исполнителя ∥ + adjudicator R2) | confirmed_with_debt, 0 blockers, 2 major + 10 minor, 0 dismissed | вердикт по контракту R2 | ✅ |
| D.3 fold | 2 major + 7 minor T4 + 3 T3-journal → канон (8b809be, 5f9734e); 1 single-incident → watch | gate «single-incident ≠ invariant» соблюдён | ✅ |
| Релиз | v1.3.0 sync, validate ✔✔, tag, re-smoke чистый профиль (лог 11) | версии синхронны + tag + smoke | ✅ |

**Discovered (главное)**
- Метрика M-готовности T3: 6 наблюдений «kit-не-хватило» за milestone (3 kit-gap → fold,
  3 project/single-incident); ручного изобретательства, ломающего цикл, — 0.
- T4 подтвердил R4-страх оператора ровно там, где ожидался: легибельность точки входа
  (README не вёл к playbook) — теперь зашита явная секция «Вход в регламент».
- Pre-existing red в migration (test_settings 0.5≠0.7 на HEAD) — находка оракула G2,
  не следствие правок; доказывает ценность init.sh немедленно после установки.

**Blockers** — (none) · далее — операторские шаги из Quick state

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
| R5 | Пути/оффлайн сломают доставку | closed (T1) | smoke 3 чистых профиля прошёл; оффлайн-путь (архив) остался на T-проверку при случае |
| R6 | Plugin-доставленный /external-audit не заработает в целевом проекте (agents не резолвятся cross-project) | closed (T1) | роли в плагине резолвятся нативно `claude-code-harness:<role>`; fallback general-purpose+role-file сохранён |
| R7 | Прод-валидатор migration уязвим к тому же классу (Track A) | open | проверить EXECUTE-привилегии Oracle-юзера до выводов; security-auditor agent + rule security-critical |
