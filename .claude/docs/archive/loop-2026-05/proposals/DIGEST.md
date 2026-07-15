# Per-diff digest — 13 PROPOSAL'ов на ревью

Дополняет авто-сгенерированный `REVIEW.md`. Здесь — opinionated анализ каждого диффа с recommended decision и context'ом для информированного выбора. Структура каждой записи:

- **Что меняет** (1-2 строки)
- **Rationale цикла** (что писал loop в backlog/journal)
- **Анализ** (что упустил/учёл loop)
- **Риск-класс** (low/medium/high — для приоритезации security-review)
- **Recommended decision** + reasoning
- **Конфликт-группа** (если есть)

Перед массовым apply прогони security-reviewer параллельно на all-medium-and-high-risk:

```
Agent({ subagent_type: "security-reviewer",
        prompt: "Review .claude/loop/proposals/iter-NNNN-...diff against current main.
                 Flag NEW perms granted, removed defenses, hook-write into sensitive paths." })
```

---

## Группа I — Независимые (apply последовательно, один коммит каждый)

### 1. iter-0013 — H-011 retire `dangerous-cmd-block.sh`

- **Что меняет**: удаляет PreToolUse Bash-hook (91 строка) + entry в `settings.json`. Hook ловит: `rm -rf /`, `dd if=...of=/dev/...`, `mkfs`, force-push в main/master/prod, fork bomb, `chmod 777 /`, `shutdown`/`reboot`.
- **Rationale цикла**: «redundant с permissions.deny (sudo/curl/wget already denied)».
- **Анализ**: rationale **частично ложный**. `permissions.deny` покрывает sudo/curl/wget — это не пересекается с тем, что ловит hook (`rm -rf /`, force-push, shutdown, dd, mkfs, fork bomb). Hook — _комплементарный_ слой, не дублирующий. Cost saving: -3% на Bash-heavy итерациях (т.е. почти ничего, hook соft-fail на jq missing).
- **Риск**: **medium-high** — реально снижает defense на катастрофические команды; единственная защита от force-push в main.
- **Recommended decision**: **REJECT**, обновить rationale в backlog как «не redundant». Возможный компромисс — оставить hook, но сузить regex'ы (если есть false-positives — backlog их не упоминает).
- **Конфликт-группа**: нет.

### 2. iter-0014 — H-012 retire `secret-scan.sh`

- **Что меняет**: удаляет PreToolUse Edit|Write|MultiEdit hook (78 строк) + entry в settings.json. Ловит при write: AWS key, GitHub token, private key headers, Slack token, generic high-entropy assignment.
- **Rationale цикла**: «gitignore prevents tracking, Read deny prevents reading, hook = third layer».
- **Анализ**: те же контр-аргументы что у H-011. **gitignore не предотвращает запись**, только git-tracking. **Read deny** не предотвращает запись новых секретов. Hook ловит именно WRITE-event — accidental hardcoded key в config.py. Loop сам это признал в iter-0014 narrative: «trades defense-in-depth for cost».
- **Риск**: **medium** — снижение defense; обработка `.env.example`/test paths уже allowlisted.
- **Recommended decision**: **REJECT**, отметить в backlog как complementary-not-redundant.
- **Конфликт-группа**: нет.

### 3. iter-0017 — H-014 retire `auto-format.sh` PostToolUse

- **Что меняет**: удаляет PostToolUse Edit|Write|MultiEdit hook (39 строк) + всю PostToolUse секцию из settings.json (это единственный PostToolUse hook).
- **Rationale цикла**: «hooks-discipline: blanket fire-on-every-write нарушает rule "только когда action must happen every time"; per-language ad-hoc invocation cleaner».
- **Анализ**: hook сейчас effectively no-op — `.claude/format.sh` не существует, hook просто пишет JSONL в `format-events.jsonl`. Loop проверил grep: **никто не читает этот лог** (`aggregate-metrics.py` / `variance-report.py` / `cross-fixture-check.py` / `proposals-review.py` все читают `reports/iter-*.json`).
- **Риск**: **low** — удаляем no-op + бесполезный лог-стрим.
- **Recommended decision**: **ACCEPT**. Чистое применение hooks-discipline. Если когда-то понадобится форматтер — добавить `.claude/format.sh` + узкий hook под конкретный matcher (например, только `*.py`).
- **Конфликт-группа**: нет.

### 4. iter-0019 — H-016 consolidate `workflow.md` + `multi-agent.md`

- **Что меняет**: переносит overlapping subagent-policy секцию из `workflow.md` в `multi-agent.md` §7.2 (+ Patterns 1/2/3, opt-in criteria, API constraint note). В workflow.md остаётся 3-строчный pointer на multi-agent.md. Net -49 строк, +16/-65.
- **Rationale цикла**: «оба файла покрывают spawn policy; single source of truth; -5% tokens когда читаешь workflow.md».
- **Анализ**: контент сохранён (sanity-checked). Workflow.md остаётся читаемым (короткое резюме + pointer). Multi-agent.md получает Patterns 1/2/3 cross-reference + opt-in criteria + API constraint note. Это **прямое применение docs-discipline rule 2** («CLAUDE.md как indexer, не store» обобщается на docs/).
- **Риск**: **low** — чистый рефакторинг docs.
- **Recommended decision**: **ACCEPT**.
- **Конфликт-группа**: нет.

### 5. iter-0022 — H-018 opt-in `LOOP_STASH_DIRTY` в `run.sh`

- **Что меняет**: 15 строк в `run.sh` — если `LOOP_STASH_DIRTY=1` и в main-tree есть uncommitted edits → `git stash push -u -m loop-iter-NNNN-pre-iter`. Default 0. **НЕ auto-pop** (оператор поппит вручную после ревью).
- **Rationale цикла**: «safety net на случай accidental main-tree edit, даже с worktree isolation».
- **Анализ**: feature harmless при default off. **НО**: loop сам в комментарии признал, что enable'ить опасно — STATE.md / backlog.md / journal.md обновляются между итерациями _намеренно uncommitted_; stash спрячет их от next iter's Phase 1 read. Реальное применение: оператор стэшит свой WIP перед запуском, _не цикл_.
- **Риск**: **low** (default off; pure additive).
- **Recommended decision**: **ACCEPT (optional)**. Польза ситуативная — если оператор хочет запустить цикл с активным WIP, фича безопасно его сохранит. Можно и отложить как low-value.
- **Конфликт-группа**: нет (но трогает `run.sh` — поэтому в proposal-only path).

### 6. iter-0026 — H-020 extract API constraint из `CLAUDE.md` в `rules/`

- **Что меняет**: 7 строк убраны из `CLAUDE.md` (тело секции «API constraint (КРИТИЧНО)»), заменены 3-строчным indexer-pointer'ом. Новый файл `.claude/rules/api-constraint.md` (25 строк, structured: Out-of-scope + Перенос концепций). `+1` в Reference materials списке.
- **Rationale цикла**: «docs-discipline rule 2 — CLAUDE.md как indexer, не store. API constraint = invariant → rules/».
- **Анализ**: точное применение docs-discipline rule 2. CLAUDE.md 119→112 строк (приближается к ≤200 budget из rule 2). Rules-файл структурирован, контент сохранён.
- **Риск**: **low** — docs-only.
- **Recommended decision**: **ACCEPT**.
- **Конфликт-группа**: нет.

---

## Группа II — Конфликт по `corpus.yml` (база 4a39c2b — apply одним ручным edit'ом)

Все 5 диффов написаны против одной и той же базовой версии `corpus.yml`. `git apply` второго после первого упадёт. Стратегия: выбрать какие принимаем, сделать **один ручной коммит** с правкой corpus.yml, остальные пометить `rejected` в backlog.

### 7. iter-0027 — H-021 `retire_bias.every_k_iter` 5→3

- **Что меняет**: 1 строка в corpus.yml.
- **Rationale**: больше retire pressure + избегает LCM-collision с `holdout_cadence: 5` (под k=5 retire-bias _никогда_ не срабатывает в одиночку — holdout precedence).
- **Анализ**: collision argument **эмпирически верен** (журнал показывает: 6 holdout слотов, 0 retire-bias-only слотов в 39 iter). С k=3 retire-bias фактически получает слоты (N=3,6,9,12,18,21,24,27 vs N=15 collision). Empirically retire-throughput в этом прогоне не был bottleneck'ом (только 1 ACCEPTed retire — H-013), но для будущих циклов с retire-heavy backlog'ом — fix реальный.
- **Риск**: **low** — механический fix scheduling bug.
- **Recommended decision**: **ACCEPT**.

### 8. iter-0028 — H-022 `variance.sigma_multiplier` 2→1.5

- **Что меняет**: 1 строка.
- **Rationale**: 1.5σ ≈ 87% confidence; tighter signal band → больше accepts.
- **Анализ**: **плохой timing**. iter-0035 holdout показал bipolar variance (terse vs thorough модель), CV на tokens 35.4%. Ужесточение confidence band при инфлированной σ → риск false-positive REJECT'ов. STATE.md iter-0035 _явно_ рекомендует: «underlying issue is invocation-level noise floor has risen; tightening… only narrowly».
- **Риск**: **medium** — может вызвать false REJECT'ов на легитимных гипотезах.
- **Recommended decision**: **DEFER** (склоняюсь к REJECT в текущем виде). Сначала рефреш baseline T01/T02/T03 на свежих n=3 runs; пересмотреть с empirical σ.

### 9. iter-0029 — H-023 `subagent_cap` 3→1

- **Что меняет**: 1 строка. **Caveat в самом диффе**: PROMPT.md invariant #7 hardcoded «NEVER spawn > 3 subagents» — без синхронной правки PROMPT.md harness рассинхронизируется.
- **Rationale**: «Opus 4.7 spawns-fewer-default; cost predictability».
- **Анализ**: cap=3 за 39 iter ни разу не был достигнут (≤1 spawn наблюдался). Изменение **performative** — ничего не меняет в cost. Но: cap=1 _foreclosure_ spawn policy (b) «parallelism (independent searches converging in main thread)» — _explicitly_ allowed в CLAUDE.md.
- **Риск**: **medium** — закрывает легитимный канон; требует пары с PROMPT.md edit.
- **Recommended decision**: **REJECT** (или DEFER). Если accept — обязательно одновременно править PROMPT.md «> 3» → «> 1». Альтернатива: cap=2 (compromise — permitted parallelism без unbounded fan-out).

### 10. iter-0031 — H-024 `holdout_cadence` 5→7

- **Что меняет**: 1 строка.
- **Rationale**: «holdout дорогой; 7 экономит ~6% времени».
- **Анализ**: holdout — **единственный** signal по invocation-level noise (iter-0035 outlier обнаружен именно там). Сейчас стоит увеличить, а не уменьшить частоту. Кроме того, разрешает LCM(5,7) collision с retire_bias (если H-021 не принят и k остаётся 5 — что неконсистентно с H-021 accept).
- **Риск**: **medium** — снижает видимость варианса в момент, когда вариансу нужно больше наблюдений.
- **Recommended decision**: **DEFER**. Пересмотреть после стабилизации T04 series (3-4 reads после re-baseline).

### 11. iter-0032 — H-025 `weighted_score_delta_max` 0.20→0.15

- **Что меняет**: 1 строка.
- **Rationale**: stricter accept gate.
- **Анализ**: исторически ни один из 12 ACCEPT'ов не падал в (0.15, 0.20] window (iter-0004 H-004 +0.137 — единственный non-zero, ниже 0.15). Тightening сейчас low-cost _по историческим данным_, но та же caveat что у H-022 — bipolar variance делает любой stricter-gate более чувствительным к invocation noise.
- **Риск**: **medium** — без re-baseline риск ложных REJECT'ов.
- **Recommended decision**: **DEFER** до re-baseline.

**Итоговая рекомендация по corpus.yml**: вручную поправить только `retire_bias.every_k_iter: 5 → 3` (H-021 ACCEPT). Остальные 4 — пометить `rejected: needs-rebaseline-first` в backlog. После того как соберётся фреш baseline T01/T02/T03 — рассмотреть H-022 / H-025 заново.

---

## Группа III — Конфликт по `PROMPT.md` (база c4559a2)

Оба диффа на одной базе, но **трогают разные секции** (Phase 2 picker vs `### On ACCEPT:` block) — можно совместить одним ручным edit'ом.

### 12. iter-0034 — H-028 stale-backlog breaker

- **Что меняет**: новая picker rule 4 в Phase 2 — если последние 3 entries в journal.md = REJECTED → `RESULT:NOOP backlog-stale-3-consecutive-rejects` + exit. Сейчас `Normal` rule renamed 4→5. +2/-1.
- **Rationale**: «prevent revisiting same dead hypothesis class».
- **Анализ**: эмпирически обоснован — 3 stale-rationale REJECT'а в 39 iter. В прошедшем прогоне breaker НЕ сработал бы (REJECT'ы не подряд: iter-0018/0021/0023/0036, разделены ACCEPT/HOLDOUT). Но для будущих прогонов после пополнения backlog'а — реальный safety net против stall'а. Low-cost.
- **Риск**: **low** — graceful exit pattern, оператор всё равно увидит.
- **Recommended decision**: **ACCEPT**.

### 13. iter-0037 — H-029 devlog auto-entry on ACCEPT

- **Что меняет**: новый шаг 6 в `### On ACCEPT:` — записать `.claude/devlog/entries/MMMM-iter-NNNN-h-XXX-*.md` с frontmatter (id/date/title/tags=[harness,loop,accept]/status=complete) + 5 секций (Контекст/Изменения/Метрики/Затронутые файлы/Проверка), затем `python3 rebuild-index.py`. Renumber 6/7→7/8. +3/-2.
- **Rationale**: «audit trail».
- **Анализ**: **избыточен**. Текущие audit-каналы: STATE.md (verbose narrative каждой итерации), journal.md (append-only лог результатов), git history (loop commits). Devlog добавит ещё один параллельный канал — 13 entries в этом прогоне дублировали бы journal narrative. Cost real: +200-500 tokens на ACCEPT iter (~+3-5%). Failure mode: если rebuild-index.py упадёт на malformed frontmatter, instruction говорит «fix and retry, не skip» — degrades to manual operator intervention. Альтернатива (предложенная самим циклом в iter-0037 caveat): writeup только для harness-behaviour-changing ACCEPTs, не для operator-tool ACCEPTs.
- **Риск**: **low-medium** — добавляет cost и failure surface ради дублирующего канала.
- **Recommended decision**: **DEFER / REJECT**. Если хочется audit-rollup — лучше написать `python3 .claude/loop/journal-to-devlog.py` (offline post-processing, без runtime cost), чем встраивать в loop iter.

---

## Сводная таблица решений

| # | Дифф | Гипотеза | Risk | **Recommended** | Conflict-group |
|---|---|---|---|---|---|
| 1 | iter-0013 | H-011 retire dangerous-cmd-block | medium-high | **REJECT** | — |
| 2 | iter-0014 | H-012 retire secret-scan | medium | **REJECT** | — |
| 3 | iter-0017 | H-014 retire auto-format | low | **ACCEPT** | — |
| 4 | iter-0019 | H-016 consolidate workflow+multi-agent | low | **ACCEPT** | — |
| 5 | iter-0022 | H-018 opt-in stash | low | **ACCEPT (optional)** | — |
| 6 | iter-0026 | H-020 extract API constraint | low | **ACCEPT** | — |
| 7 | iter-0027 | H-021 retire_bias 5→3 | low | **ACCEPT** | corpus.yml |
| 8 | iter-0028 | H-022 sigma 2→1.5 | medium | **DEFER** (re-baseline first) | corpus.yml |
| 9 | iter-0029 | H-023 subagent_cap 3→1 | medium | **REJECT** | corpus.yml |
| 10 | iter-0031 | H-024 holdout 5→7 | medium | **DEFER** | corpus.yml |
| 11 | iter-0032 | H-025 delta_max 0.20→0.15 | medium | **DEFER** | corpus.yml |
| 12 | iter-0034 | H-028 stale-breaker | low | **ACCEPT** | PROMPT.md |
| 13 | iter-0037 | H-029 devlog-on-accept | low-medium | **DEFER** | PROMPT.md |

**Итог по рекомендациям**: **5 ACCEPT** (3, 4, 5, 6, 12) + **1 ACCEPT в corpus.yml** (7) + **2 REJECT** (1, 2, 9) + **4 DEFER** (8, 10, 11, 13). Это твой baseline — корректируй по своему суждению, моя рекомендация именно про recommended starting point. Особенно стоит перепроверить мои REJECT'ы по H-011/H-012 — там я пушу против рекомендации цикла, может быть мой counter-argument не вполне справедлив для твоего use-case.

## Apply workflow

После того как ты определился с решениями:

```bash
# 1. Apply independent ACCEPTs (Group I)
for f in iter-0017 iter-0019 iter-0022 iter-0026; do
  git apply .claude/loop/proposals/${f}-*.diff
  # review, then individual commit
done

# 2. Hand-merge corpus.yml (Group II) — open in editor, apply only H-021
# 3. Hand-merge PROMPT.md (Group III) — apply only H-028

# 4. Update backlog.md statuses: proposed→accepted / rejected (with reason)

# 5. Cleanup
rm .claude/loop/proposals/iter-{0013,0014,0017,0019,0022,0026,0027,...}-*.diff
python3 .claude/loop/proposals-review.py    # regenerate REVIEW.md

# 6. Verify protected scope
.claude/benchmark/static-checks.sh           # Tier 0 should still pass

# 7. Если планируешь возобновлять цикл — пополнить backlog (минимум H-031)
```
