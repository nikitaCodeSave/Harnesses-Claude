# Harnesses-Claude

**Лаборатория R&D дизайна harness'а для Claude Code.** Выводы model-agnostic; актуальный срез версий и built-in'ов — единственный version-pinned файл лабы, `.claude/docs/native-capabilities.md`.

> ⚠️ **Это лаборатория, а не шаблон.** `.claude/` здесь содержит исследовательскую
> машинерию (`benchmark/`, замороженные архивы `docs/archive/`, `devlog/`, `audits/`),
> которую **нельзя копировать целиком** в рабочий проект. В проекты едет только измеренный
> минимум — плагин `harness` из `~/PROJECTS/claude-code-harness` (один скилл и три шаблона;
> фраза «set up Claude Code harness in this project» — для нового проекта, существующего и
> большого многосоставного), а не клон этого репозитория.

## Что это

Репозиторий, в котором эмпирически выращивается ответ на один вопрос: **какой минимум
обвязки даёт максимум продуктивности под способной моделью.** Здесь живут принципы,
бенчмарки, решения (ADR) и замороженный архив — закрытый журнал (149 devlog-записей) и прошлые
эксперименты, на которых обкатывается и калибруется канон, отгружаемый в другие проекты через плагин.

## Центральный принцип

> **Под способной моделью минимум обвязки даёт максимум продуктивности.**
> (model-agnostic — не пере-привязывать к версии при апгрейде)

Каждый компонент harness'а кодирует assumption «модель не умеет X». Если модель уже делает
X нативно (выбрать вменяемый стек, проверить перед claim'ом «готово», уважать permissions,
дёрнуть нужный tool) — компонент **не добавляется**. «Harness тяжело растить» почти всегда
значит, что обвязка переросла реальные пробелы модели.

**Мета-уровень:** main thread = meta-orchestrator. Его задача — не писать код напрямую, а
**конфигурировать окружение** Claude Code (preload context, constraints, паттерны
делегирования) перед тем как inner executor начнёт писать код. Skill / agent / hook как
**environment configurator** — допустимы; как дубль built-in'а или самоописание роли main
thread'а — anti-pattern.

## Лаборатория vs отгружаемый канон

| | Где | Что |
|---|---|---|
| **Кит** (отгружается) | плагин `harness`, репо `~/PROJECTS/claude-code-harness` | один скилл: читает репо и выбирает путь (новый / существующий / с harness'ом), ставит корневой `CLAUDE.md` с блоками *How we work* и *Project knowledge*, `settings.json`, `CLAUDE.md` компонентов, подключает `mattpocock-skills`. Ни агентов, ни команд, ни хуков; каждая строка шаблона опирается на замер `benchmark/pipeline-ab/` |
| **Глобальный слой** | `~/.claude/` | `CLAUDE.md` нет — решение оператора: строка появляется в нём только через `/retro`, когда её отсутствие навредило там, где у неё нет другого носителя. В `settings.json` — приватность и прокси, запрет `/tdd`, автообновление `mattpocock-skills`; скилл `harness` — симлинк на рабочую копию кита |
| **Лаборатория** (этот репо) | `.claude/` | R&D-машинерия: эволюция канона, бенчмарки, ADR, замороженные архивы — **не копируется** |

## Структура репозитория

```
AGENTS.md                — операционные заметки для агентов любого вендора: команды, границы, конвенции
WORKFLOW.md              — портативный human-facing гайд: старт → требования → дизайн → Spec→Build→Review → continuity
docs/typesafe/           — снимок документации TypeSafe (Jev)
integrations/typesafe/   — песочница интеграции TypeSafe (свой uv-проект)
.claude/
├── CLAUDE.md            — мета-оркестраторские инструкции (принцип, anti-patterns, API/built-ins/spawn-policy)
├── settings.json        — permissions (allow / ask / deny); хуков нет
├── docs/                — 13 активных reference-доков + adr/ (действующие решения) + archive/ (frozen ADR-лог, baseline'ы, прошлые эксперименты)
│                          principles · harness-architecture · harness-evolution · native-capabilities
│                          · workflow(+async/orchestration/cloud/evolution) · multi-agent · memory-layers
│                          · benchmark · external-sources
├── rules/               — 3 инварианта: api-constraint · testing · docs-discipline
│                          (проектных hooks/commands нет)
├── devlog/              — замороженный журнал; решения — docs/adr/
├── benchmark/           — 4-layer измерительная методология (structural → behavioral → trajectory → statistical),
│                          A/B-стенды с RESULTS.md (pipeline-ab, guard-ab, spec-upstream-ab), text2sql-оракулы
├── memory/              — локальные JSONL event-логи (gitignored; ни один хук их не пишет)
├── audits/              — provenance независимых аудитов (отчёты, JSON-вердикты, логи), frozen
├── plans/               — долгоживущие планы (in-flight состояние держит открытая спека)
└── worktrees/           — эфемерные git-worktree'ы (gitignored)
```

## Как это работает

**Spine — Spec → Build → Review** (дефолт для нетривиальной задачи, помещающейся в одну сессию;
typo/one-liner — сразу Build → Review). Выбран замером `.claude/benchmark/pipeline-ab/` против ванили,
четырёхстадийного потока и пайплайна Pocock:

- **Spec** — интервью, пока модель не сможет написать спеку, затем `SPEC.md`: acceptance
  criteria (= оракул, против которого крутится Review), интерфейс из запроса дословно, ограничения
  scope, non-goals, ADR если объяснение решения заняло бы >5 мин. Человек читает короткую спеку,
  а не длинный план.
- **Build** — в той же сессии, что писала спеку, один main thread (1M контекст). Порядок тестов и
  кода не предписывается (TDD не требуется — `.claude/rules/testing.md`), тест обязан быть способен упасть, «готово» — с командой и
  выводом. Subagent — только при изоляции шумного вывода / параллельности / независимом ревью.
- **Review** — `/code-review` на substantive change; по уровню риска — одно ревью ветки свежим
  контекстом против `SPEC.md`, только корректность, ≤3 раундов. «Looks done ≠ is done».
- **Эскалация Check** — работа не помещается в одну сессию или silent-wrong класс: критерии из
  спеки превращаются в приёмочные тесты отдельным контекстом до свежей сборки, read-only
  для исполнителя deny-правилом.
- **Долгий проект** (месяцы, много сессий) — та же спина плюс лёгкие правила знаний в `CLAUDE.md`
  (`GLOSSARY.md`, ADR включая решения «на будущее», читать перед работой); инструменты Pocock — по
  триггеру: фича больше сессии, туман, `/retro`. `.claude/docs/workflow.md` § Долгий проект.

**Лестница верификации** (cheapest → strongest): in-prompt check → `/goal` → Stop-hook →
`/code-review` → fresh-context критик / dynamic workflow.

**Как работать** — блок *How we work* кита (каждая строка опирается на замер или first-party
источник) и пошаговый мануал кита `docs/manual.md`. Поведенческого baseline в глобальном слое нет.

Полная развёртка — [`WORKFLOW.md`](WORKFLOW.md).

## Как канон эволюционирует

Эволюция канона идёт по эмпирическим сигналам (не по вкусу), **model-agnostic** и
**evidence-gated** — single-incident в invariant не превращается. Две операции + provenance:

- **Refresh-ledger** — штамп последней точки заземления по каждой оси (CC-примитивы · модели ·
  подходы: версия, дата, проверенные источники); сам штамп живёт в
  `native-capabilities.md`, единственном файле с версиями. Дельта `claude --version` против ledger — самостоятельный
  триггер ревизии.
- **D-цикл** (≈1 сессия, на milestone-close) — fold доказанных находок внутрь канона:
  собрать → классифицировать (`kit-gap` / `project-specific` / `single-incident` / `noise`) →
  gate (только `kit-gap` с multi-source evidence) → point-edit reference → commit (+ ADR, если это решение).
- **Strip-ревизия** (раз в 3–6 мес / major-релиз модели / дельта CC-версии), два прохода:
  **external-intake** (что сдвинулось снаружи: changelog, first-party docs, essays — по дельте
  от ledger) → **re-test** (что из канона устарело: `claude --safe-mode` как быстрый тест
  «модель или обвязка»; устаревшее удаляется, не архивируется).

Дисциплина — `.claude/docs/harness-evolution.md`.

## Constraints

- **API:** строго CLI-подписка Claude Code. Anthropic API, managed-agents, beta headers,
  `--bare`, `--max-budget-usd` — **out of scope** (`.claude/rules/api-constraint.md`).
- **Built-ins first:** перед любым custom-субагентом — сверка с инвентарём в
  `native-capabilities.md`. Пять специалистов (Explore, Plan, general-purpose,
  statusline-setup, claude-code-guide) дублировать нельзя; шестой, catch-all `claude`, —
  дефолт фонового dispatch.
- **Single-agent default:** один main thread — дефолт для most coding. Bounded fan-out —
  только когда scope превышает один контекст, и тогда через **dynamic workflows** (keyword
  `ultracode`), а не кастомный subagent-pipeline.

## Точки входа

| Хочешь | Читай |
|---|---|
| Полный workflow разработчика | [`WORKFLOW.md`](WORKFLOW.md) |
| Принцип, anti-patterns, spawn-policy | [`.claude/CLAUDE.md`](.claude/CLAUDE.md) |
| Машинный routing-spine | `.claude/docs/workflow.md` |
| Действующие решения | `.claude/docs/adr/`; хронология — замороженный архив `.claude/devlog/` (`tldr.md`) |
| Поставить harness в проект (новый, существующий, большой) | плагин `harness`: «set up Claude Code harness in this project» |
