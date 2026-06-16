---
id: 70
date: 2026-06-07
title: "Actualize harness → CC 2.1.168 + 3 fresh sources"
tags: [harness, maintenance, versioning, hooks, sources]
status: complete
---

# Actualize harness state → Claude Code 2.1.168 + fresh agentic-dev sources

## Контекст
Оператор: «актуализируй состояние на начало сессии — вышла масса обновлений Claude Code
и статей по агентной разработке». Бинарь на машине = **2.1.168**, а harness-доки отставали:
`native-capabilities.md` (canonical срез) — 2.1.154-era, lab-доки (`builtins-inventory.md`,
все `workflow-*.md`) — 2.1.143-era. Per [[feedback_grow_with_community]] — research first-party
ДО опоры на внутренние артефакты.

## Дизайн
Два фоновых general-purpose агента (изоляция контекста, §sub-agent policy (а)): (1) official
changelog 2.1.155→168 из `code.claude.com/docs/en/changelog`; (2) свежие статьи март–июнь 2026
новее известного списка. Затем gap-анализ → согласование объёма с оператором (выбран **полный
sweep A–F** + все 3 источника).

## Сделано
**A. Факт-фиксы.** `workflow`→`ultracode` keyword rename (2.1.160; голое "workflow" больше не
триггерит) — проектный `CLAUDE.md`, глобальный skill `native-capabilities.md` + `harness-discipline.md`.
Version-stamp native-capabilities 2.1.154→2.1.168 + новая секция «Changed in 2.1.155→168».

**F. Lab-docs re-ground.** `builtins-inventory.md` → новая «Delta 2.1.144→2.1.168» секция + стемпы
до 2.1.168 (ядро 2.1.143-таблиц оставлено, дельты вынесены). 4× `workflow-*.md` стемпы → 2.1.168;
точечные факты: fan-out resilience (2.1.161 — упавший Bash не отменяет siblings), `SendMessage`
authority-hardening (2.1.166), `EnterWorktree` mid-session switch, `claude agents --json waitingFor`.

**C. Hook-апгрейд.** `stop-validation.sh` (Stop hook) переведён на `hookSpecificOutput.additionalContext`
(2.1.163): advisory-провал теперь **доходит** до Claude (feed-and-continue), а не теряется в stderr+exit0.
Loop-guard: после 2 подряд logged-fail перестаёт пере-кормить (анти-спин). **Verified** функционально
(3 кейса: no-change→пусто; fail→валидный additionalContext JSON; loop-guard→подавление). Честная
оговорка: e2e «Claude продолжает ход» опирается на документированный 2.1.163-контракт, не на live-run.
`loop-protected-guard.sh` — это **PreToolUse**, additionalContext-механизм к нему НЕ применим (не форсил).

**B/D. Guardrails reconcile.** `principles.md` §permissions: натив-hardening 2.1.160–166 (glob deny,
`WebFetch(domain:)` precedence, `$HOME`-deny, acceptEdits config-prompts) расширяет слой — ручной deny
остаётся минимальным.

**E. Новые источники.**
- **Harness-Bench** (arXiv 2605.27922) → `benchmark.md`: harness качает скор на 23.8 пт; model×harness
  reporting; failure-symptom taxonomy; эмпирика «сильнее модель → ниже harness-variance» (подтверждает
  foundational-принцип И недомер single-shot A/B из #61/#63).
- **Anthropic harness-design** (Rajasekaran, 2026-03) → `multi-agent.md`: уже был процитирован;
  добавлен нюанс evaluator-с-live-app (Playwright MCP) + снятие manual context-resets под 4.6+.
- **Externalization** (arXiv 2604.08224) → `memory-layers.md`: Weights→Context→Harness, «файл =
  authoritative state» как citable frame для progress/devlog; + memory-judge 63%-wrong-accept (2604.11364).

## Результат
16/16 Layer A static-checks pass. CLAUDE.md = 142 строки (≤200). Зафиксированы 3 MEMORY-указателя.
Изменено 8 проектных доков + 1 hook + 2 файла глобального skill. Открытый хвост: failure-symptom
taxonomy из Harness-Bench как axes для Layer C — кандидат на будущую P-итерацию (не сделано здесь).
