# Ralph Loop — итоги ревью

Сгенерировано вручную после остановки цикла. **Не обновляется автоматически** — переписать после применения решений по предложениям.

- **Запущен**: 2026-05-11T00:51:31Z
- **Остановлен**: 2026-05-11T04:57:42Z (graceful pause через `RESULT:NOOP empty-backlog`)
- **Длительность**: ~4ч 6мин wall-clock
- **Итераций**: 39 (38 со счётчиком, iter-0039 = state-only)
- **Совокупная стоимость**: ~$72.50 (бюджет $120, использовано 60%)
- **Процесс**: мёртв; `PAUSED.md` создан; `RUN.pid`/`RUN.started` — stale-артефакты, можно удалить

## Итоговые счётчики

Из `STATE.md` + `backlog.md` (структурированная правда; счётчики `grep RESULT:` по `journal.md` врут — там много нарратива).

| Тип итерации | Кол-во | Где видно |
|---|---|---|
| **ACCEPT** (через worktree, замержено в main) | **13** | `git log --grep "loop:"` → 18 коммитов (13 H-кода + 5 state-update) |
| **PROPOSAL** (дифф в `proposals/`, ждёт человека) | **13** | `.claude/loop/proposals/*.diff` |
| **REJECT** (fitness или stale-rationale) | **4** | H-015, H-017, H-019, H-030 |
| **HOLDOUT pass** (overfit-detect на T04) | **7** | iter-0005/0010/0015/0020/0025/0030/0035 |
| **NOOP empty-backlog** | **1** | iter-0038 (первый и единственный — backlog drained) |

Всего 30 гипотез в backlog (H-001..H-030): 13 ACCEPT + 13 PROPOSAL + 4 REJECT.

## 13 ACCEPTed гипотез (уже в main)

Это **полезные артефакты цикла** — мержились через worktree, fitness-gate прошёл. Краткий каталог:

| H-id | Iter | Что добавлено / убрано | Файл |
|---|---|---|---|
| H-001 | 0001 | Slash-команда `/loop-status` (операторский инспектор) | `.claude/commands/loop-status.md` |
| H-002 | 0002 | Агрегатор метрик по итерациям (per-iter тренд) | `.claude/loop/aggregate-metrics.py` |
| H-003 | 0003 | Stop-hook регресс-чекер (drop в test-count) | `.claude/hooks/stop-validation.sh` extend |
| H-004 | 0004 | SessionStart preload STATE.md summary | `.claude/hooks/session-context.sh` extend |
| H-005 | 0006 | Cost-warn UserPromptSubmit hook (file only; wiring в settings — отдельный PROPOSAL) | `.claude/hooks/cost-warn.sh` |
| H-006 | 0007 | Bootstrap-fixtures helper (corpus-driven re-clone) | `.claude/benchmark/bootstrap-fixtures.sh` |
| H-007 | 0008 | Per-task variance report (CV>30% flag) | `.claude/loop/variance-report.py` |
| H-008 | 0009 | Cross-fixture sign-inversion detector | `.claude/loop/cross-fixture-check.py` |
| H-009 | 0011 | Auto-index pending PROPOSAL диффов | `.claude/loop/proposals-review.py` |
| H-010 | 0012 | Opt-in security-reviewer agent | `.claude/agents/security-reviewer.md` |
| H-013 | 0016 | **Retire** `deliverable-planner` агент (первый non-PROPOSAL retire) | удалён `.claude/agents/deliverable-planner.md` |
| H-026 | 0033 | CLI field tripwire для `claude --output-format` | `.claude/loop/validate-claude-output.sh` + тест |
| H-027 | 0024 | OpenHarness tool-gating Tier-0 check (≤20 active tools) | `.claude/benchmark/static-checks.sh` extend |

Все 13 — операторские/телеметрические инструменты или ретайр одного компонента. Ни одна гипотеза не правила фитнес-логику цикла, prompt'ы или benchmark-инфраструктуру runtime-критическим образом → harness behaviour сохранён.

## 4 REJECTа — поучительные case'ы

| H-id | Iter | Класс | Что случилось |
|---|---|---|---|
| H-015 | 0018 | **stale-rationale dead-on-arrival** | `commands/` уже хостит `loop-status.md` (H-001 ACCEPT того же дня); retire был бы регрессией H-001. Backlog был составлен до применения H-001 — рассуждение устарело к моменту попытки. |
| H-017 | 0021 | **stale-rationale dead-on-arrival** | `headless-runner.sh` уже использует `jq`-парсинг с первого коммита `b5fcfd1`; рассуждение «replace grep with jq» — apply-no-op. |
| H-019 | 0023 | **fitness REJECT (false positive)** | Добавление T05/T06/T07 yaml'ов раздуло `files_changed` метрику на T01/T02 (10→26 / 11→27 — INJECT_HARNESS копирует весь `.claude/` в фикстуру). Weighted score +0.305 > 0.20. Поведенчески всё ОК (pytest pass, tokens within 2σ). **Урок**: чистая additive-правка `.claude/` _всегда_ триггерит files-signal на injected-задачах. |
| H-030 | 0036 | **stale-rationale + design-conflict** | ADR-trigger PreToolUse Write hook: (1) hooks-discipline N≥3 порог не достигнут (ноль incident'ов), (2) self-description anti-pattern, (3) target/rationale scope mismatch, (4) block-at-write timing flavor (CLAUDE.md anti-pattern). |

**Доминантный паттерн**: 3 из 4 REJECT'ов — stale-rationale. Цикл сам выработал внутренний паттерн «pre-pick rationale-validation pass» и предложил H-031 как кандидата для следующего пополнения backlog'а. Это **сильный сигнал к доработке** перед перезапуском.

## 7 HOLDOUT readings — характеристика variance

T04 schema-migration на full-stack-fastapi-template, прогон каждые 5 итераций.

| Iter | Tokens | Turns | Cost | Wall | Files | Заметка |
|---|---|---|---|---|---|---|
| 0005 | 11721 | 24 | $0.910 | 153s | 4 | baseline |
| 0010 | 9904 | 20 | $0.776 | 127s | 4 | мягкое улучшение |
| 0015 | 10840 | 21 | $0.845 | 137s | 4 | стабильно |
| 0020 | 10792 | 17 | $0.699 | 123s | 4 | мягкое улучшение |
| 0025 | 10691 | 22 | $0.866 | 141s | 4 | стабильно |
| 0030 | 8405 | 13 | $0.642 | 104s | 4 | **LOW outlier** (-21% tokens vs prior μ) |
| 0035 | **21255** | **29** | **$1.431** | **324s** | **5** | **HIGH outlier** (+153% tokens, ~5.7σ above prior μ) |

**Итоговый CV по 7-точечной серии**: tokens 35.4%, turns 24.8%, cost 30.1%, wall 47.4%, files 9.1% — далеко за пределами 20% синтетического порога.

**Важный вывод цикла** (записан в STATE.md iter-0035): variance стала бипольной (terse vs thorough модели в идентичном prompt'е), runtime harness НЕ менялся с iter-0024. Это **invocation-level noise**, а не overfit. Все 7 holdout'ов **passed** по функциональным критериям (Tier 0 + exit=0 + correct task adaptation).

Recommendation цикла: рефрешнуть T01/T02/T03 baseline свежими n=3 runs до того как принимать tune'ы variance/threshold (H-022, H-025). См. DIGEST.md.

## Variance flags (свежий `variance-report.py`)

| Task | Метрика | n | CV% | Флаг |
|---|---|---|---|---|
| T01 | files | 13 | **40.1%** | FLAG → артефакт iter-0023 H-019 (INJECT_HARNESS) |
| T02 | files | 13 | **36.3%** | FLAG → тот же артефакт |
| T04 | tokens | 7 | **35.4%** | FLAG → bipolar variance (см. выше) |

Другие 13 метрик в пределах 30%. T03 — n=1 (только iter-0004), `<min`.

## Cross-fixture: чисто

`cross-fixture-check.py`: `(no tasks with ≥2 fixtures observed)` — corpus так и не расширился до того, чтобы инструмент сработал боевым образом. Тот же tripwire status, что и в iter-0009.

## Полезные артефакты по итогам (для последующих сессий)

1. **`/loop-status`** — компактный дашборд для оператора без чтения 5 файлов.
2. **`aggregate-metrics.py` / `variance-report.py` / `cross-fixture-check.py`** — три телеметрических инструмента, читают `.claude/loop/reports/iter-*.json` (35 файлов).
3. **`proposals-review.py`** — регенерирует `REVIEW.md` от 13 диффов; `--check` exit 1 при N≥1 pending.
4. **`security-reviewer` agent** — opt-in диф-уровневый ревью; ровно тот сценарий, для которого 8 из 13 предложений созданы (трогают settings.json / hooks / run.sh / PROMPT.md).
5. **`bootstrap-fixtures.sh`** — повторный re-clone внешних фикстур из corpus.yml (репродуцируемость).
6. **`validate-claude-output.sh`** — CLI tripwire, проверяет наличие 8 jq-полей в `claude --print --output-format json`; защищает headless-runner от молчаливого breakage при обновлениях CLI.
7. **Tier-0 tool-gating check** — `static-checks.sh` теперь считает active agents/hooks/skills/commands (12/20 сейчас).
8. **35 per-iter report JSON'ов** в `.claude/loop/reports/` + 37 metadata-JSON в `.claude/loop/logs/iter-*.json` — пригодны для повторного аналитического прохода.

## Discovered patterns / open debt

Внутренние открытия цикла, не оформленные как гипотезы:

1. **Stale-rationale class** (3 случая) — backlog был сгенерирован одномоментно 2026-05-11, рассуждения устаревают по мере применения предыдущих гипотез. **Кандидат H-031 (NON-PROTECTED ADD)**: `backlog-validate.py` — pre-pick rationale-check (target literal exists / not-already-applied / not-self-description / anti-pattern grep).
2. **INJECT_HARNESS files-inflation** — любая additive-правка `.claude/` инфлирует `files_changed` метрику на injected-задачах. Mitigation: либо вычитать harness-инжект из счётчика, либо снизить вес files, либо смириться. Empirically обработано в iter-0024 (H-027 ACCEPT через modify-existing-file path).
3. **Retire-bias × holdout-cadence collision** — k=5 у обоих параметров → retire-bias никогда не срабатывает в одиночку (holdout precedence). Адресуется H-021 (см. DIGEST.md).
4. **Bipolar invocation variance** (iter-0035) — model генерирует либо terse либо thorough ответ на идентичный prompt; cache_read варьируется 2.5× между прогонами. Открытое наблюдение.
5. **Cwd-stuck recurrence** — `cd <worktree>` из Bash-вызова персистится, ломает следующий `git worktree remove`. Workaround: абсолютные пути, `cd` обратно в корень перед remove. Pattern noted iter-0016/0017.
6. **`PROMPT.md` inject-from path mismatch** — записано как infra debt (g) → operator action H-035 в STATE.md.
7. **`PYTEST_TARGETS` recursive scan** — T03/T04 pytest=skipped с iter-0003. infra debt (a).

## Что писалось в protected-файлы НАПРЯМУЮ?

```
git diff main -- .claude/CLAUDE.md .claude/rules/ .claude/docs/ \
                  .claude/settings.json .claude/loop/{run.sh,PROMPT.md,corpus.yml,fitness.sh,fitness.py}
```
**Ожидаемо: пусто.** Цикл уважал protected-list во всех 39 итерациях, все правки таких файлов уехали в `proposals/`. `loop-protected-guard.sh` срабатывал штатно (записано в iter-0013/0014 narratives).

## Devlog состояние

19 entries в `.claude/devlog/entries/`, последняя `0028-loop-iter-0001-first-accept-bug-3-fix-launch-readiness.md` — **до старта основного прогона**. H-029 (devlog-on-accept) добавил бы entries автоматически, но он pending; цикл сам в devlog не писал.

## Что делать дальше — операционно

1. Удалить stale `.claude/loop/RUN.pid` и `.claude/loop/RUN.started`.
2. Открыть `.claude/loop/proposals/DIGEST.md` — per-diff анализ с recommended actions.
3. Применить одобренные диффы, пометить статусы в `backlog.md`.
4. Регенерировать `REVIEW.md`: `python3 .claude/loop/proposals-review.py`.
5. **Перед перезапуском цикла** — пополнить backlog (минимум H-031 backlog-validator), иначе iter-0040 снова уткнётся в NOOP.
6. **Перед принятием H-022 / H-025** (tune'ы variance/threshold) — рефрешнуть baseline T01/T02/T03 на свежих n=3 runs (см. iter-0035 caveat).
