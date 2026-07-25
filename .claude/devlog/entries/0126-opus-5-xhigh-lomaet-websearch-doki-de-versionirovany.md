---
id: 126
date: 2026-07-25
title: "Opus 5: xhigh ломает WebSearch, доки де-версионированы"
tags: [config, docs, harness]
status: complete
---

# Opus 5: xhigh ломает WebSearch, доки де-версионированы

## Контекст
Вышел Claude Opus 5 (CC 2.1.219, дефолтная Opus-модель), и глобальная настройка `effortLevel: xhigh` начала молча ломать WebSearch: под-запрос инструмента идёт с отключённым thinking, а Opus 5 принимает `thinking: disabled` только при effort ≤ `high` — иначе HTTP 400. Инструмент отказывает, сессия выглядит рабочей.

Вторая половина задачи — хронический дрейф: пин версий CC и поколения моделей растёкся по 12+ живым докам, хотя правило «behavioral binding → de-version; provenance → keep» записано в ките с самого начала. Третий цикл подряд (4.7→4.8→5) переезд превращался в ручную вычитку.

## Изменения

**1. Конфиг (`~/.claude/settings.json`).** `effortLevel: "xhigh"` и мёртвый ключ `"effort": "auto"` удалены, вместо них `env.CLAUDE_CODE_EFFORT_LEVEL: "auto"`.

Ключа `effort` в settings-схеме **не существует** — он лежал в файле и не делал ничего. Валидны только `effortLevel` (enum `low|medium|high|xhigh`; `max`/`ultracode` — session-only) и env-переменная `CLAUDE_CODE_EFFORT_LEVEL`, которая единственная принимает `auto` и **перебивает** `effortLevel`. Выбран `auto` (= дефолт текущей модели), а не хардкод `high`: конфиг перестаёт пиниться к поколению модели — то же соображение, что и в п. 2.

**2. Де-версионирование живого слоя; инвариант «один версионированный файл».** Версионный пин легален ровно в одном месте — `native-capabilities.md` (кит); остальные живые доки пишутся version-free и ссылаются на него. Провенанс не тронут: датированные grounding-стампы, «4.7-era eval, не перемерено», замеры стоимости, «since vX» в описании фич — утверждения о прошлом, они не протухают. Остаточный грep по живому слою даёт 21 упоминание, все просмотрены поштучно и все — провенанс.

Заодно переписана рекомендация по effort в `workflow.md`: было «не понижай на `medium` без причины», стало «свипай в обе стороны, понижение оправдывается замером» — по first-party guidance для Opus 5 (`low`/`medium` сильнее, чем в прежних поколениях).

**3. Дельта для плагина вынесена в отдельную сессию.** Правки кита (`native-capabilities.md` под 2.1.220/Opus 5 + детектор дрейфа в `audit-checklist.md`) в этой сессии **не применялись**: `~/.claude/skills/claude-code-harness` — симлинк в публичный репо `claude-code-harness`, у которого свой релизный цикл (SemVer + CHANGELOG + собственный devlog). Черновые правки откатаны, содержание передано хендофф-промптом.

## Найдено при сверке changelog (в плагин, не сюда)

- **`context: fork` скиллы с 2.1.218 фоновые по умолчанию** (`background: false` — opt-out). Самое существенное из дельты: форк-скилл, результат которого нужен текущему ходу, теперь обязан явно отключать фон, иначе ход продолжится без результата. Совпадает с уроком ADR-006/007 (`AskUserQuestion` несовместим с `context: fork`, потому что форк работает в background-режиме) — с 2.1.218 это стало дефолтом, а не краевым случаем. У нас живых форк-скиллов нет; затронут шаблон «project-knowledge skill» (план WU-6) и советы кита.
- Вложенность субагентов: кит утверждает «до 5 уровней» — **неверно**, дефолт 3 (2.1.219; в 2.1.217 вложенность была выключена).
- `/fork` (2.1.212) теперь копирует сессию в фоновую, а in-session форк называется `/subtask`.
- Капы фан-аута: 20 конкурентных субагентов, 200 спавнов/сессию, 200 WebSearch/сессию; dynamic workflow size по умолчанию medium (<15 агентов) + ключ `workflowSizeGuideline`.
- `/code-review`, `/verify`, `/deep-research` — invoke-only: с 2.1.215/218 модель не запускает их сама.
- Хук `DirectoryAdded`; sandbox-ключи `sandbox.network.strictAllowlist` / `sandbox.filesystem.disabled`; auto-mode классификатор забрал себе dangerous-`rm`/background-`&`/plan-mode-Bash (2.1.218); Bash-permission анализатор починил не-ASCII границы слов (2.1.216).

**Открытый долг:** два утверждения де-версионированы, но **не перемерены** на Opus 5 — «single-agent дефолт для most coding» (Anthropic пишет, что Opus 5 делегирует охотнее предшественника) и effort-рекомендация. Первое помечено в тексте как неперемеренное; второе переписано по first-party guidance.

## Затронутые файлы
- `~/.claude/settings.json` — effort-конфиг (вне репо, вне коммита)
- `.claude/CLAUDE.md` — де-версионирование + инвариант «один версионированный файл»
- `.claude/docs/{workflow,multi-agent,principles,harness-architecture,benchmark,workflow-cloud-offload,external-sources}.md` — де-версионирование
- `.claude/rules/docs-discipline.md` — де-версионирование
- `WORKFLOW.md` — шапка и футер version-free

## Проверка
Оракул активного effort — `$CLAUDE_EFFORT` (read-only, выставляется в Bash-подпроцессах):

```bash
claude --print --model opus 'Run bash: echo "EFFORT=$CLAUDE_EFFORT"'
```

| Конфиг | `$CLAUDE_EFFORT` | WebSearch |
|---|---|---|
| было (`effortLevel: xhigh`) | `xhigh` | 400 |
| `--effort high` | `high` | ok |
| `CLAUDE_CODE_EFFORT_LEVEL=auto` | `high` | ok |
| после правки, глобально | `high` | ok |

`auto` резолвится в `high` на Opus 5, Opus 4.8 и Sonnet 5 (проверено 2026-07-25 на 2.1.220).

**Радиус поражения уже, чем кажется:** на `xhigh` отказывает только WebSearch — WebFetch, Bash `curl`/`wget` и MCP-инструменты работают (проверено там же). Теряется веб-*discovery* (запрос → выдача), а не доступ в сеть; из наших поверхностей на этом же завязан `/deep-research`.

Watch-item: после апдейтов CC гонять `claude --print --effort xhigh --model opus 'WebSearch: test'` — проход без 400 означает, что кламп починили и `xhigh` снова пригоден как дефолт.

## Related
- #123 — не-ASCII в system-guard; CC 2.1.216 независимо починил разбор не-ASCII границ слов в Bash-permission-анализаторе (корроборация урока)
- #125 — правки `workflow.md` / `WORKFLOW.md` из той работы были незакоммичены на старте этой сессии и попали в тот же коммит
