---
id: 9
date: 2026-05-10
title: "ADR-013/014 + meta-CLAUDE.md process rules (with ADR-014 rollback)"
tags: [adr, harness]
status: complete
---

# ADR-013/014 + meta-CLAUDE.md process rules (with ADR-014 rollback)

## Контекст
Получен детальный аудит-разбор `docs/HARNESS-DECISIONS.md` от внешнего рецензента: 7 пунктов — 5 process gaps + 2 эмпирические задачи. Цель: реализовать процессные дополнения, провести эмпирическую верификацию ADR-006/007 закрытия, зафиксировать решения. В процессе допущена методологическая ошибка (ADR-014 в промежуточной форме нарушил собственное симметричное правило foundational principle), пользователь её немедленно отметил, ADR-014 переписан в финальную форму.

## Изменения

**docs/HARNESS-DECISIONS.md**:
1. **Active inventory** (computed view) сверху файла — снимок состояния `.claude/` после всех applied ADR. Единственное место, нарушающее «не редактируется после фиксации» (явно помечено как exception).
2. **ADR-013** — Cross-session memory: `auto-memory` canonical, `claude-mem` / MCP memory в baseline запрещены без empirical evidence что auto-memory недостаточна.
3. **ADR-014** — Built-in `/init` не интервьюирует (empirical proof в `/tmp/init-poc/`), но это **by design** под Opus 4.7. Decision = **no action**: ADR-007 закрытие ADR-006 остаётся в силе. Промежуточная prescriptive форма (mandatory AskUserQuestion) откачена после возражения пользователя — нарушала симметричное правило foundational principle (N=1 не достаточно для invariant'а).
4. **ADR-010 clarification** (edit-in-place per разрешение владельца): добавлено use-case scope для удаления `stop-recovery.sh` — обосновано **интерактивными** TUI-сессиями; при добавлении фоновых сценариев (`claude --print` в cron) — re-evaluate.

**.claude/CLAUDE.md** (meta-orchestrator):
1. **Symmetric foundational principle** — критерий когда компонент *должен* появиться: N≥3 эмпирически зафиксированных случаев + не покрыто проектным CLAUDE.md / built-in'ами. Меньше — ad hoc, что и привело к v0.1 expansion'у.
2. **Sub-agent spawn policy** (новый раздел) — критерии (а) изоляция контекста, (б) параллелизм, (в) близость к auto-compact. В остальных случаях main thread выполняет работу сам.
3. **Re-evaluation triggers** (новый раздел) — major-релиз модели / N≥3 эмпирических промаха одного типа / breaking change в built-in каталоге. Регрессия = новый ADR с `Supersedes` и transcript-доказательством.
4. **First-session contract** — формулировка ослаблена с прескриптивной обратно до soft guidance после возражения пользователя; ссылается на ADR-014 evidence.

**Memory** (`~/.claude/projects/.../memory/`):
- `feedback_no_upfront_contract_interview.md` — feedback memory, фиксирующая что под Opus 4.7 формальный upfront-контракт (язык/deliverable/verification) не нужен; контракт строится итеративно из conversation.

## Затронутые файлы
- `docs/HARNESS-DECISIONS.md` — +inventory, +ADR-013, +ADR-014, +clarification ADR-010
- `.claude/CLAUDE.md` — +symmetric extension foundational principle, +Sub-agent spawn policy, +Re-evaluation triggers, First-session contract softened
- `~/.claude/projects/-home-nikita-PROJECTS-Harnesses-Claude/memory/feedback_no_upfront_contract_interview.md` — new feedback memory
- `~/.claude/projects/-home-nikita-PROJECTS-Harnesses-Claude/memory/MEMORY.md` — index updated

## Проверка
- Изменения документационные; исполняемых компонентов harness'а не добавлено и не удалено (`.claude/` структура неизменна — agents 2, hooks 4, skills 1, rules 1).
- **Empirical evidence для ADR-014** (transcript 2026-05-10, Claude Code 2.1.138, fixture `/tmp/init-poc/`):
  - Команда: `cd /tmp/init-poc && claude --print "/init"`
  - Output: 1 строка summary; AskUserQuestion вызовов = 0; CLAUDE.md создан на английском по default'у с секциями `## Project / ## Commands / ## Layout note`.
  - Conclusion: built-in `/init` документирует repo-state, не интервьюирует; под Opus 4.7 это OK — контракт строится итеративно.

## Related
- ADR-006 — оригинальный invariant «mandatory interview after onboarding», основан на N=1 pain-case (FastApi-Base battle-test).
- ADR-007 — закрытие ADR-006 как moot, inference из docs (без верификации).
- ADR-010 — clarification edit-in-place, узакониваемая редактирование existing ADR при явном разрешении владельца.
- ADR-012 — meta-CLAUDE.md trim (3 новых процессных раздела расширяют, не возвращают удалённое).
- ADR-013 — cross-session memory canonical decision.
- ADR-014 — empirical evidence + self-correction (методологический урок).
