# Devlog TL;DR

Derived view — генерируется `rebuild-index.py` из `entries/*.md`.
Источник правды — `entries/`. **Этот файл не редактируется вручную.**

Назначение: холодный вход агента / читателя в проектную хронологию
без открытия всех entry-файлов целиком. Записи отсортированы по id desc.

---

## #56 · 2026-05-29 · system-guard simplified to DENY-only

**Tags:** refactor, harness, hooks

Сразу после hardening (#55) оператор: «system-guard можно упростить — модель умная, очевидно опасное не сделает; хук скорее формальность + дополнительный контроль». Это согласуется с central principle (минимум обвязки под Opus 4.8) и с пережитым в этой сессии трением (ASK на…

[→ entries/0056-system-guard-simplified-to-deny-only.md](entries/0056-system-guard-simplified-to-deny-only.md)

---

## #55 · 2026-05-29 · Guardrails pillar — system-guard hardening

**Tags:** feature, harness, hooks, security

Третий столб practice-слоя (после methodology #53, continuity #54): guardrails. Открытие при разведке: глобальный baseline уже существует — ~/.claude/hooks/system-guard.sh (PreToolUse, 3 tier: DENY катастрофика / ASK рискованное-обратимое / LOG sudo-audit). Значит «полная…

[→ entries/0055-guardrails-pillar-system-guard-hardening.md](entries/0055-guardrails-pillar-system-guard-hardening.md)

---

## #54 · 2026-05-29 · Continuity pillar — global SessionStart context hook

**Tags:** feature, harness, hooks

Второй столб practice-слоя (после methodology, #53): сделать «что было до» глобальным дефолтом. Раньше continuity-сёрфинг работал ТОЛЬКО в этом lab-репо через project-level .claude/hooks/session-context.sh. Цель — в ЛЮБОМ проекте Claude при старте видит недавнюю историю работы…

[→ entries/0054-continuity-pillar-global-sessionstart-context-hook.md](entries/0054-continuity-pillar-global-sessionstart-context-hook.md)

---

## #53 · 2026-05-29 · Test-quality methodology pillar (global, evidence-grounded)

**Tags:** feature, harness, adr

Оператор сформулировал недостающее звено: harness ценен как standing development-practice layer (заточить Claude под разработку), а не как разовый bootstrap; и не хватало надёжного методологического слоя (приходилось переруливать BDD/TDD в каждом проекте, чтобы не было…

[→ entries/0053-test-quality-methodology-pillar-global-evidence-grounded.md](entries/0053-test-quality-methodology-pillar-global-evidence-grounded.md)

---

## #52 · 2026-05-29 · Benchmark text2sql Opus 4.8: harness vs noharness (n=1)

**Tags:** benchmark, harness

Re-measurement cost-envelope под Opus 4.8 (триггер из devlog #50/#51 — major model upgrade). Прогон battle-test-runner.sh --task text2sql на двух армах: harness=ours vs noharness, оба --build-model opus --judge-model opus (4.8), последовательно (чтобы избежать contention на…

[→ entries/0052-benchmark-text2sql-opus-4-8-harness-vs-noharness-n-1.md](entries/0052-benchmark-text2sql-opus-4-8-harness-vs-noharness-n-1.md)

---

## #51 · 2026-05-29 · Lab docs re-grounded to Opus 4.8 + dynamic workflows

**Tags:** docs, harness

Продолжение devlog #50 (то записало «остаётся глубокий re-ground lab-доков»). Четыре on-demand reference-дока были приколочены к Opus 4.7 / CC 2.1.143 и пропускали главный новый workflow-примитив — dynamic workflows. Harness'а собственная доктрина (workflow-evolution.md)…

[→ entries/0051-lab-docs-re-grounded-to-opus-4-8-dynamic-workflows.md](entries/0051-lab-docs-re-grounded-to-opus-4-8-dynamic-workflows.md)

---

## #50 · 2026-05-29 · Harness starter consolidated under Opus 4.8

**Tags:** refactor, harness

Оператор указал, что «стартовый harness первой сессии» перегружен и местами хуже голого claude. Разведка двумя субагентами вскрыла корень: «стартер» = глобальный слой ~/.claude/, и в нём жили ДВА конкурирующих bootstrap-скилла. Глобальный harness-setup (Python-only, 19…

[→ entries/0050-harness-starter-consolidated-under-opus-4-8.md](entries/0050-harness-starter-consolidated-under-opus-4-8.md)

---

## #49 · 2026-05-18 · Working style block added to harness-setup template (A/B/C N=3×3)

**Tags:** adr, harness, experiment

Оператор сообщил, что /harness-setup (skill claude-code-harness) генерирует target-CLAUDE.md без behavioral guidance — нет «думай прежде чем кодить / минимум кода / surgical changes / verifiable goals», которые Карпати [сформулировал в…

[→ entries/0049-working-style-block-added-to-harness-setup-template-a-b-c-n.md](entries/0049-working-style-block-added-to-harness-setup-template-a-b-c-n.md)

---

## #48 · 2026-05-18 · Workflow doc split — 6-файловый layout с empirical grounding 2026 Q2

**Tags:** docs, harness, refactor

Заменили монолитный workflow.md (380 строк, 2026-05-10 vintage) на тонкий spine + 5 slice docs. Старая версия дублировала Anthropic-canonical feature-dev plugin и игнорировала весь inventory Claude Code 2.1.143 (Monitor tool, /goal, dispatch flags v2.1.142, hooks v2.1.139…

[→ entries/0048-workflow-doc-split-6-layout-empirical-grounding-2026-q2.md](entries/0048-workflow-doc-split-6-layout-empirical-grounding-2026-q2.md)

---

## #47 · 2026-05-17 · harness-setup items 1-3 closed (ruff/py-detect/B7)

**Tags:** refactor, harness, skill

Closure трёх deferred open items из devlog #46 для ~/.claude/skills/harness-setup/. Все три — разные axis того же anti-pattern #15 «prescribe-without-detect» + один scope decision. Цель — устранить friction день 1 на user'ских системах с Python ≠ 3.12 и формализовать sample-app…

[→ entries/0047-harness-setup-items-1-3-closed-ruff-py-detect-b7.md](entries/0047-harness-setup-items-1-3-closed-ruff-py-detect-b7.md)

---

## #46 · 2026-05-17 · /harness-setup audit — 13 fixes + anti-pattern #15

**Tags:** refactor, harness, skill, audit

Сессия комплексного аудита skill'а ~/.claude/skills/harness-setup/ против leader-canon (Anthropic Best Practices / Effective Harnesses / Cherny howborisusesclaudecode / NLAH arXiv 2603.25723 / Meta-Harness arXiv 2603.28052 / Chroma Context Rot). Поводом стал реальный run…

[→ entries/0046-harness-setup-audit-13-fixes-anti-pattern-15.md](entries/0046-harness-setup-audit-13-fixes-anti-pattern-15.md)

---

## #45 · 2026-05-16 · Harness-setup final outcome contract v3

**Tags:** refactor, adr, harness, skills

Pilot run /harness-setup на /home/nikita/PROJECTS/test/ (2026-05-16) выявил пять новых проблем после compact reorg v2 (#44):

[→ entries/0045-harness-setup-final-outcome-contract-v3.md](entries/0045-harness-setup-final-outcome-contract-v3.md)

---

## #44 · 2026-05-16 · Harness-setup compact reorg v2

**Tags:** refactor, adr, harness, skills

Pilot iteration 2 теста /harness-setup на пустом репо (/home/nikita/PROJECTS/test/) обнаружила два structural дефекта: (а) F8d block .venv/bin/ prefix баг — skill подставлял .venv/bin/<tool> для всех Python инструментов, не различая глобальный ruff (~/.local/bin/) от venv-bound…

[→ entries/0044-harness-setup-compact-reorg-v2.md](entries/0044-harness-setup-compact-reorg-v2.md)

---

## #43 · 2026-05-16 · harness-setup → team-ready Python-only (Windows-native, settings split, idempotent)

**Tags:** skill, harness-setup, refactor, testing

User-level skill ~/.claude/skills/harness-setup был в pre-release состоянии (создан 2026-05-15), e2e empirically tested только на Python с 4 stack-skeleton'ами (Python / Node / Rust / Go), bash-only hooks (stop-verify.sh, format.sh), single-file settings.json без team/personal…

[→ entries/0043-harness-setup-team-ready-python-only-windows-native-settings.md](entries/0043-harness-setup-team-ready-python-only-windows-native-settings.md)

---

## #42 · 2026-05-13 · Evaluator v2.0: schema enforcement — prompt + rubric layer guards

**Tags:** refactor, harness, agents, testing

Полное тестирование v2.0 как production-ready harness component выявило класс багов «schema drift в реальном critic spawn». Critic не следовал declared CRITIC.json v2.0 schema, rubric Step 3 silently fallback'ил на дефолты (// "", 0 from [].length on empty array) и выдавал…

[→ entries/0042-evaluator-v2-0-schema-enforcement-prompt-rubric-layer-guards.md](entries/0042-evaluator-v2-0-schema-enforcement-prompt-rubric-layer-guards.md)

---

## #41 · 2026-05-13 · Evaluator v2.0: class-based rubric + independent probe + EVIDENCE re-execution

**Tags:** refactor, harness, agents, hooks

Adversarial review evaluator-связки (discovery-critic agent + /critique slash command + harness-internal discovery-gate.sh hook) выявил 8 структурных слабостей v1.0 после #39: (1) PREMORTEM анкорит критика на авторском фрейминге — Phase 1 verification идёт первой, Phase 2…

[→ entries/0041-evaluator-v2-0-class-based-rubric-independent-probe-evidence.md](entries/0041-evaluator-v2-0-class-based-rubric-independent-probe-evidence.md)

---

## #40 · 2026-05-13 · Расследование gating механизма claude --bg / Agent View (2.1.140)

**Tags:** research, claude-code-builtins, factcheck, cli-gating

После релиза Claude Code 2.1.140 (changelog упоминает фикс claude --bg "connection dropped mid-request") оператор попросил протестировать функционал. Запуск claude --bg "echo test" неизменно возвращает '--bg' is not enabled. If this is unexpected, retry in a moment. — и в nested…

[→ entries/0040-gating-claude-bg-agent-view-2-1-140.md](entries/0040-gating-claude-bg-agent-view-2-1-140.md)

---

## #39 · 2026-05-13 · Evaluator decoupling: JSON artifacts + /critique slash command

**Tags:** refactor, harness, agents, hooks, adr

Evaluator-узел Planner→Generator→Evaluator (discovery-critic agent + discovery-gate.sh Stop hook) был coupled к benchmark-инфраструктуре: триггер через HARNESS_BENCH_MODE=1 / .benchmark-active marker, артефакты PREMORTEM.md / EVIDENCE.md / CRITIC.md с regex-парсимой строкой…

[→ entries/0039-evaluator-decoupling-json-artifacts-critique-slash-command.md](entries/0039-evaluator-decoupling-json-artifacts-critique-slash-command.md)

---

## #38 · 2026-05-12 · Memory layers doc and progress.md convention

**Tags:** memory, docs, harness, conventions

Запрос от оператора: «как должна реализовываться внутренняя память между сессиями и между агентами? Что советуют Boris Cherny / Matt Pocock / industry?». Triggered by предыдущий research-pass про /goal + agent view (devlog #37), где обнаружилось что чужие тексты приносят ложные…

[→ entries/0038-memory-layers-doc-and-progress-md-convention.md](entries/0038-memory-layers-doc-and-progress-md-convention.md)

---

## #37 · 2026-05-12 · Empirical fact-check /goal + agent view + continueOnBlock (Claude Code 2.1.139)

**Tags:** research, claude-code-builtins, harness-integration, factcheck

Оператор предложил «полноценный рефакторинг harness'а под built-ins Claude Code 2.1.139» на основе чужого текста про «мета-роль агента». В тексте утверждалось: /goal — built-in с Haiku-evaluator, /spec — для plan-блоков, continueOnBlock — новый hook field, agent view = TUI для…

[→ entries/0037-empirical-fact-check-goal-agent-view-continueonblock-claude.md](entries/0037-empirical-fact-check-goal-agent-view-continueonblock-claude.md)

---

## #36 · 2026-05-11 · Battle-test n=3 — sign-inversion CONFIRMED, harness wins +4pt

**Tags:** benchmark, battle-test, harness, statistical-protocol, sign-inversion, evidence-based

Phase 2.B (operator approved post-2.6) — n=3 enforcement на text2sql battle-test. Previous session (devlog #35) declared «noise band -1pt» based on n=1. Layer D protocol требует n=3 minimum для статистических claim'ов. Phase 2.B завершил 4 incremental builds (2 ours + 2…

[→ entries/0036-battle-test-n-3-sign-inversion-confirmed-harness-wins-4pt.md](entries/0036-battle-test-n-3-sign-inversion-confirmed-harness-wins-4pt.md)

---

## #35 · 2026-05-11 · Battle-test text2sql first comparison — 87 vs 88, 10 runner bugs fixed

**Tags:** benchmark, battle-test, harness, deliverable-scale, empirical, evidence-based

Phase 2.3 + 2.6 — первая end-to-end валидация battle-test infrastructure на text2sql-Oracle F-deliverable task. Ours vs no-harness, n=1 each. Operator approved sequential gates: 2.3 ours build → fix bugs → run llm-judge → 2.6 noharness full pipeline → comparison aggregate.

[→ entries/0035-battle-test-text2sql-first-comparison-87-vs-88-10-runner-bug.md](entries/0035-battle-test-text2sql-first-comparison-87-vs-88-10-runner-bug.md)

---

## #34 · 2026-05-11 · Phase 2 — battle-test-runner.sh + grade.py + llm-judge.sh complete (no OAuth burn)

**Tags:** benchmark, battle-test, harness, deliverable-scale, ralph-patterns, no-oauth

Devlog #33 — scaffolding (fixture + judge artifacts). Phase 2 — runner + grader + LLM-judge code, без OAuth. Operator явно попросил «использовать что есть из логики RALPH (.claude/loop) + провалидировать весь пайплайн» — сначала ревью loop/ patterns, потом integration. Цель…

[→ entries/0034-phase-2-battle-test-runner-sh-grade-py-llm-judge-sh-complete.md](entries/0034-phase-2-battle-test-runner-sh-grade-py-llm-judge-sh-complete.md)

---

## #33 · 2026-05-11 · Battle-test text2sql-Oracle — scaffolding (F-deliverable task type)

**Tags:** benchmark, battle-test, harness, deliverable-scale, oracle, ollama

После P4 (devlog #32) operator предложил новый task type — F-deliverable: Claude строит production-grade text2sql ассистента с нуля на реальной инфраструктуре (Oracle XE Docker + Ollama локально). Это качественно отличается от existing micro-benchmarks:

[→ entries/0033-battle-test-text2sql-oracle-scaffolding-f-deliverable-task-t.md](entries/0033-battle-test-text2sql-oracle-scaffolding-f-deliverable-task-t.md)

---

## #32 · 2026-05-11 · P4 trip-wire invariants — first behavioral validation of harness value

**Tags:** benchmark, harness, invariants, evidence-based, layer-c-validation

P1+P2 (devlog #30) + n=1 baseline (#31) показали что Layer C trajectory parser работает на synthetic stream-json, но три из четырёх метрик (skills_triggered, invariant_pings, workflow_markers) никогда не были non-zero на benign tasks T01-T04. Без adversarial probing мы не знали…

[→ entries/0032-p4-trip-wire-invariants-first-behavioral-validation-of-harne.md](entries/0032-p4-trip-wire-invariants-first-behavioral-validation-of-harne.md)

---

## #31 · 2026-05-11 · Headless runner hardening + T01-T04 trajectory baseline (n=1)

**Tags:** benchmark, harness, infrastructure, evidence-based

После P1+P2 (devlog #30) operator дал явное go на smoke-валидацию runner'а под новой stream-json + trajectory методологией и последующий re-prog T01-T04. Smoke выявил 4 проблемы в runner'е, каждая зафиксирована, после чего прогнан 8-run baseline (4 tasks × 2 harness variants)…

[→ entries/0031-headless-runner-hardening-t01-t04-trajectory-baseline-n-1.md](entries/0031-headless-runner-hardening-t01-t04-trajectory-baseline-n-1.md)

---

## #30 · 2026-05-11 · Benchmark redesign — 4-layer model + trajectory metrics (P1+P2)

**Tags:** benchmark, harness, methodology, evidence-based

Текущий бенчмарк (3-tier model, 5 задач, 4 fixture-варианта) хорошо ловил token/turn/cost deltas — empirical evidence «harness ROI ∝ exploration cost» (devlog #24-25) получено именно через него. Но методология имела 5 blind spots:

[→ entries/0030-benchmark-redesign-4-layer-model-trajectory-metrics-p1-p2.md](entries/0030-benchmark-redesign-4-layer-model-trajectory-metrics-p1-p2.md)

---

## #29 · 2026-05-11 · Ralph Loop operator review — 7 accept, 6 reject

**Tags:** adr, harness, cleanup

Ralph Loop (39 итераций, ~4ч wall-clock, $72.50) завершился штатно — RESULT:NOOP empty-backlog на iter-0038, PAUSED.md записан. На момент остановки в .claude/loop/proposals/ накопилось 13 pending PROPOSAL-диффов против protected-файлов, ожидающих человеческого ревью. Operator…

[→ entries/0029-ralph-loop-operator-review-7-accept-6-reject.md](entries/0029-ralph-loop-operator-review-7-accept-6-reject.md)

---

## #28 · 2026-05-11 · Loop iter-0001 first ACCEPT + Bug 3 fix + launch readiness

**Tags:** harness, self-improvement, loop, smoke, accept, evidence

Continuation devlog #27 (Milestone 2/3 smoke с обнаруженными bugs). User authorized автономный fix Bug 3 + re-smoke validation. Это итог: first successful iteration.

[→ entries/0028-loop-iter-0001-first-accept-bug-3-fix-launch-readiness.md](entries/0028-loop-iter-0001-first-accept-bug-3-fix-launch-readiness.md)

---

## #27 · 2026-05-11 · Self-improvement Ralph-loop — Milestone 2/3 smoke and fixes

**Tags:** harness, self-improvement, loop, ralph, smoke, benchmark, evidence

Continuation of devlog #26 (Milestone 1 scaffolding). User explicit authorization to do all Milestone 2/3 work autonomously: corpus extension, backlog generation, fixture clone, smoke loop, fixes, ADR.

[→ entries/0027-self-improvement-ralph-loop-milestone-2-3-smoke-and-fixes.md](entries/0027-self-improvement-ralph-loop-milestone-2-3-smoke-and-fixes.md)

---

## #26 · 2026-05-11 · Self-improvement Ralph-loop — Milestone 1 scaffolding

**Tags:** harness, self-improvement, loop, ralph, scaffolding

User authorized многочасовой autonomous self-improvement цикл harness'а по аналогии с Ralph-pattern ([Mishra-Sharma «Long-running Claude», Mar 2026](https://www.anthropic.com/research/long-running-Claude) + Huntley ralph-wiggum). Goal: эмпирическая эволюция harness'а для…

[→ entries/0026-self-improvement-ralph-loop-milestone-1-scaffolding.md](entries/0026-self-improvement-ralph-loop-milestone-1-scaffolding.md)

---

## #25 · 2026-05-11 · T03 FastAPI cross harness sign inversion

**Tags:** benchmark, harness, evidence, fastapi

User explicit authorization прогонять T03 на FastApi-Base (realistic FastAPI template, domain-based, async SQLAlchemy, ~30 files), сбрасывая Claude artefacts между runs. T03 spec уже существовал (tier1/tasks/T03-fastapi-health-endpoint.yaml), но ни разу не прогонялся — fixture…

[→ entries/0025-t03-fastapi-cross-harness-sign-inversion.md](entries/0025-t03-fastapi-cross-harness-sign-inversion.md)

---

## #24 · 2026-05-11 · Cross-harness empirical benchmark + headless-runner bug fixes

**Tags:** benchmark, harness, evidence

User-explicit authorization для проверки совместимости харнесов из community ecosystem (статья «HARNESSES для Claude Code», май 2026). Real-world benchmark под Opus 4.7 на одном fixture (sample-py-app), four harness variants. Previous devlog 0023 documented classifier…

[→ entries/0024-cross-harness-empirical-benchmark-headless-runner-bug-fixes.md](entries/0024-cross-harness-empirical-benchmark-headless-runner-bug-fixes.md)

---

## #23 · 2026-05-11 · Headless-runner infrastructure + classifier constraint finding

**Tags:** feature, harness

Запрос: возможность тестировать harness наработки на external projects (e.g. FastApi-Base) и замерять качество через benchmark. Без real headless invocation Tier 1 остаётся scaffolding-only (run-tier1.sh только validates structure).

[→ entries/0023-headless-runner-infrastructure-classifier-constraint-finding.md](entries/0023-headless-runner-infrastructure-classifier-constraint-finding.md)

---

## #22 · 2026-05-11 · Stop-validation multi-gate + --bare references cleanup

**Tags:** feature, harness

Phantom-completion (модель декларирует «готово», а lint/types ругаются) — реальная проблема dev-loop под Opus 4.7, не закрытая существующим stop-hook (тот гонял только pytest/npm test). Community evidence: 35% → 4% false-completion после independent verification.

[→ entries/0022-stop-validation-multi-gate-bare-references-cleanup.md](entries/0022-stop-validation-multi-gate-bare-references-cleanup.md)

---

## #21 · 2026-05-10 · benchmark infrastructure stop hook

**Tags:** feature, harness, benchmark, hooks

Пользователь дал директиву (2026-05-10) закрыть measurement gap из предыдущей сводки: «без формальных evals (Tier 1/2 task-suite runs) сравнение с industry — structural / pattern-based, не performance-quantitative». Просьба: загрузить в проект исходники для тестирования +…

[→ entries/0021-benchmark-infrastructure-stop-hook.md](entries/0021-benchmark-infrastructure-stop-hook.md)

---

## #20 · 2026-05-10 · principles.md rewrite evidence-based

**Tags:** docs, harness, refactor, research

Пользователь дал директиву (2026-05-10): «.claude/docs/principles.md отсылки к ADR — этого быть не должно, отсылки к архивной информации, ознакомься с документацией Anthropic, Claude code и полностью перепиши документ согласно лучшим рекомендациям вспомогательным докам для…

[→ entries/0020-principles-md-rewrite-evidence-based.md](entries/0020-principles-md-rewrite-evidence-based.md)

---

## #19 · 2026-05-10 · D-022 subagent isolation opt-in

**Tags:** adr, harness, workflow, research

Пользователь дал две директивы (2026-05-10):

[→ entries/0019-d-022-subagent-isolation-opt-in.md](entries/0019-d-022-subagent-isolation-opt-in.md)

---

## #18 · 2026-05-10 · workflow.md Plan→Work→Review canonical spine

**Tags:** docs, harness, workflow, research

Пользователь дал critical feedback: harness слишком опирался на свои же ранее зафиксированные ADR'ы как ground truth, не консультируясь с первоисточниками (Anthropic engineering blog, claude.com docs, GitHub репозитории, community 2026 essays). Это приводило к stale решениям и…

[→ entries/0018-workflow-md-plan-work-review-canonical-spine.md](entries/0018-workflow-md-plan-work-review-canonical-spine.md)

---

## #17 · 2026-05-10 · Harness self-contained: docs moved to .claude/docs/

**Tags:** refactor, docs, harness, portability

Harness — это переносимый pack, который инсталлируется в произвольный target-проект (/path/to/SomeProject/.claude/). У target-проекта обычно собственный docs/ (создаваемый project-docs-bootstrap skill: ARCHITECTURE.md, CODE-MAP.md, ADR/, RUNBOOKS/).

[→ entries/0017-harness-self-contained-docs-moved-to-claude-docs.md](entries/0017-harness-self-contained-docs-moved-to-claude-docs.md)

---

## #16 · 2026-05-10 · D-021: two-tier docs split (active vs archive)

**Tags:** docs, harness, refactor

Append-only history (docs-discipline rule #3, ADR-017) стал friction'ом против foundational principle. Каждый retired/superseded ADR продолжал жить в active context: HARNESS-DECISIONS.md достиг ~67 KB, 397 строк, 18 ADR'ов. CLAUDE.md ссылается на этот файл как «читать перед…

[→ entries/0016-d-021-two-tier-docs-split-active-vs-archive.md](entries/0016-d-021-two-tier-docs-split-active-vs-archive.md)

---

## #15 · 2026-05-10 · Tier 0/1 dogfood + ADR-020 fixes

**Tags:** benchmark, harness, docs, adr

Первое реальное прогон benchmark methodology из ADR-019. Tier 0 automated (static-checks.sh implementation), Tier 1 dogfood на FastApi-Base fixture с генерацией реальных docs (per project-docs-bootstrap skill workflow Phase 1-5). Three methodology gaps выявлены и зафиксированы…

[→ entries/0015-tier-0-1-dogfood-adr-020-fixes.md](entries/0015-tier-0-1-dogfood-adr-020-fixes.md)

---

## #14 · 2026-05-10 · ADR-018/019: tight format + tiered benchmark

**Tags:** adr, harness, docs, benchmark

Continuation сессии 2026-05-10. После ADR-017 (project docs bootstrap skill + discipline rule) пользователь явно дал три задачи: (а) skill-creator validation новой skill, (б) ADR-018 на refactor HARNESS-DECISIONS.md format, (в) проработка benchmark подхода для testing/validation…

[→ entries/0014-adr-018-019-tight-format-tiered-benchmark.md](entries/0014-adr-018-019-tight-format-tiered-benchmark.md)

---

## #13 · 2026-05-10 · ADR-017: project-docs-bootstrap skill + docs-discipline rule

**Tags:** adr, harness, docs

Multi-turn discussion в этой сессии: пользователь попросил deeper synthesis на тему «как Meta orchestrator руководит командами разработчиков». Первый ответ (про harness hygiene) был отвергнут как «недостаточно информации»; второй (про project-level documentation contract…

[→ entries/0013-adr-017-project-docs-bootstrap-skill-docs-discipline-rule.md](entries/0013-adr-017-project-docs-bootstrap-skill-docs-discipline-rule.md)

---

## #12 · 2026-05-10 · Trim ADR log + retire N>=3 invariant

**Tags:** cleanup, harness

Пользовательский feedback после моего предложения ADR-17 (memory taxonomy): HARNESS-DECISIONS.md «выглядит как наиболее мешающийся артефакт, раздут контекстом и часто мешает принимать решения». Это перерасставило приоритет — сначала разобраться с самим форматом, потом думать про…

[→ entries/0012-trim-adr-log-retire-n-3-invariant.md](entries/0012-trim-adr-log-retire-n-3-invariant.md)

---

## #11 · 2026-05-10 · ADR-016: multi-agent baseline + pilot validation

**Tags:** adr, harness

Сессия 2026-05-10 расширяла harness дисциплиной multi-agent под Opus 4.7. По ходу работы возникли два диалоговых поворота, изменивших scope: 1. Запрос пользователя «information should be in active access у claude through skills + reference files, не через раздутый CLAUDE.md» —…

[→ entries/0011-adr-016-multi-agent-baseline-pilot-validation.md](entries/0011-adr-016-multi-agent-baseline-pilot-validation.md)

---

## #10 · 2026-05-10 · ADR-15 retire ADR-005 implementation warm context banned · _supersedes #5_

**Tags:** adr, harness, cleanup

Внешний агент-ревью (transcript этой сессии) выявил, что ADR-005 «берём три» (managed Memory/Dreams port-over: _manifest.yml, PreToolUse exit 2 на RO-store, SessionStart hook со списком stores) принят 2026-05-09, но через сутки ни одна из трёх капабилити не материализована…

[→ entries/archive/0010-adr-15-retire-adr-005-implementation-warm-context-banned.md](entries/archive/0010-adr-15-retire-adr-005-implementation-warm-context-banned.md)

---

## #9 · 2026-05-10 · ADR-013/014 + meta-CLAUDE.md process rules (with ADR-014 rollback)

**Tags:** adr, harness

Получен детальный аудит-разбор docs/HARNESS-DECISIONS.md от внешнего рецензента: 7 пунктов — 5 process gaps + 2 эмпирические задачи. Цель: реализовать процессные дополнения, провести эмпирическую верификацию ADR-006/007 закрытия, зафиксировать решения. В процессе допущена…

[→ entries/archive/0009-adr-013-014-meta-claude-md-process-rules-with-adr-014-rollba.md](entries/archive/0009-adr-013-014-meta-claude-md-process-rules-with-adr-014-rollba.md)

---

## #8 · 2026-05-10 · Trim harness per Opus 4.7 foundational principle (ADR-010, 011, 012)

**Tags:** adr, refactor, harness

Аудит всего harness'а под цитаты Anthropic про Opus 4.7 best practices («spawns fewer subagents by default», «calls tools less often and reasons more», «response length is calibrated to task complexity») выявил 6 hooks/ skills + 1 agent + 57 строк CLAUDE.md, которые кодируют…

[→ entries/archive/0008-trim-harness-per-opus-4-7-foundational-principle-adr-010-011.md](entries/archive/0008-trim-harness-per-opus-4-7-foundational-principle-adr-010-011.md)

---

## #7 · 2026-05-09 · ADR-009 retire sandbox baseline (workflow friction)

**Tags:** refactor, harness, security, adr

ADR-008 включил sandbox в harness baseline (commit 27723e8) ссылаясь на canonical Anthropic recommendation про «84% reduction in permission prompts». Эмпирическое использование в той же сессии — несколько часов спустя — показало конкретные friction points для harness workflow:

[→ entries/archive/0007-adr-009-retire-sandbox-baseline-workflow-friction.md](entries/archive/0007-adr-009-retire-sandbox-baseline-workflow-friction.md)

---

## #6 · 2026-05-09 · ADR-008 sandbox baseline + SessionStart context hook + effort guidance

**Tags:** feature, harness, hooks, security, adr

Прогон по 6 canonical Anthropic статьям (harness-design, effective-harnesses, sandboxing, opus-4-7-best-practices, multi-agent-systems, common-workflow-patterns) выявил три baseline practice, явно рекомендованных Anthropic, у которых в harness'е НЕ было реализации. После ADR-007…

[→ entries/archive/0006-adr-008-sandbox-baseline-sessionstart-context-hook-effort-gu.md](entries/archive/0006-adr-008-sandbox-baseline-sessionstart-context-hook-effort-gu.md)

---

## #5 · 2026-05-09 · ADR-007 retire 6 skills + 2 agents как дубликаты built-ins

**Tags:** refactor, harness, adr, cleanup

Stage 2 battle-test на FastApi-Base + критический ревью пользователя выявили системное нарушение foundational principle в v0.1 expansion коммите (76c4f37). Создавая 7 user-triggered skills и 5 custom agents, я не верифицировал built-in/bundled каталог Claude Code 2.1.x…

[→ entries/archive/0005-adr-007-retire-6-skills-2-agents-built-ins.md](entries/archive/0005-adr-007-retire-6-skills-2-agents-built-ins.md)

---

## #4 · 2026-05-09 · Mandatory onboarding interview (ADR-006) после Stage 2 pilot finding

**Tags:** bugfix, agents, harness, adr

Stage 2 battle-test на pilot'е FastApi-Base выявил harness-bug: onboarding-agent в auto-mode пропустил interview phase на mature-проекте. В выводе явно: «No interview was conducted — Auto-mode prefers action over questions». Pilot'ный CLAUDE.md создан с высоким качеством…

[→ entries/archive/0004-mandatory-onboarding-interview-adr-006-stage-2-pilot-finding.md](entries/archive/0004-mandatory-onboarding-interview-adr-006-stage-2-pilot-finding.md)

---

## #3 · 2026-05-09 · Permission whitelist + quote-aware dangerous-cmd-block

**Tags:** config, hooks, harness, dx

При попытке Stage 2 install (rsync копии mature pilot) сработал встроенный auto-mode classifier Claude Code — отдельный слой ДО проектных hooks. Логи dangerous-cmd.jsonl показали: мой dangerous-cmd-block.sh пропустил оба rsync с decision="allowed". Блокировал именно built-in…

[→ entries/archive/0003-permission-whitelist-quote-aware-dangerous-cmd-block.md](entries/archive/0003-permission-whitelist-quote-aware-dangerous-cmd-block.md)

---

## #2 · 2026-05-09 · v0.1 expansion: P0 патчи гайда, skills для slash-commands, блокирующие hooks

**Tags:** feature, harness, hooks, skills, docs

После формулировки текущего этапа harness'а в .claude/plans/radiant-jingling-frost.md (v0.1 — фундамент материализован) пользователь запросил параллельное исполнение четырёх задач: применение P0-патчей к research-гайду, сборка commands, блокирующие hooks, wiring skill-creator…

[→ entries/archive/0002-v0-1-expansion-p0-skills-slash-commands-hooks.md](entries/archive/0002-v0-1-expansion-p0-skills-slash-commands-hooks.md)

---

## #1 · 2026-05-09 · Bootstrap devlog scaffold

**Tags:** feature, devlog, harness

Harness задумывался как минимальная стартовая обвязка для новых проектов под Opus 4.7. Devlog нужен с первой сессии — без него каждая последующая сессия Claude Code читает код «без памяти команды», теряет мотивацию решений и трактует squash-мерджи как однострочные изменения.

[→ entries/archive/0001-bootstrap-devlog-scaffold.md](entries/archive/0001-bootstrap-devlog-scaffold.md)
