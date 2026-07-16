# Harnesses-Claude

**Лаборатория R&D дизайна harness'а для Claude Code** — поколение Fable 5 + Sonnet 5 + Opus 4.8 / Claude Code 2.1.211.

> ⚠️ **Это лаборатория, а не шаблон.** `.claude/` здесь содержит исследовательскую
> машинерию (`benchmark/`, discovery-критиков, event-логи, архивный `docs/archive/loop-2026-05/`),
> которую **нельзя копировать целиком** в рабочий проект. Отгружаемое каноничное знание о дизайне
> harness'а живёт в отдельном **глобальном скилле** `~/.claude/skills/claude-code-harness/`
> (плагин `claude-code-harness` v1.10.0); минимальный стартовый harness для нового проекта —
> его **Bootstrap-режим**, а не клон этого репозитория.

## Что это

Репозиторий, в котором эмпирически выращивается ответ на один вопрос: **какой минимум
обвязки даёт максимум продуктивности под способной моделью.** Здесь живут принципы,
бенчмарки, журнал решений (116 devlog-записей) и архив ретайренных экспериментов, на которых
обкатывается и калибруется канон, отгружаемый в другие проекты через плагин.

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
| **Канон** (отгружается) | `~/.claude/skills/claude-code-harness/` (v1.10.0) | bootstrap / audit / extend / explain режимы; `references/` (native-capabilities, harness-discipline, practice-baseline §1–8, harness-evolution, evidence-base); shipped project-docs |
| **Practice baseline §1–8** | operator-global `~/.claude/CLAUDE.md` | think-first · simplicity · surgical · goal-driven · testing · continuity · guardrails · independent-verification. Применяется во всех проектах, **не дублируется** в каждый репо |
| **Лаборатория** (этот репо) | `.claude/` | R&D-машинерия: эволюция канона, бенчмарки, devlog, архив ретайренных экспериментов — **не копируется** |

## Структура репозитория

```
WORKFLOW.md              — портативный human-facing гайд: старт → требования → дизайн → Plan→Work→Review → continuity
.claude/
├── CLAUDE.md            — мета-оркестраторские инструкции (принцип, anti-patterns, API/built-ins/spawn-policy)
├── settings.json        — permissions (read-only Bash/Read) + hook-конфигурация
├── docs/                — 11 активных reference-доков + archive/ (frozen ADR-лог, baseline'ы, ретайренный loop/)
│                          principles · harness-architecture · workflow(+async/orchestration/cloud/evolution)
│                          · multi-agent · memory-layers · benchmark · external-sources
├── rules/               — 3 инварианта: api-constraint · testing · docs-discipline
│                          (проектных hooks/commands нет — ретайрены 2026-07-15; hooks — глобальные ~/.claude/hooks/)
├── skills/              — 1 action-skill: update-plan-progress (progress-журнал multi-session задач)
├── devlog/              — 116 записей (live + archive/), index.json/tldr.md (авто), rebuild-index.py
├── benchmark/           — 4-layer измерительная методология (static → headless → cross-fixture → smoke), text2sql-оракулы
├── memory/              — JSONL event-логи (session-starts, agent-spawn, denied, …) для continuity
├── audits/              — provenance прогонов /external-audit (AUDIT-*.json + логи)
├── plans/ · progress/   — долгоживущие планы + in-flight состояние (progress gitignored)
└── worktrees/           — эфемерные git-worktree'ы (gitignored)
```

## Как это работает

**Spine — Plan → Work → Review** (дефолт для нетривиальной задачи; typo/one-liner пропускает Plan):

- **Plan** — read-only разведка до первой записи (plan mode / built-in `Plan`-агент). Выход:
  явные acceptance criteria (= оракул, против которого крутится Review), critical files, ADR
  если объяснение решения заняло бы >5 мин.
- **Work** — один main thread на весь lifecycle (1M контекст). Test-driven как runnable-оракул
  (RED → GREEN → refactor, не догма очерёдности; тест обязан быть способен упасть). Subagent —
  только при изоляции контекста / параллельности / compact-rescue.
- **Review** — self-review + tests/lint/type-check всегда; `/code-review` на substantive change;
  **fresh-context критик** (отдельная сессия/subagent, которому велено опровергать) для
  high-stakes. «Looks done ≠ is done».

**Лестница верификации** (cheapest → strongest): in-prompt check → `/goal` → Stop-hook →
`/code-review` → fresh-context критик / dynamic workflow.

**Practice baseline §1–8** (живёт в operator-global, отгружается через канон):
think-before-coding · simplicity-first · surgical-changes · goal-driven · tests-verify-behavior ·
continuity (devlog/progress/memory) · mechanical-guardrails · independent-verification.

Полная развёртка — [`WORKFLOW.md`](WORKFLOW.md).

## Как канон эволюционирует

Эволюция канона идёт по эмпирическим сигналам (не по вкусу), **model-agnostic** и
**evidence-gated** — single-incident в invariant не превращается. Две операции + provenance:

- **Refresh-ledger** — штамп последней точки заземления (`last-grounded: CC v2.1.211 ·
  Fable 5 + Sonnet 5 + Opus 4.8 · дата · проверенные источники`). Дельта `claude --version` против
  ledger — самостоятельный триггер ревизии.
- **D-цикл** (≈1 сессия, на milestone-close) — fold доказанных находок внутрь канона:
  собрать → классифицировать (`kit-gap` / `project-specific` / `single-incident` / `noise`) →
  gate (только `kit-gap` с multi-source evidence) → point-edit reference → commit + devlog.
- **Strip-ревизия** (раз в 3–6 мес / major-релиз модели / дельта CC-версии), два прохода:
  **external-intake** (что сдвинулось снаружи: changelog, first-party docs, essays — по дельте
  от ledger) → **re-test** (что из канона устарело: `claude --safe-mode` как быстрый тест
  «модель или обвязка»; устаревшее удаляется, не архивируется).

Дисциплина — `~/.claude/skills/claude-code-harness/references/harness-evolution.md`.

## Constraints

- **API:** строго CLI-подписка Claude Code. Anthropic API, managed-agents, beta headers,
  `--bare`, `--max-budget-usd` — **out of scope** (`.claude/rules/api-constraint.md`).
- **Built-ins first:** перед любым custom-субагентом — `claude agents`. 5 built-in типов
  (Explore, Plan, general-purpose, statusline-setup, claude-code-guide) дублировать нельзя.
- **Single-agent default:** один main thread — дефолт для most coding. Bounded fan-out —
  только когда scope превышает один контекст, и тогда через **dynamic workflows** (keyword
  `ultracode`), а не кастомный subagent-pipeline.

## Точки входа

| Хочешь | Читай |
|---|---|
| Полный workflow разработчика | [`WORKFLOW.md`](WORKFLOW.md) |
| Принцип, anti-patterns, spawn-policy | [`.claude/CLAUDE.md`](.claude/CLAUDE.md) |
| Машинный routing-spine | `.claude/docs/workflow.md` |
| Хронология решений | `.claude/devlog/` (`tldr.md` для холодного входа) |
| Поставить harness в новый проект | глобальный скилл `claude-code-harness` (Bootstrap-режим) |
