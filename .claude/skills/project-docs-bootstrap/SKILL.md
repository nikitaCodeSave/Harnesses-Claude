---
name: project-docs-bootstrap
description: "Bootstrap canonical Claude-friendly project documentation (docs/ARCHITECTURE.md, docs/CODE-MAP.md, docs/GLOSSARY.md, docs/CONVENTIONS.md, docs/ADR/, docs/RUNBOOKS/) tailored to actual project state. Use this skill whenever the developer mentions 'настрой документацию проекта', 'documentation contract', 'нужен ARCHITECTURE.md / CODE-MAP.md', needs project navigation files, asks how to organize the docs/ folder, has an empty or minimal docs/ in a non-trivial codebase, has just run /init and needs structure beyond CLAUDE.md, or onboards a team and wants Claude-friendly cold-start docs. Reads code first, scopes plan with developer, writes real content — never boilerplate."
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(ls:*), Bash(tree:*), Bash(git log:*), Bash(git diff:*), Bash(git status:*), Bash(find:*), Bash(wc:*), Bash(grep:*)
---

# Навык: bootstrap проектной документации (Claude-friendly layout)

Устанавливает canonical layout документации в проекте: `docs/ARCHITECTURE.md`, `docs/CODE-MAP.md`, `docs/GLOSSARY.md`, `docs/CONVENTIONS.md`, `docs/ADR/`, `docs/RUNBOOKS/`. Layout оптимизирован под cold-start AI-агента — каждая новая сессия Claude должна за <60 секунд понять проект из docs (без grep'а по всему репо).

Полный per-doc charter и skeletons — в `references/CONTRACT.md` (on-demand reference, читается в Phase 3, не auto-loaded). Дисциплина поддержки — `.claude/rules/docs-discipline.md` (always-loaded invariant).

## Когда использовать

- После `/init` в проекте без `docs/` или с минимальным README.
- Когда разработчик просит «настрой документацию», «documentation contract», «нужен ARCHITECTURE.md».
- Когда cold-start audit обнаружил doc gap: код богатый, docs скудные.
- Когда команда вырастает >1 разработчика и появляется coordination cost.

**НЕ** использовать:
- Для проектов с актуальной `docs/` — это не migration tool.
- Для генерации boilerplate без чтения кода (создаёт legacy быстрее, чем код).
- Как замену проектному CLAUDE.md (CLAUDE.md → meta entry, остальное → `docs/`).

## Принципы (жёсткие)

1. **Read-before-write**: каждый doc отражает реальное состояние, не gen-template.
2. **Scope first, generate after**: подтверди с разработчиком, что именно создаём.
3. **Минимально адекватно**: 1 страница реального содержимого > 10 страниц шаблона.
4. **Owner + last-updated** в frontmatter каждого doc'а.
5. **Append-only history**: ADR не редактируются (superseded), runbook ведёт last-tested-on.
6. **CLAUDE.md как indexer**, не content store: CLAUDE.md ссылается, `docs/` хранят.

## Алгоритм

### Phase 1: Audit (read-only)

1. Read CLAUDE.md в иерархии (порядок поиска): root `CLAUDE.md` → `.claude/CLAUDE.md` (project-scoped) → `~/.claude/CLAUDE.md` (user-level fallback). Read `README.md`. Если ни один CLAUDE.md не найден — отметь cold-start scenario.
2. `ls -la` корня + `tree -L 2 -I 'node_modules|.git|.venv|__pycache__|dist|build'`.
3. Detect стек:
   - Python: `pyproject.toml`, `setup.py`, `requirements*.txt`
   - JS/TS: `package.json` (поля `dependencies`, `scripts`)
   - Go: `go.mod`
   - Rust: `Cargo.toml`
   - Multi-stack: проверь все, отметь paths-scoping candidates (см. `references/CONTRACT.md` §6).
4. Detect mode: `git log --oneline 2>/dev/null | wc -l` + `git log --oneline --since="3 months ago" 2>/dev/null | wc -l`.
   - No git repo / 0 commits → bootstrap project (предложи `git init` если applicable; докум-ция не блокируется).
   - <30 commits total → new project (lighter docs).
   - >100 commits + active recent → mature (retroactive ADR для ключевых решений).
5. Map существующие docs (canonical и non-canonical):
   - Canonical: `find docs -name '*.md' 2>/dev/null` + `ls AGENTS.md CONTRIBUTING.md CHANGELOG.md 2>/dev/null`.
   - Non-canonical: `find . -maxdepth 3 -name '*.md' -not -path './.git/*' -not -path './node_modules/*' -not -path './.venv/*' 2>/dev/null` — отметь docs вне `docs/` (например `<module>/ARCHITECTURE_DECISION.md`, `notes.md`). Для каждого — propose migration plan: incorporate в canonical doc / preserve as-is с reference / archive.
6. Identify domain hints для GLOSSARY: grep по коду на акронимы:
   - `grep -rE '\b[A-Z]{2,5}\b' --include='*.py' src/ | head -20` (Python)
   - `grep -rE '\b[A-Z]{2,5}\b' --include='*.ts' src/ | head -20` (TS)

### Phase 2: Scope proposal

Сформируй таблицу с разработчиком:

| Doc | Trigger met? | Создавать сейчас? |
|---|---|---|
| `docs/ARCHITECTURE.md` | ≥2 компонента / external service | yes/no |
| `docs/CODE-MAP.md` | ≥3 top-level dirs в `src/` или корне | yes/no |
| `docs/GLOSSARY.md` | domain-термины найдены | yes если найдены |
| `docs/CONVENTIONS.md` | команда ≥2 dev'ов или divergent patterns в коде | yes если есть |
| `docs/ROADMAP.md` | active initiatives с дедлайнами | yes если есть |
| `docs/ADR/0001-*.md` | retroactive первое ключевое решение | предложить |
| `docs/RUNBOOKS/` | операционная procedure run ≥3 раз | по запросу |
| `.github/pull_request_template.md` doc-check | команда ≥2 dev'ов | yes |

**Подтверди scope с разработчиком до Write**.

### Phase 3: Generate (per approval)

Для каждого approved doc:
1. Read relevant code (не угадывай). Для ARCHITECTURE — entry points + external services. Для CODE-MAP — `tree -L 2`. Для GLOSSARY — найденные акронимы + их usage context.
2. Draft реальное содержимое (не template). Каждая секция skeleton'а из `references/CONTRACT.md` заполняется фактами проекта или **удаляется**, если не применима.
3. Frontmatter:
   ```yaml
   ---
   owner: "@<github-handle>"
   last-updated: <YYYY-MM-DD>
   status: draft | active | superseded
   ---
   ```
4. Save в `docs/<file>.md`.

Skeleton'ы (минимальная структура секций) — в `references/CONTRACT.md`.

### Phase 4: Lock-in discipline

1. В проектный `CLAUDE.md` (root проекта, не harness'а) добавить блок ссылок на созданные docs + reference на `.claude/rules/docs-discipline.md` (harness invariant). Skeleton — `references/CONTRACT.md` §1.
2. Если команда ≥2 dev'ов — propose `.github/pull_request_template.md` с doc-check checklist. Template — `references/CONTRACT.md` §4.
3. Опционально: предложить разработчику quarterly cold-start audit ritual (открыть Claude в новой сессии, проверить понятен ли проект из docs только) для отлова doc drift.

### Phase 5: Verification

- [ ] Каждый созданный doc отражает реальное состояние (cold-start mental check: «понял бы проект новый контрибьютор?»).
- [ ] У каждого doc есть `owner` + `last-updated` в frontmatter.
- [ ] Проектный `CLAUDE.md` ссылается на новые docs.
- [ ] PR template обновлён (если applicable).
- [ ] Devlog entry создан (через skill `devlog`).

## Anti-patterns

- ❌ Генерировать docs без чтения кода (boilerplate = legacy с первой минуты).
- ❌ Создавать dead docs — пустой `docs/ADR/` без первого ADR, `GLOSSARY.md` без domain-терминов в коде, `ROADMAP.md` без active initiatives, `RUNBOOKS` для procedure run <3 раз.
- ❌ Лить generic best-practices в `CONVENTIONS.md` («мы следуем PEP 8» — useless; пиши только divergences).
- ❌ Дублировать содержимое в `CLAUDE.md` (CLAUDE.md ссылается, `docs/` хранят — см. `docs-discipline.md` rule 2).
- ❌ Заполнять frontmatter `owner: TBD` (если не знаешь — спроси разработчика).

## Связь с другими артефактами

- `.claude/rules/docs-discipline.md` — always-loaded invariant: doc-with-code, append-only history, owner-of-record, glossary first-use, cold-start test. Этот skill = bootstrap (одноразовая операция); rule = ongoing discipline.
- `references/CONTRACT.md` — full per-doc charter с skeletons. Skill читает on-demand при Phase 3 generate (не auto-loaded в системный prompt).
- Skill `devlog` — после bootstrap создай entry с tag `docs`.
- `docs/HARNESS-DECISIONS.md` ADR-017 — обоснование добавления этого skill в harness.
