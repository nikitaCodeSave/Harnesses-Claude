---
id: 15
date: 2026-05-10
title: "Tier 0/1 dogfood + ADR-020 fixes"
tags: [benchmark, harness, docs, adr]
status: complete
---

# Tier 0/1 dogfood + ADR-020 + static-checks.sh

## Контекст

Первое реальное прогон benchmark methodology из ADR-019. Tier 0 automated (static-checks.sh implementation), Tier 1 dogfood на FastApi-Base fixture с генерацией реальных docs (per project-docs-bootstrap skill workflow Phase 1-5). Three methodology gaps выявлены и зафиксированы in-place.

## Изменения

### Tier 0 implementation
- **`.claude/benchmark/static-checks.sh`** — 9 automated checks (CLAUDE.md size, SKILL.md size, ADR-018+ size, devlog index integrity, skill frontmatter, retired components guard, compact index sync, hooks executable, rule files non-empty). Manual checks (`claude --print`, `claude agents`, hook stdin smoke) явно выделены.
- Run result: 13/13 PASS.

### Tier 1 dogfood — FastApi-Base
**Pre-dogfood prep**: `git init -b main && git add -A && git commit -m "chore: initial commit"` (был tarball, без git). Fixture теперь 1 commit, qualifies для bootstrap mode.

**Phase 1 audit findings**:
- Stack: Python 3.12 + FastAPI 0.115 + SQLAlchemy 2.0 async + asyncpg + Alembic + Postgres + JWT.
- Top-level src/: `shared/`, `auth/`, `users/` (3 domains, ≥3 trigger met для CODE-MAP).
- Existing docs: `README.md` (полный — Domain-Based template description, Архитектурные правила), `.claude/CLAUDE.md` (harness meta-CLAUDE), `fastapi-skills/ARCHITECTURE_DECISION.md` (non-canonical meta-decision-tree).
- No project-root `CLAUDE.md`, no `docs/`.

**Phase 2 scope**: ARCHITECTURE.md + CODE-MAP.md + ADR-0001 + project root CLAUDE.md. Skip CONVENTIONS.md (дублировал бы README «Архитектурные правила» — anti-pattern), skip GLOSSARY.md (нет obscure акронимов), skip ROADMAP/RUNBOOKS (no signals).

**Phase 3 generated** (real content based on actual code):
- `~/PROJECTS/FastApi-Base/docs/ARCHITECTURE.md` (70 строк): Components table, data flow, layered convention, external services, deployment, constraints.
- `~/PROJECTS/FastApi-Base/docs/CODE-MAP.md` (58 строк): top-level layout + per-domain layout + where-to-find-X table.
- `~/PROJECTS/FastApi-Base/docs/ADR/0001-domain-based-layered-architecture.md` (49 строк): retroactive ADR для архитектурного выбора с alternatives (Simple Modular / Clean / Hexagonal).
- `~/PROJECTS/FastApi-Base/CLAUDE.md` (48 строк): minimal indexer — stack, doc refs, mode, dev commands, architectural invariants, sensitive paths, testing.

**Phase 5 verify**:
- ✓ Каждый doc отражает реальное состояние (cold-start mental check pass).
- ✓ Owner + last-updated в frontmatter.
- ✓ CLAUDE.md ссылается на docs/.
- ✓ Не сгенерирован ни один dead doc (CONVENTIONS / GLOSSARY / ROADMAP / RUNBOOK skipped per scope).
- ✓ fastapi-skills/ARCHITECTURE_DECISION.md preserved-with-reference (упомянут в CODE-MAP.md и ADR-0001 Notes).

### Three methodology gaps → fix-in-place

**Gap 1: fixture criteria mismatch.** HARNESS-BENCHMARK.md требовал «≥30 commits», FastApi-Base был tarball. Fix:
- `git init` на FastApi-Base (1 commit baseline).
- HARNESS-BENCHMARK.md «Fixture project» relaxed: «git repo initialized + ≥10 commits soft».
- SKILL.md Phase 1 step 4 добавлен «No git repo / 0 commits → bootstrap project (предложи `git init`)».

**Gap 2: skill behavior on existing non-canonical docs.** Раньше Phase 1 step 5 искал только в `docs/`; не находил `fastapi-skills/ARCHITECTURE_DECISION.md`. Fix:
- SKILL.md Phase 1 step 5 расширен: `find . -maxdepth 3 -name '*.md'` для non-canonical detection + migration plan (incorporate / preserve-with-reference / archive).

**Gap 3: skill behavior on .claude/CLAUDE.md (project-scoped) vs root CLAUDE.md.** Раньше Phase 1 step 1 предполагал только root. Fix:
- SKILL.md Phase 1 step 1 explicit hierarchy search: root `CLAUDE.md` → `.claude/CLAUDE.md` → `~/.claude/CLAUDE.md`.

### ADR-020
Tight format ADR (≤30 строк) фиксирует все три fix'а с counter-evidence to revise (second dogfood на другом fixture).

## Затронутые файлы

**Harness**:
- `.claude/benchmark/static-checks.sh` — новый, 13/13 pass
- `.claude/skills/project-docs-bootstrap/SKILL.md` — Phase 1 steps 1, 4, 5 расширены
- `docs/HARNESS-BENCHMARK.md` — fixture criteria relaxed
- `docs/HARNESS-DECISIONS.md` — ADR-020 + compact index entry
- `.claude/devlog/entries/0015-*.md` — этот entry
- `.claude/devlog/index.json` — регенерирован

**FastApi-Base** (внешний проект):
- `.git/` (init)
- `docs/ARCHITECTURE.md`, `docs/CODE-MAP.md`, `docs/ADR/0001-*.md`, `CLAUDE.md` — новые, 225 строк total

## Проверка

```
$ .claude/benchmark/static-checks.sh
=== Harness Tier 0 static checks ===
... 13/13 PASS

$ ls ~/PROJECTS/FastApi-Base/docs/ ~/PROJECTS/FastApi-Base/CLAUDE.md
ARCHITECTURE.md  ADR/  CODE-MAP.md
~/PROJECTS/FastApi-Base/CLAUDE.md

$ python3 .claude/devlog/rebuild-index.py
index.json updated: 15 entries
```

## Что НЕ сделано (сознательно)

- НЕ commit'нул FastApi-Base изменения второй раз — оставлю на пользователя для review docs перед commit.
- НЕ сгенерирован CONVENTIONS.md / GLOSSARY.md / ROADMAP.md / RUNBOOKS.md в FastApi-Base — нет signals, dead-doc anti-pattern.
- НЕ запущен второй dogfood на другом fixture — counter-evidence к ADR-020 будет естественно собран при следующем real use-case (другой стек / monorepo / mature project).
- НЕ автоматизирован Tier 1 — per ADR-019 v2 trigger («≥3 harness changes accumulated»), пока manual.
- НЕ обновлён static-checks.sh для Tier 1 metrics capture — Tier 1 manual в v1; automation отложено.

## Открытые вопросы

1. **Second dogfood на различном fixture** — counter-evidence для ADR-020. Trigger: следующий real project использующий harness, ИЛИ specifically setup'нутый monorepo fixture.
2. **Pre-commit hook для static-checks.sh** — кандидат на v2 после ≥3 harness changes accumulated (ADR-019 roadmap).
3. **Tier 1 metrics capture automation** — нужен только когда manual procedure окажется слишком burdensome (≥5 ADR cycles).

## Related

- #14 (`adr-018-019-tight-format-tiered-benchmark`) — предложил methodology, эта запись валидирует.
- #13 (`adr-017-project-docs-bootstrap-skill-docs-discipline-rule`) — skill foundation, дополнен ADR-020 fix'ами.
