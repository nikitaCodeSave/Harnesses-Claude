---
id: 17
date: 2026-05-10
title: "Harness self-contained: docs moved to .claude/docs/"
tags: [refactor, docs, harness, portability]
status: complete
---

# Harness self-contained: docs moved to .claude/docs/

## Контекст

Harness — это переносимый pack, который инсталлируется в произвольный target-проект (`/path/to/SomeProject/.claude/`). У target-проекта обычно собственный `docs/` (создаваемый `project-docs-bootstrap` skill: `ARCHITECTURE.md`, `CODE-MAP.md`, ADR/, RUNBOOKS/).

Прежняя структура держала harness-knowledge в корневом `docs/` рядом с операционным кодом harness'а (`.claude/`). Это путало два слоя:

- **harness-knowledge** (principles, multi-agent baseline, benchmark methodology, frozen ADR log) — должна жить вместе с pack'ом
- **project-docs** (создаются `project-docs-bootstrap` в target-проекте) — собственность проекта применения

При копировании pack'а в чужой проект корневой `docs/` либо ломал ссылки в `.claude/CLAUDE.md`, либо загрязнял проектный `docs/` мета-материалом harness'а. Failure mode в обе стороны.

## Изменения

7 файлов перемещены из `docs/` → `.claude/docs/`:

**Active layer (3 файла)** — `.claude/docs/`:
- `HARNESS-PRINCIPLES.md` → `principles.md`
- `MULTI-AGENT-BASELINE.md` → `multi-agent.md`
- `HARNESS-BENCHMARK.md` → `benchmark.md`

**Archive layer (4 файла, frozen)** — `.claude/docs/archive/`:
- `archive/DECISIONS-2026Q2.md` → `archive/decisions-2026Q2.md`
- `PRACTICES-FROM-PROJECTS.md` → `archive/practices-from-projects.md`
- `RESEARCH-AUDIT.md` → `archive/research-audit.md`
- `Harnesses_gude.md` → `archive/harnesses-guide.md` (исправлена опечатка)

Корневой `docs/` удалён (был пустым после миграции).

Operational refs обновлены в 9 файлах: `.claude/CLAUDE.md`, `.claude/rules/testing.md`, `.claude/rules/docs-discipline.md`, `.claude/skills/devlog/SKILL.md`, `.claude/skills/project-docs-bootstrap/SKILL.md`, `.claude/skills/project-docs-bootstrap/references/CONTRACT.md`, `.claude/benchmark/static-checks.sh`, `.claude/hooks/README.md`, `.claude/hooks/secret-scan.sh`, `.claude/devlog/README.md`. Также cross-refs внутри active `.claude/docs/*.md` файлов (относительные пути).

Frozen archive файлы (decisions-2026Q2.md, research-audit.md, practices-from-projects.md, harnesses-guide.md) **не модифицированы внутри** — они сохраняют исторические ссылки на старые пути (docs-discipline rule 3: frozen point-in-time snapshot). Live devlog entries 0011-0016 также не трогались — сохраняют временной контекст на момент написания.

`secret-scan.sh` allowlist почищен от legacy суффиксов (`*HARNESS-DECISIONS*|*RESEARCH-*|*PRACTICES-*`) — заменён на общий `*archive/*` plus existing `*.md`/`*docs/*` который уже покрывает все harness-doc файлы независимо от их точного именования.

## Принцип

**Harness pack самодостаточен.** Zero внешних ссылок из `.claude/` на корневой `docs/`. `.claude/docs/` хранит harness-knowledge, корневой `docs/` принадлежит target-проекту. Эти два слоя не пересекаются path'ами и не конфликтуют при инсталляции pack'а.

## Затронутые файлы

- `.claude/docs/` (new): 3 active + 4 archive файла
- `.claude/CLAUDE.md`: Reference materials secция обновлена на `.claude/docs/...` paths
- `.claude/rules/testing.md`, `.claude/rules/docs-discipline.md`: обновлены ссылки
- `.claude/skills/devlog/SKILL.md`, `.claude/skills/project-docs-bootstrap/SKILL.md`+`references/CONTRACT.md`: обновлены ссылки
- `.claude/benchmark/static-checks.sh`: check paths + display labels обновлены на новые имена
- `.claude/hooks/secret-scan.sh`: allowlist почищен
- `.claude/hooks/README.md`, `.claude/devlog/README.md`: обновлены ссылки

## Проверка

```bash
$ grep -rn "HARNESS-PRINCIPLES\|HARNESS-DECISIONS\|HARNESS-BENCHMARK\|MULTI-AGENT-BASELINE\|PRACTICES-FROM-PROJECTS\|RESEARCH-AUDIT\|Harnesses_gude" \
  .claude/CLAUDE.md .claude/rules/ .claude/hooks/ .claude/benchmark/ \
  .claude/devlog/README.md .claude/skills/ \
  .claude/docs/principles.md .claude/docs/multi-agent.md .claude/docs/benchmark.md
# (no output — all operational refs обновлены)

$ ls docs 2>&1
ls: cannot access 'docs': No such file or directory

$ bash .claude/benchmark/static-checks.sh
=== ALL AUTOMATED CHECKS PASSED (13/13) ===
```

## Related

- #16 — D-021 two-tier docs split (active vs archive) ввёл active/archive разделение в корневом `docs/`; эта запись закрывает остаток: переносит саму папку внутрь pack'а.
- Implicit ADR — этот рефактор — структурная миграция (docs-discipline rule 3 explicit разрешает изменять frozen layer только через таковые). Зафиксирован эта запись + грядущая правка principles.md если потребуется.
