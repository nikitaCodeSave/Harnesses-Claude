# T4 Walkthrough Audit — Adjudicator Report

- **Date:** 2026-06-10
- **Scope:** Regulation v1 operator playbook walkthrough (контракт R2, адаптация)
- **Playbook:** `/home/nikita/.claude/skills/claude-code-harness/references/operator-playbook.md`
- **Verdict:** `confirmed_with_debt` (см. `AUDIT-VERDICT.json`)
- **Role verdicts:** new_project = `passed_with_friction`; legacy_project = `passed_with_friction`

## Executed steps — walkthrough_new_project

| # | Шаг | Исполнен? | Ключевое evidence |
|---|---|---|---|
| 1 | Entry point: README.md → lifecycle | да | README прочитан; playbook из README НЕ достижим (нашёл через SKILL.md:77) |
| 2 | Чтение playbook + SKILL.md + bootstrap-checklist | да | все 3 файла прочитаны |
| 3 | Фикстура: пустой репо + git init | да | /tmp/t4-walkthrough-new |
| 4 | Bootstrap Phase 0 read-the-room | да | claude 2.1.170; git log fatal на 0-commit репо (friction) |
| 5 | Phase 1: план + approval | да (self-approved) | approval-канала в headless нет — противоречие playbook §1 vs checklist |
| 6 | Phase 2: CLAUDE.md ≤200 строк | да | ~60 строк по шаблону |
| 7 | Phase 3: settings.json (deny over allow) | да | tuned to what exists, без спекулятивных правил |
| 8 | §2: Phase 5 kit (oracle/features.json/progress/devlog/journal) | да | ./init.sh GREEN day 0; F1-F3 passes:false; commit 2a3d4b0 |
| 9 | §1 check: `claude --print "what is the project's stack?"` | да | ответ точно по CLAUDE.md, EXIT=0 |
| 10 | Phase 7 check: `claude --print "ls"` | да | прошёл механически, но критерий 'settings load + obey' непроверяем по ls-ответу |
| 11 | §3 session-start ритуал + preconditions | да | ритуал исполнен буквально, oracle GREEN до работы |
| 12 | §3: F1 по TDD red→green | да | genuine RED (ceaaf28) → GREEN (0180cb2); verify исполнен дословно; silent micro-decision: conftest.py/sys.path |
| 13 | §3 конец сессии: commit/progress/passes-дисциплина | да | только F1 passes:true; oracle GREEN re-run |
| 14 | Phase 5 journal: честные наблюдения | да | 3 наблюдения, вкл. PATH-hygiene дыру (чужой venv через PATH fallback) |

## Executed steps — walkthrough_legacy_project

| # | Шаг | Исполнен? | Ключевое evidence |
|---|---|---|---|
| 1 | Entry point README.md | да | grep 'playbook' → 0; quick-start только new-project |
| 2 | Фикстура: легаси-репо с грязным harness'ом | да | CLAUDE.md 252 строки, orchestrator.md-дубль, settings без permissions |
| 3 | README → playbook по цепочке ссылок | да | 2 прыжка + листинг каталога, через model-facing SKILL.md |
| 4 | §4 Audit mode: audit-checklist top-down | да | wc/cat/head/grep по фикстуре; правок нет (per checklist) |
| 5 | §4 gap-report по шаблону | да | F1-F4 + recommended order; шаблон — в третьем файле (SKILL.md), friction |
| 6 | §5 /external-audit: существование команды | да | файл есть; `claude plugin list` → v1.2.0 loaded |
| 7 | §5 Шаг 0 (scope/preconditions) | да | features.json/progress отсутствуют — поведение не специфицировано, импровизация |
| 8 | §5 Шаг 1 до точки спавна: резолвинг ролей + fallback | частично | пути проверены живьём (ls, env); полный 3-ролевой прогон НЕ запускался |
| 9 | §6/§7: harness-evolution.md + исполнимость триггеров | чтение + tool-existence | --safe-mode и plugin tag/validate подтверждены в бинаре; полного D-цикла/strip не было |

**Rule 3 note:** new_project-walker исполнял полностью — полное доверие. legacy-walker шаги 8-9 исполнил частично (резолвинг и проверки бинаря — да; спавн ролей и сам D-цикл — нет): доверие к его выводам по §5-спавну и §6/§7 понижено, но его findings там опираются на исполненные ls/CLI-проверки, не на чистое чтение, поэтому не отброшены.

## Surviving findings (12; 2 major, 10 minor)

| # | Severity | Источник | Finding | Ref |
|---|---|---|---|---|
| 1 | **major** | оба (corroborated) | README не ссылается на operator-playbook.md — lifecycle §3-§7 недостижим от заявленной точки входа; legacy-сценарий из README недостижим вовсе | README ↔ playbook |
| 2 | **major** | new_project | Approval-gate противоречие: checklist Phase 1 требует approval before writing, playbook §1 — fire-and-forget; headless-поведение не определено | §1 / Phase 1 |
| 3 | minor | new_project | Кто и как сидит features.json — не определено (granularity, review засеянного ledger'а) | §2.2 / 5.2 |
| 4 | minor | new_project | Explicit-contract rule не предотвратил silent micro-decision на фиче #1 (src-layout import без pyproject) | Phase 5.2 |
| 5 | minor | new_project | PATH-hygiene дыра per-tool resolve: fallback зарезолвил python3 из чужого venv; регламент не велит проверять, во что зарезолвилось | §3 |
| 6 | minor | new_project | Phase 7 check `claude --print "ls"` — vague pass criterion, ничего не доказывает про settings | Phase 7 |
| 7 | minor | new_project | Phase 0 `git log | wc -l` — fatal на 0-commit репо (канонический new-repo путь) | Phase 0 |
| 8 | minor | legacy | Шаблон gap-report'а в SKILL.md, а §4 шлёт только в checklist — третий файл без упоминания | §4 |
| 9 | minor | legacy | external-audit Шаг 0.1: нет ветки «features.json/progress отсутствуют» для legacy без kit | §5 Шаг 0 |
| 10 | minor | legacy | ROLE_DIR fallback проверяет существование каталога, не role-файлов — каталог с посторонним содержимым обходит стоп-условие | §5 Шаг 1 |
| 11 | minor | legacy | Pre-flight native-видимости 3 agent-типов снаружи сессии недоступен; рабочий indirect (`claude plugin list`) нигде не предложен | §5 Шаг 1 |
| 12 | minor | legacy | D-цикл триггер «≥5 наблюдений» мёртв by design для legacy без opt-in journal; evolution.md это не оговаривает | §6-§7 |

Каждый surviving finding — actionable item для D-цикла Phase 4.

## Dismissed findings

Нет (0). Ни одно finding не опровергнуто реальным исполнением другого walker'а; единственное пересечение (README→playbook discoverability) — независимая корроборация, слито в finding #1 с повышением до major.

## Blocking questions (от walkers, для оператора)

1. Как новичок, имеющий только README.md, должен узнать о существовании operator-playbook.md (§3 build-ритуал, §5 external-audit, §6 D-цикл)? README на него не ссылается.
2. Кто принимает approval в bootstrap Phase 1, когда bootstrap запускается headless/одной командой — агент ждёт или self-approve допустим?
3. Кто и как утверждает засеянный features.json (granularity, verify-контракты)? Процедура и владелец декомпозиции не определены.

(legacy-walker blocking questions: нет)
