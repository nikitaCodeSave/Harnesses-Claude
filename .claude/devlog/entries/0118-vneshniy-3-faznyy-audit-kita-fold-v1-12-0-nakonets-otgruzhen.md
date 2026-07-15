---
id: 118
date: 2026-07-15
title: "Внешний 3-фазный аудит кита → fold: v1.12.0 наконец отгружен, supply chain починен, уроки #115 доставлены"
tags: [harness, audit, kit, release, supply-chain, currency, guard]
status: complete
---

# Внешний аудит кита (9 срезов × adversarial verify) → исполнение доработок

## Контекст

Оператор запросил независимый fresh-context аудит двух артефактов (кит
`~/.claude/skills/claude-code-harness/` + глобальная обвязка `~/.claude/`) по осям
«внутренняя согласованность» и «эмпирика потребителей» (метод devlog #115), с мандатом
менять правила/паттерны при подтверждённом преимуществе. Прогон: dynamic workflow
(`ultracode`) — 9 finder-срезов → скептик-опровергатель на каждую находку → completeness
critic; 58 агентов, ~2.9M токенов; 1 находка REFUTED, 10 WEAKENED, остальные CONFIRMED.
Затем — исполнение всех доработок в этой же сессии (верификация — бинарь 2.1.210 strings +
живой changelog + first-party доки через 2 verifier-агентов).

## Главный вывод аудита

Контент кита в основном здоров, канон потребителями исполняется (Greenplun-пара местами
жёстче канона) — критический дефект был в **дистрибуции**: supply chain разорван на три
слоя (GitHub = v1.9.0 от 13.06 с ретрагированным ложным caveat #49947; локальный commit =
v1.10.1; worktree = uncommitted «v1.12.0» 13 дней; v1.11.0 — фантом, отгруженный
потребителям мимо VCS). Плюс: метрика «progress 0/32» в #115 **фактологически ложна**
(9 файлов в 4 проектах, ≥4 существовали к дате #115 — сам #115 внутренне противоречив);
«3/3 проекта ловит silent-wrong» — конфляция двух классов ROI (реальная база: 2 прода /
3 CRITICAL-катча + 11062026 design-vetting отдельным классом).

## Что сделано (fold)

### A. Supply chain / release (CRITICAL → закрыт)
- **dot-claude запушен**: origin/main = v1.12.0 (было 5 незапушенных коммитов + uncommitted
  дельта); манифесты синхронизированы (plugin.json = marketplace.json = 1.12.0); теги
  бэкфилл v1.9.1/v1.9.2/v1.10.0/v1.10.1 + v1.12.0 (24 тега на remote).
- **Release-ритуал механизирован**: `~/.claude/scripts/kit-release.sh` (sync обоих
  манифестов — plugin.json канон/update-cache-key per first-party plugins-reference;
  stamp-check изменённых project-docs; staged + печать commit/tag/push). SKILL.md
  Maintenance обновлён: «release существует только committed+tagged+pushed».
- **Ре-синк потребителей** (verbatim, hand-edits предварительно исключены diff'ом):
  11062026 v1.9.0→канон (ушёл отозванный caveat #49947), Greenplun + Greenplun-router
  workflow.md фантом-v1.11.0→v1.12.0. Коммиты в их репо — за оператором.

### B. Currency кита → CC 2.1.210 (сверено с бинарём + first-party)
native-capabilities.md: заголовок 2.1.210/Claude 5 family; **Sonnet 5 default по
account-типам** (Pro/Team Standard/Enterprise seats; Max/Premium/PAYG = Opus 4.8; Fable
нигде не default — model-config verbatim); **Explore наследует main-модель с 2.1.198**
(было «Haiku» — фактическая ошибка); **`/agents` wizard удалён 2.1.198** (смотреть
`/context`/`.claude/agents/`); catch-all `claude` dispatch-тип (agent-view док); **Manual**
rename (2.1.200); classifier→Sonnet 5 (2.1.210); **Agent SDK credit исправлен на PAUSED**
(кит месяц отгружал опровергнутый факт вопреки собственному re-check 17.06); plugin
version = update cache key. **`/review`→`/code-review` по всей лестнице** (7 файлов:
на 2.1.210 `/review` = строго PR, бинарь сам редиректит). Refresh-ledger
harness-evolution → 2.1.210/2026-07-15; штампы harness-discipline/audit-checklist/
evidence-base пересведены.

### C. Уроки #115 доставлены на все поверхности (были только в uncommitted-ките)
- **Урок 1 (per-change для silent-wrong класса)**: глобальный `~/.claude/CLAUDE.md §8`
  (было «Opt-in, not every task» — урок туда не доехал вовсе) + practice-baseline §8 +
  shipped workflow.md ladder. База скорректирована: 2 прода/3 инцидента, «3/3» — конфляция.
- **Урок 2 (continuity: carrier ≠ mandate)**: shipped workflow.md §Continuity («lever =
  state-on-disk, форматы = default not mandate») + practice-baseline §6 + bootstrap
  Phase 5 (девлог-или-commit-дисциплина); hedge был только в kit-internal harness-discipline.
- practice-baseline ре-дистиллирован против живого глобального файла (+§1 negative-search,
  +§2 recommendation-triage); в Maintenance закреплён sync-ритуал baseline→кит.

### D. Дыры аудит-чеклиста и контрактов
- audit-checklist §9: **sweep корня на `.claude`-sibling снапшоты** (класс
  `.claude.original/` battletest'а был вне scope); §3: карваут для собственных
  external-audit ролей кита (иначе механический §3 флагает сам кит).
- Мёртвые `CRITIC.json`-ссылки убраны из 3 agent-контрактов; пути команды унифицированы
  `.claude/audit/`→`.claude/audits/` (lab-конвенция); граница `ultrareview` (платный
  cloud diff-review) vs `/external-audit` (subscription-local deliverable-аудит)
  артикулирована в native-capabilities.
- Bootstrap: SessionStart-hook rationale переписан (кит хук НЕ отгружает — у юзера его
  нет); duty-line «Size the change» добавлена в CLAUDE.md-шаблон + Phase 7 grep.

### E. Правки правил/паттернов (мандат оператора, по подтверждённой эмпирике)
- **CLAUDE.md §7 приведён к правде**: guard = DENY-only, «prompts on risky» удалено
  (живой прогон: все 4 заявленных prompt-кейса проходили молча — prompt-tier не существовал).
- **system-guard сужен до документированного scope**: `rm -rf ~/subdir` больше не
  DENY (абсолютный эквивалент никогда не гейтился → нулевая защита, чистый friction);
  ДОБАВЛЕНО покрытие абсолютного home-корня `/home/<user>` (реальный gap) + глоб-формы
  `~/*`, `$HOME/*`. Тест-suite расширен 29→38 кейсов, **38/38 PASS**.
- Строково-литеральный over-block (heredoc/кавычки) оставлен осознанно — residual
  задокументирован в header'е guard'а (deny прозрачен, кейс редок).

### F. Memory-коррекции
- `feedback_continuity_format_friction`: «progress 0/32» → «заводят, но не закрывают»
  (9 файлов/4 проекта); adoption-знаменатель уточнён (живой парк ≈19/31, devlog ≈26%).
- `reference_critique_fresh_context_lever`: конфляция «3/3» скорректирована; отмечен fold.
- `reference_agents_surfaces`: /agents wizard removed 2.1.198. MEMORY.md-строки обновлены.

## Проверка
- system-guard: 38/38 PASS (`benchmark/audit/test-system-guard.sh`, включая новые
  home-root/subdir кейсы и негативные регрессии).
- jq-контракт external-audit: синтетическое трио AUDIT-*.json + VERDICT против гейтов
  всех 3 ролей + adjudicator-схемы — 5/5 PASS (включая негативный контроль bad-enum).
  Закрыта дыра критика «контракт ни разу не исполнялся».
- Кит: grep 2.1.195/2.1.173/Sonnet 4.6/CRITIC/`/review`-as-diff-rung = 0 хитов;
  манифесты jq-valid и равны 1.12.0; push verified (`git ls-remote` = 24 тега,
  origin/main = HEAD).
- Fresh-context smoke-тест скилла (worktree-агент, 5 probe + staleness-grep):
  **5/5 PASS**; единственный найденный stale-остаток (bootstrap Phase 0 «interactive
  /agents») закрыт патчем **v1.12.1**, выпущенным end-to-end через новый
  kit-release.sh — заодно живая e2e-валидация самого ритуала (запушен, тег на remote).
- Все новые фактические клеймы сверены: changelog verbatim (2.1.197/198/200/210) +
  strings бинаря 2.1.210 + live-fetch code.claude.com (sub-agents, plugins-reference,
  commands, hooks, memory, model-config) + anthropic.com news/engineering.

## Related
- #115 — эмпирический аудит (источник уроков; его метрика progress исправлена здесь)
- #116 — upstream-гейты (объявлял «v1.12.0 SHIPPED» — фактически отгружен только сейчас)
- #117 — fresh-context аудит лаборатории (актуализация 2.1.210 лаборатории; здесь — кита)
- #62/#65 — fresh-context lever (усилен до per-change для silent-wrong класса)
