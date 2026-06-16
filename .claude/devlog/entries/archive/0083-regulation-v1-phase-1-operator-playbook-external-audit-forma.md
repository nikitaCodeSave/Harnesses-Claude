---
id: 83
date: 2026-06-10
title: "Regulation v1 Phase 1: operator playbook + /external-audit formalized, battle-tested on milestone-1 SGR"
tags: [harness, regulation, external-audit, agents, dogfood]
status: complete
---

# Regulation v1 Phase 1: operator playbook + /external-audit formalized, battle-tested

## Контекст
Трек «Регламент v1» (план `.claude/plans/standard-v1-regulation.md`), Phase 1 — сборка
содержания. Цель сессии: R1 (operator playbook), R2 (`/external-audit` как формализованный
3-ролевой протокол + боевой verify), R3 (harness-evolution reference). Phase 0 закрыт в
сессии 1 (D1–D5 grill'ом).

## Изменения (всё в `~/.claude`, commit 9a215c3)
- **R1 `references/operator-playbook.md`** (99 строк) — human-facing вход в регламент:
  bootstrap → Phase 5 kit → build-ритуал → когда заказывать аудит → D-цикл → strip-ревизия.
  Ссылки на checklist'ы, не копии. Карта слоёв (baseline / kit / аудит / проектный слой).
- **R2 `/external-audit`** — `commands/external-audit.md` (adjudicator) + 3 agent-определения
  `agents/{evidence-executor,process-auditor,code-refuter}.md`. Формализация 3-ролевого
  протокола, жившего прозой в devlog #78–#81. Контракт вердиктов унифицирован с CRITIC.json
  (lowercase enums, arrays-not-objects, per-role jq-валидация). Adjudication-правила:
  (1) исполненное доказательство > прочитанного; (2) verified-critical ⇒ refuted;
  (3) blocked executor ⇒ blocked; (4) иначе confirmed / confirmed_with_debt.
- **R3 `references/harness-evolution.md`** (53 строки) — D-цикл (fold находок журнала/аудита
  в канон через gate «single-incident ≠ invariant») + strip-ревизия (`--safe-mode` тест).
  D3-минимум: единственная канонизация из lab (testing/api-constraint/docs-discipline НЕ
  переносятся — дубли baseline §1–§8).
- SKILL.md reference-map + README обновлены; `.gitignore` whitelist += `agents/`.

## Боевой verify R2 — главный результат
Прогнал `/external-audit` на milestone-1 `AI_analyst_sgr` (закрытый dogfood'ом, 6/6 фич,
120 unit + 5 integration зелёные, e2e grounded). Три роли параллельно против живого
Oracle+ollama → adjudication.

**Вердикт: REFUTED.** code-refuter нашёл **verified CRITICAL**, исполняемо доказанный на
живом стеке: обход SQL-денлиста через quoted identifier — `SELECT "DBMS_RANDOM".VALUE()
FROM dual` проходит `validate_sql` и исполняется Oracle (`_strip_literals_and_comments`
затирает double-quoted идентификаторы ДО прогона package-regex; Oracle резолвит их в реальный
пакет). Открывает `"UTL_HTTP"` (SSRF), `"UTL_FILE"`, `"DBMS_LOCK".SLEEP` (DoS), `"SYS".*`.
Параллельно evidence-executor вынес CONFIRMED (продукт работает, все 3 golden-числа F6
независимо пере-выведены прямым SQL — exact match), process-auditor — CLEAN.

Это **прямое подтверждение §8 и всего регламента**: дыру пропустили ВСЕ предыдущие слои
dogfood'а (F4-hardening, lab security review, self-Evaluator ×2, reader/executor аудиты F6) —
поймал только полностью внешний, исполняющий 3-ролевой аудит. Adjudication-контракт сработал
без ручной доводки: CONFIRMED и REFUTED не конфликтуют (разные поверхности — «работает» vs
«безопасно»), правило verified-critical⇒refuted дало корректный итог.

Surviving findings (1 critical + 4 minor, включая закрытый долг F6 «validate-vs-execute
divergence» — подтверждён реальным, но fail-closed) записаны actionable-items'ами в
`AI_analyst_sgr/.claude/progress/build.md` в формате «воспроизвести → закрыть». Код не правил —
фикс делает авторская сессия отдельным red→green циклом.

## Затронутые файлы
- `~/.claude`: operator-playbook.md, harness-evolution.md, external-audit.md, 3× agents/,
  SKILL.md, README.md, .gitignore (commit 9a215c3)
- `AI_analyst_sgr/.claude/audit/m1-external-audit-2026-06-10/` — 4 JSON (3 роли + verdict)
- `AI_analyst_sgr/.claude/progress/build.md` — External audit раздел + actionable (не закоммичено: продукт-репо оператора, фикс отдельной сессией)
- `.claude/progress/standard-v1.md` — session 2

## Проверка
- dot-claude: commit 9a215c3 (9 файлов, 480 insertions); все 3 agent-JSON прошли per-role
  jq-валидацию; AUDIT-VERDICT.json написан adjudicator'ом.
- Боевой прогон: 3 роли отработали, evidence-executor исполнил живой стек (./init.sh + 5
  integration + независимое пере-выведение golden), вердикт получен без ручной доводки.

## Discovered (для R4/Phase 2)
- Agent type из `~/.claude/agents/` НЕ резолвится в `subagent_type` Task-tool'а из другого
  проекта (видны только built-in + lab-local). Обход для прогона: `general-purpose` + «прочитай
  ~/.claude/agents/<role>.md и следуй». Через slash-command `/external-audit` оператор увидит
  глобальные агенты штатно — это путь запуска по дизайну.

## Related
- #78–#82 — dogfood-трек (содержание kit, 3-ролевой аудит прозой)
- #62, #65 — fresh-context принцип (§8), который этот прогон подтвердил ещё раз
- план `.claude/plans/standard-v1-regulation.md` (R1/R2/R3 done; next R4 → Phase 2)
