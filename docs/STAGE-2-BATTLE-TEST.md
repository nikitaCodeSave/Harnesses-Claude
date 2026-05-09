# Stage 2 — Battle-test plan (harness v0.1)

**Цель**: эмпирически проверить harness на двух пилотных проектах — один greenfield, один mature — за ~2 недели. Метрики и threshold'ы из исходного гайда (раздел Recommendations, Этап 2).

## Состав harness'а на старте Stage 2 (после ADR-007 cleanup)

| Категория | Артефакт | Статус |
|---|---|---|
| Архитектура | `.claude/CLAUDE.md` (мета), `docs/HARNESS-DECISIONS.md` (ADR-001..007, ADR-006 superseded), `.claude/rules/testing.md` | зафиксированы |
| Subagents | 3 custom: deliverable-planner, code-reviewer, meta-creator | минимально |
| Skills | 2: devlog (наш schema) + plan-deliverable (deliverable-driven contract) | минимально |
| Hooks | 8: 4 блокирующих (block-shallow-agent-spawn, secret-scan, dangerous-cmd-block, auto-format) + 4 observability (config-audit, env-reload, denied-log, stop-recovery) | smoke-tested 14/14 |
| settings.json | hooks + permission whitelist (106 allow / 23 ask / 13 deny) | валиден |
| Devlog | operational | работает |

Onboarding/review/debug сценарии в пилоте — через built-ins (`/init`, `/team-onboarding`, `/memory`, `/review`, `/debug`, `/simplify`, `/security-review`, `claude ultrareview`). См. таблицу в `.claude/CLAUDE.md` секция «Built-in onboarding & quality flow».

## Установка в пилотный проект

Вариант по умолчанию (простой и реверсируемый):
```bash
PILOT=/path/to/pilot
cp -r /home/nikita/PROJECTS/Harnesses-Claude/.claude "$PILOT/.claude"
# Убрать harness-specific артефакты, относящиеся к самой Harnesses-Claude:
rm -rf "$PILOT/.claude/devlog/entries/"*  # devlog пилота — свой
rm -rf "$PILOT/.claude/memory/"*          # observability логи — свои
rm -rf "$PILOT/.claude/plans/"*           # plan-mode артефакты — свои
rm "$PILOT/.claude/CLAUDE.md"             # мета-CLAUDE остаётся, но проектный — отдельно
# Поверх — `claude` → `/onboard` создаст проектный CLAUDE.md в корне пилота.
```

Альтернатива — упаковать harness как plugin (`marketplace.json` + `plugin.json`) и установить через `claude plugin install`. Дороже на старте, чище на дистрибуции — отложено на Stage 3 (publish as plugin).

## Workflow battle-test'а (per pilot)

1. **Setup**: cp `.claude/` в пилот; `cd $PILOT`; `claude`.
2. **Bootstrap CLAUDE.md** (если нет):
   - NEW project — `/init` (built-in). При желании зафиксировать язык — добавить вручную строку `Working language: <язык>`.
   - MATURE project с new development — `/init` (если корневого CLAUDE.md нет) либо `/memory` для уточнения существующего.
   - MATURE с new teammate handoff — `/team-onboarding` (built-in v2.1.101+).
3. **First deliverable**: дать конкретную задачу из real backlog. Если goal неоднозначен — `/plan-deliverable` для 1-page spec; иначе сразу основной поток для реализации.
4. **Hooks observation**:
   - Сколько раз сработал `secret-scan.sh`? (false positives → tighten allowlist)
   - Сколько раз `dangerous-cmd-block.sh`? (false positives → refine regex; теперь с echo/printf short-circuit и quote-stripping per devlog #3)
   - Срабатывает ли `block-shallow-agent-spawn.sh` адекватно?
   - Логи: `.claude/memory/*.jsonl`
5. **Self-evolution**: появились ли запросы на новые skills/agents через meta-creator (вызываемый напрямую через Task tool)? Если ≥3 — скорее всего harness покрывает реальные потребности.
6. **Devlog**: после каждой итерации — запись через `/devlog`.
7. **Code review**: built-in `/review` после нетривиальных изменений; `claude ultrareview` перед merge; bundled `/debug` для bug hunt; bundled `/simplify` для cleanup.

## Метрики (per pilot)

| Метрика | Цель Stage 2 | Threshold для Stage 3 |
|---|---|---|
| Time to first working deliverable (от `/onboard` до зелёного теста) | замерить | <1 день для greenfield, <3 дней для mature |
| Self-created skills/agents | зафиксировать | ≥3 успешных |
| False-positive blocking hooks | посчитать | =0 |
| Devlog entries | вести | ≥5 за 2 недели |
| Approval-fatigue прецеденты | отметить | <5 случаев «надоело approval'ить» |

## Threshold для перехода Stage 3

- ≥3 успешных самосозданных skills/agents в сумме по двум пилотам.
- 0 false-positive blocking hooks (после tuning'а на первом пилоте — на втором уже без сюрпризов).
- onboarding `/onboard` отрабатывает на обоих пилотах без ручной правки workflow.
- Никаких regression'ов в существующей разработке пилотов из-за harness'а.

## Что вернуть в harness после Stage 2

- Tuning regex'ов в hooks (если найдены false positives).
- Новые ADR в `docs/HARNESS-DECISIONS.md`, если выявлены архитектурные lessons.
- Возможные новые skills/agents, доказавшие useful в обоих пилотах.
- Решение по `onboarding-agent` (per ADR-001 note: кандидат на удаление, если `CLAUDE_CODE_NEW_INIT=1` покрывает 80%+).
- v0.3 patch list к `Harnesses_gude.md`.

## Откат

При серьёзных проблемах в пилоте: `rm -rf $PILOT/.claude` возвращает пилот в исходное состояние. Harness-репо (`Harnesses-Claude`) не модифицируется в процессе battle-test — все правки обсуждаются и применяются обратно в Stage 2.x devlog-записях.
