---
id: 120
date: 2026-07-15
title: "Плагин актуализирован под standalone-топологию + стандарты Anthropic (v1.13.0)"
tags: [refactor, harness, distribution, docs]
status: complete
---

# Плагин актуализирован под standalone-топологию + стандарты Anthropic (v1.13.0)

## Контекст
После выноса kit'а в отдельный публичный репо (#119) его внутренний нарратив остался dot-claude-центричным («канон = ~/.claude», доставка через git-clone dot-claude, release-скрипт в `~/.claude/scripts/`), а манифесты не были сверены с first-party стандартами плагинов. Оператор поставил цель: актуализировать под новую топологию и привести максимально к рекомендациям Anthropic, приняв документацию как источник правды (исторические условности вторичны).

## Изменения
Стандарты собраны из first-party доков (`plugins`, `plugins-reference`, `skills`, `plugin-marketplaces`, skill best-practices) отдельным subagent'ом. Ключевой арбитр соответствия — официальный `claude plugin validate --strict` (passed на всех итерациях).

**Структура НЕ реструктурирована.** Валидатор принимает root-`SKILL.md` (single-skill shortcut) и `commands/` (legacy, «no forced migration»). Multi-skill layout не требуется — совпадает с simplicity-принципом kit'а. Пользовательская гипотеза «SKILL.md в корне нарушает формат» проверена и опровергнута докой.

**Манифесты под стандарт:**
- `plugin.json`: корректный `$schema` (json.schemastore.org), `keywords[]` (array — строка была бы hard error), `homepage`; `version` — единственный источник истины.
- `marketplace.json`: убран `version` из plugin-entry (дока: не дублировать, plugin.json silently wins → desync невозможен by design; ровно тот desync ловил внешний аудит #118).

**Нарратив под новую топологию** (канон = репо плагина `nikitaCodeSave/claude-code-harness`, не `~/.claude`):
- `operator-playbook.md` — карта слоёв, доставка (плагин через `/plugin marketplace add` vs baseline через Bootstrap — едут раздельно), «канон» = репо плагина, commit туда.
- `harness-evolution.md` — канон = репо плагина; baseline §1–8 эволюционирует отдельно в operator-global.
- `SKILL.md` — release mechanics: `scripts/release.sh` (в репо) вместо `~/.claude/scripts/kit-release.sh`.
- `external-audit.md` — `~/.claude/skills/` reframed как @skills-dir dev-путь, не «дефолт-clone».

**release-скрипт** перенесён в репо (`scripts/release.sh`), был привязан к dot-claude (`cd $HOME/.claude`). Синк marketplace-версии убран (version теперь один); добавлен drift-guard. `.gitignore` расширен на `scripts/` (иначе скрипт не трекался — поймано на staging).

## Затронутые файлы
- `~/PROJECTS/claude-code-harness/.claude-plugin/plugin.json` — $schema/keywords/homepage; version 1.13.0
- `~/PROJECTS/claude-code-harness/.claude-plugin/marketplace.json` — version убран из entry, +keywords
- `SKILL.md`, `references/operator-playbook.md`, `references/harness-evolution.md`, `commands/external-audit.md` — топология-нарратив
- `scripts/release.sh` (новый), `.gitignore` (+scripts/)
- Релиз: commit `bee7638`, tag `v1.13.0`, запушен

## Проверка
- `claude plugin validate . --strict` → ✔ passed (после правок).
- Догфуд через symlink (fresh `claude --print`) → skill `claude-code-harness` + namespaced агенты (`:code-refuter/:evidence-executor/:process-auditor`) + `:external-audit` видны.
- JSON манифестов валиден; `version` только в plugin.json (1.13.0), в marketplace-entry отсутствует.
- `bash -n scripts/release.sh` OK; references-ссылки из SKILL.md целы; остаточных `dot-claude`/`kit-release.sh` упоминаний нет.

## Related
- #119 — вынос kit в отдельный публичный репо (топология, на которую опирается эта актуализация)
- #118 — внешний аудит, ловивший manifest desync (устранён by design через single-source version)
