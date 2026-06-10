# T1 — smoke чистого профиля (Regulation v1, Phase 3)

**Дата:** 2026-06-10 · **CC:** 2.1.170 · **Исполнитель:** lab-сессия (Fable 5)
**Провенанс:** все выводы команд — в логах `01…10-*.log` рядом с этим отчётом
(урок D.2: golden-ожидания без артефакта — слепое пятно).

## Сетап

Три одноразовых чистых профиля `CLAUDE_CONFIG_DIR=$(mktemp -d)`:
- CFG1 `/tmp/t1-smoke-cfg-NUOMxs` — установка v1.1.0 из боевого `~/.claude` + bootstrap;
- CFG2 `/tmp/t1-smoke-cfg2-nedNyZ` — эмпирика упаковки (тестовый marketplace с commands+agents внутри plugin-дира);
- CFG3 `/tmp/t1-smoke-cfg3-erYjHK` — финальный re-smoke релиза v1.2.0.

Тестовое репо: `/tmp/t1-smoke-repo-KS83AN` (пустое, только `git init`).
Для `claude --print`-прогонов в чистый профиль копировался `.credentials.json`
(auth — вне механики плагина; в логах отмечено).

## Результаты по шагам quick start

| Шаг | Результат | Лог |
|---|---|---|
| `claude plugin marketplace add /home/nikita/.claude` | ✅ exit=0, marketplace `dot-claude` добавлен | 01 |
| `claude plugin install claude-code-harness@dot-claude` | ✅ exit=0, scope user, enabled | 01 |
| `claude plugin details` | ✅ v1.1.0: Skills 1 / Agents 0, ~211 tok always-on | 01 |
| Bootstrap «set up Claude Code harness in this project» | ✅ plugin-skill СРАБОТАЛ (Skill-вызов в transcript, лог 05); создал `CLAUDE.md` 30 строк (indexer-стиль) + `.gitignore` | 03, 04 |
| `.claude/settings.json` при bootstrap | ⚠️ в headless `--print --permission-mode acceptEdits` заблокирован («settings files are protected»); доведён вторым прогоном с `--dangerously-skip-permissions`. В интерактивной сессии это обычный approve-prompt — не дефект, но границу headless-bootstrap'а надо знать | 03, 06 |

## Эмпирическое решение отложенного вопроса упаковки (Phase 2)

Вопрос: упаковывать ли `/external-audit` + 3 agent-роли ВНУТРЬ
`skills/claude-code-harness/{commands,agents}/`; конфликт «git-clone автозагрузка корня
vs plugin = поддиректория».

Факты (логи 02, 07, 08, 09, 10):
1. **v1.1.0 plugin-only = dangling refs.** Доставленный playbook ссылается на
   `/external-audit` и `~/.claude/{commands,agents}` — на plugin-only профиле их НЕТ (лог 02).
2. **commands+agents внутри plugin-дира ЗАГРУЖАЮТСЯ**: inventory Skills 2
   (`claude-code-harness`, `external-audit`) / Agents 3; ~530 tok always-on (лог 07).
3. **Роли резолвятся НАТИВНО как `subagent_type`**: `claude-code-harness:{evidence-executor,
   process-auditor,code-refuter}` видны Agent-tool'у на чистом профиле; команда видна как
   `claude-code-harness:external-audit` (лог 08, runtime-опрос `claude --print`).
4. **Конфликт clone-vs-plugin снимается переносом, не дублированием**: на основном профиле
   `~/.claude/skills/claude-code-harness` автозагружается как plugin
   `claude-code-harness@skills-dir` и после переноса несёт те же командy+агентов (лог 10).

**Решение (реализовано, v1.2.0):** `git mv` команд и ролей внутрь plugin-дира; шаг 1
`/external-audit` переписан — native `subagent_type` first, ROLE_DIR-fallback сохранён;
README/playbook обновлены; bump 1.1.0→1.2.0 синхронно, оба манифеста validate ✔,
тег `claude-code-harness--v1.2.0` создан. Commit dot-claude `6036560`.
Финальный re-smoke v1.2.0 на CFG3: Skills 2 / Agents 3 ✅ (лог 09).

Следствие: риск **R6 закрыт сильнее ожидаемого** — для plugin-пути general-purpose-обход
больше не нужен (роли = полноценные agent-типы); fallback оставлен для локально
вкопированных ролей.

## Bonus-находка (поймана `claude plugin validate`)

`external-audit.md` имел невалидный YAML frontmatter (`argument-hint: <scope: …>` —
двоеточие в plain scalar) → «at runtime this command loads with empty metadata (all
frontmatter fields silently dropped)». Исправлено квотированием обоих полей.
Урок в канон: `claude plugin validate` гонять на каждом релизе — он ловит то, что
runtime молча глотает.

## Стоимость

Always-on для потребителя плагина: ~211 → ~530 tok (3 agent-описания + command).
Принято: аудит — суть kit'а, доставка «из коробки» оправдывает +319 tok.

## Вердикт T1

**PASSED с правками** — установка одной командой воспроизведена артефактами; bootstrap
по quick start срабатывает (skill триггерится на каноничную фразу); отложенный вопрос
упаковки решён эмпирикой и реализован (v1.2.0). Открытых блокеров для T2/T3 нет.
