---
id: 119
date: 2026-07-15
title: "Kit вынесен в отдельный публичный репо: source of truth + symlink-догфуд"
tags: [refactor, harness, distribution]
status: complete
---

# Kit вынесен в отдельный публичный репо: source of truth + symlink-догфуд

## Контекст
Kit `claude-code-harness` жил подкаталогом внутри приватного dot-claude (весь `~/.claude` под git). Централизованное приватное развитие уже работало (marketplace + SemVer), но для **публичного шаринга** dot-claude нельзя опубликовать целиком (личный конфиг), а история kit'а была перемешана с global-rig коммитами. Решение: вынести kit в самостоятельный публичный репозиторий как single source of truth, сохранив догфуд без разрыва.

Развилки, зафиксированные с оператором: цель = публикация для других; история = чистый старт (без переноса 30 коммитов); checkout = `~/PROJECTS/claude-code-harness`.

## Изменения
Топология «один источник + symlink» (не вторая копия):
- **Source of truth** — новый репо `github.com/nikitaCodeSave/claude-code-harness` (public, ветка `main`, checkout `~/PROJECTS/claude-code-harness`). Свой git, свой `.claude/CLAUDE.md`, свой `.claude-plugin/marketplace.json` (`source: "./"`), whitelist-`.gitignore` (пускает только shippable-слой + README/LICENSE/dev-CLAUDE).
- **Догфуд** — `~/.claude/skills/claude-code-harness` заменён на **symlink** на новый checkout. Резолвинг проверен эмпирически: fresh `claude --print "list skills"` видит `claude-code-harness` через symlink (единственное непроверенное допущение — сняли до удаления backup).
- **dot-claude** больше не хранит/раздаёт kit: `git rm -r --cached skills/claude-code-harness`, путь заигнорен как symlink, `marketplace.json` обнулён (`plugins: []`, описание указывает на новый marketplace). Закоммичено + запушено.
- Установка теперь: `/plugin marketplace add nikitaCodeSave/claude-code-harness`.

Поток развития: лаборатория `Harnesses-Claude` (R&D/провенанс) → выводы вносятся в standalone-репо (source) → symlink догфудит → push раздаёт подписчикам.

Provenance-скан перед публикацией: 17 shippable-файлов чистые (ни клиентских имён, ни `/home/`, ни путей проектов; только намеренные author name/email в манифесте). Backup старой физкопии перемещён в scratchpad (guard не дал `rm -rf` под `~/` — корректное срабатывание home-scope DENY).

## Затронутые файлы
- `~/PROJECTS/claude-code-harness/` — новый репо (22 файла: плагин + README/LICENSE/.gitignore/marketplace/dev-CLAUDE), initial commit `5b6ef0e`
- `~/.claude/skills/claude-code-harness` — теперь symlink → `~/PROJECTS/claude-code-harness`
- `~/.claude/.claude-plugin/marketplace.json` — plugins обнулён (kit переехал)
- `~/.claude/.gitignore` — `/skills/claude-code-harness` заигнорен как dev-symlink
- (dot-claude коммит `51822e8`, запушен)

## Проверка
- `claude --print "list skills"` в fresh headless-сессии → `claude-code-harness` присутствует (догфуд через symlink работает).
- `git ls-files` нового репо → ровно shippable-слой, ничего лишнего (нет settings.local/сессий/логов).
- `gh repo view` → PUBLIC, defaultBranch `main`.
- dot-claude `git status` → clean после коммита+push.

## Related
- #118 — external-audit kit v1.12.0/v1.12.2 (последнее состояние kit перед выносом)
