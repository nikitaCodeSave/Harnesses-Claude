---
plan: .claude/plans/standard-v1-regulation.md (закрыт; это операторское ревью результатов)
last-updated: 2026-06-10
status: active
owner: оператор (Никита) — чеклист для ручного прохождения
---

# Операторское ревью «Регламент v1» — маршрут по шагам

## Quick state — трек закрыт агентом 2026-06-10 (devlog #86/#87, DoD 6/6); это чеклист РУЧНОГО ревью оператора: шаги 1–3 обязательные (~35 мин), главное решение — push migration; 10 вопросов ниже

Время: ~45–60 мин на всё. Отмечай `[x]` по ходу.

---

## Шаг 0 — Ориентация (5 мин)

- [ ] Прочитать сводки:

```bash
cat ~/PROJECTS/Harnesses-Claude/.claude/devlog/entries/0086-regulation-v1-released-t2-t4-v1-3-0.md
cat ~/PROJECTS/Harnesses-Claude/.claude/devlog/entries/0087-regulation-v1-b-c-f1-1.md
```

**#86** — релиз регламента (T1–T4). **#87** — пять решений, принятых от твоего лица, с обоснованиями. Вопрос после чтения: *«согласен ли я с пятью решениями из #87?»*

---

## Шаг 1 — AI_analyst_migration: САМОЕ ВАЖНОЕ (20 мин)

Живой рабочий проект, **4 незапушенных коммита** — финальное слово твоё.

- [ ] **1.1. Что закоммичено; твоя работа не тронута:**

```bash
cd ~/PROJECTS/AI_analyst_for_work/AI_analyst_migration
git log --oneline -4        # 8755bb1, cd2db92, 6525025, ac8780a — агентские
git status --short          # должно остаться: M infrastructure/log_setup.py + твои dev/* (untracked)
git show --stat 6525025     # самый большой коммит — только .claude/** и CLAUDE.md
```

❓ **В1:** в diff'ах нет файлов из `core/`, `application/`, `infrastructure/`? (Исключение — `tests/infrastructure/test_settings.py` в `cd2db92`, см. 1.3.)

- [ ] **1.2. Permissions-блок — единственное, что может мешать ежедневно:**

```bash
cat .claude/settings.json
```

Deny: `Read(./.env)`, `Read(./data/**)`, `Read(./logs/**)`, `allowed_users.yaml`, `dev/dump_prod_settings.txt`; ask: `git push`, prod-docker.

❓ **В2:** просишь ли Claude в этом проекте регулярно *читать* `data/` (monitoring) или `logs/`? Если да — ослабить конкретное правило (trade-off: там PII и креды банка). Правка — одна строка в `settings.json`.

- [ ] **1.3. Тест-фикс — проверить рассуждение агента:**

```bash
git show cd2db92                       # тест 0.7 → 0.5
git show bbf49e7 --stat | head -5      # твой коммит, где default менялся намеренно
./init.sh                              # зелёный: 1398 passed
```

❓ **В3:** 0.5 — намеренный default (не временный эксперимент)? Если хотел откатить — вернуть обе строки (код и тест) одним коммитом.

- [ ] **1.4. Ретайрменты — изменят привычки:**

```bash
ls .claude/agents/    # осталось 3: security-auditor, spec-reviewer, tdd-test-writer
ls .claude/skills/    # 11; sync-docs и refactor удалены, parallel-execute DEPRECATED
cat .claude/GUIDE.md  # было 626 строк, стало 139 — главный объект ревью
```

❓ **В4:** по новому `GUIDE.md` по-прежнему можно выбрать правильный ритуал для типовой задачи? Если чего-то не хватает — дефект ужатия G12, сказать агенту.
❓ **В5:** `/implement` теперь по умолчанию single-context TDD (тройка — opt-in для high-stakes). **Первая реальная задача через новый `/implement` = эмпирическая проверка решения D2** (см. `.claude/progress/d2-tdd-agents-retired.md`). Станет хуже → `git revert 6525025`.

- [ ] **1.5. Закрытие gap-report построчно:**

```bash
cat .claude/audit/gap-report-2026-06-10.md   # в конце — секция «Closure»
```

❓ **В6:** согласен с отклонением G16 (devlog остался `devlog/changelog.json`)? Если всё же нужен канонный формат — отдельная сессия, конвертация описана в строке G16.

- [ ] **1.6. РЕШЕНИЕ О PUSH:**

```bash
git push origin main   # когда (и если) всё выше устроило
```

Ветка получит и твой будущий коммит `log_setup.py` — он по-прежнему незакоммичен.

---

## Шаг 2 — Канон `~/.claude` (10 мин)

Уже запушено (откат = revert), но это твой ежедневный инструмент.

- [ ] Прочитать:

```bash
cd ~/.claude
git log --oneline -4    # 6036560 (T1, v1.2.0), 8b809be (T3-fold), 5f9734e (T4-fold, v1.3.0)
cat README.md           # новая секция «Вход в регламент» — главная правка
cat skills/claude-code-harness/references/operator-playbook.md   # ~110 строк, 5 минут
```

❓ **В7:** прочитать playbook целиком как пользователь — это **тот самый «единый формат workflow»**. Спорные места через T4-находки: §2 (ledger засеивает сессия, ревьюишь ты), §3 (диск истиннее контракта; смотреть, что зарезолвил PATH), §5 (имя команды при plugin-доставке — `claude-code-harness:external-audit`).
❓ **В8:** согласен с headless-резолюцией approve-гейта (bootstrap без оператора «действует и фиксирует план», а не стоит)? Правка в `references/bootstrap-checklist.md`, Phase 1.

- [ ] (опц., 2 мин) Проверка доставки: `claude plugin details claude-code-harness` → v1.3.0, Skills 2 / Agents 3.

---

## Шаг 3 — prompt-regress: новый продукт из T3 (10 мин)

- [ ] Осмотреть и прогнать:

```bash
cd ~/PROJECTS/prompt-regress
git log --oneline            # 7 коммитов: bootstrap → F1 RED → GREEN → долг → F1.1 RED → GREEN → docs
./init.sh                    # зелёный, 22 passed
cat CLAUDE.md .claude/features.json
cat .claude/harness-journal.md   # 6+ наблюдений — сырьё будущих D-циклов
```

- [ ] Попробовать тулзу на своих данных:

```bash
.venv/bin/python -m promptdiff compare \
  --baseline ~/PROJECTS/AI_analyst_for_work/AI_analyst_migration/dev/validation/results/baseline-prod-prompt-old.csv \
  --candidate ~/PROJECTS/AI_analyst_for_work/AI_analyst_migration/dev/validation/results/BUCKETING-fix-prod.csv \
  --out /tmp/report.json --md /tmp/report.md && cat /tmp/report.md | head -30
```

❓ **В9:** верна ли продуктовая траектория F2–F4 в `features.json` (batch-run через executor-адаптер, stability-режим, журнал итераций)? Поправить приоритеты до следующей сессии.
❓ **В10:** нужен ли репо remote на GitHub? Агент его не создавал.

---

## Шаг 4 — Артефакты доказанности (по желанию)

`~/PROJECTS/Harnesses-Claude/.claude/audits/`:

| Каталог | Что внутри | Зачем |
|---|---|---|
| `t1-smoke/` | `T1-REPORT.md` + 11 логов | провенанс установки на чистые профили |
| `t2-migration/` | `GAP-REPORT.md` (с closure), `APPLY-RESULT.json`, **бэкап-tar** | полный аудит легаси + бэкап слоя до правок |
| `t3-prompt-regress/` | `T3-RESULT.json` | вердикты bootstrap/feature/Evaluator |
| `t4-walkthrough/` | `AUDIT-VERDICT.json`, `T4-REPORT.md` | как два «новичка» прошли регламент |

Якорь обратимости: `t2-migration/backup-claude-layer-2026-06-10.tar.gz` — полный `.claude/`+CLAUDE.md+devlog migration **до** правок (HEAD был `8a9e83c`).

---

## Шаг 5 — Оставшиеся хвосты

- [ ] **`git push` в migration** — после шага 1 (учти CI/деплой от push в main, если есть).
- [ ] **Docstring `application/agent.py:5`** — всё ещё «8-шагового pipeline»; одна строка в следующем PR, трогающем код (агент в код не лез сознательно).
- [ ] **Watch D2**: на первой реальной задаче через обновлённый `/implement` в migration оценить, не стало ли хуже без TDD-тройки — закрыть решение фактом.

## Завершение ревью

Когда все чекбоксы закрыты: сказать агенту «ревью пройдено, удали operator-review» (+ ответы на В1–В10, где есть несогласие) — файл конвертируется в короткую devlog-запись и удаляется по rule #7.
