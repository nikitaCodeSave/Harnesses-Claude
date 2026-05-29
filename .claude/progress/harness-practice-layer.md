# Progress: harness as development-practice layer

**Quick state (2026-05-29):** Harness = **standing development-practice layer**. Все 3 столба ✅
(methodology #53, continuity #54, guardrails #55) + system-guard упрощён до DENY-only (#56).
**Бенчмарк качества text2sql v2 построен и прогнан вживую** (#57-59): 12 задач, 9 осей, реальный
Oracle+ollama. **A/B harness-vs-noharness обвязка + проба** (#60-61): n=1 показал delta −1 (шум) —
single-shot не выявляет ценность practice-слоя (подтверждает #52). Всё закоммичено на main.
**Открытый главный трек: мульти-сессийный замер** (где continuity реально задействован).

## Большая картина
Эмпирика (devlog #52): на single-shot greenfield harness = overhead (×2.6 cost, ×2 turns,
quality-tie). Значит ценность — в дельте, которой у Opus 4.8 НЕТ по умолчанию. Правило:
**harness кодирует ДЕЛЬТУ, не БАЗУ**. Три столба: methodology / continuity / guardrails.

## Сделано (читать для глубины)
- **devlog #50/#51** — консолидация стартера под Opus 4.8: ретайр `harness-setup` (→
  `~/.claude/_archived-skills/`), чистый глобальный `~/.claude/skills/claude-code-harness/`,
  re-ground 4.7→4.8 (CLAUDE.md + principles/workflow/multi-agent/builtins-inventory).
- **devlog #52** — бенчмарк text2sql ours-vs-noharness (n=1), доказал overhead-на-single-shot.
- **devlog #53** — ✅ **столб 1 (methodology)** глобально: `~/.claude/CLAUDE.md §5` (standing
  test-invariant), `~/.claude/skills/tdd/` (+ `references/agent-test-evidence.md`, T1-grounded),
  `~/.claude/hooks/test-quality-reminder.sh` (advisory Stop-гейт, asserts=0∧prints>0), wired в
  `~/.claude/settings.json`. Рычаг = oracle+behavior+run, **red-first НЕ догма**.
- memory: `project_harness_practice_layer.md`, `project_harness_starter_consolidated.md`.
- Karpathy-репо (forrestchang) проверен: обновлений нет (контент заморожен 2026-04-20), мы впереди.
- **devlog #54** — ✅ **столб 2 (continuity)** глобально: `~/.claude/hooks/session-context.sh`
  (new, SessionStart, project-agnostic: last-3 devlog + active progress, silent-degrade), wired
  в `~/.claude/settings.json`, `~/.claude/CLAUDE.md §6` (3 continuity-слоя + роли). Git НЕ в хуке
  (built-in уже даёт → дельта-чистота). Лабовый хук урезан до loop-STATE. Reproduce-test +
  mutation-test (`.claude/benchmark/audit/test-session-context-hook.sh`, 10/10, оракул кусается).
  Дизайн-решение: devlog=episodic/git-tracked, progress=in-flight, авто-память=atemporal — не дубль.

## ✅ Столб 3 — guardrails (devlog #55, сделан)
Открытие: глобальный baseline уже был — `~/.claude/hooks/system-guard.sh` (DENY/ASK/LOG). «Полная
реализация» = НЕ новый хук (теория), а hardening существующего: тест (`.claude/benchmark/audit/
test-system-guard.sh`, 29/29) + фикс реального false-positive (`-guard` в `system-guard` матчил
рекурсивный флаг) + закрытие HIGH-дыры (capital `-R`) по итогам security-reviewer subagent'а.
§7 в `~/.claude/CLAUDE.md`: project-danger кодируется реактивно (permissions.deny), не upfront.

## Доп. сделано в этой сессии (вне 3 столбов)
- **system-guard упрощён → DENY-only + sudo LOG** (#56): убраны ASK-тиры (трение), оставлен
  катастрофический пол. Тест 29/29.
- **Бенчмарк text2sql v2 MVP** (#57): 4-агентная разведка production-проекта `AI_analyst_migration`
  → design-doc + MVP (`.claude/benchmark/text2sql-v2/`: фикстура+golden+оси 1-4, тест 18/18 «good vs
  naive»). Узкий NL→SQL + golden; судим КАЧЕСТВО результата, не pass/fail. Шаг к правильному замеру.

## Бенчмарк v2 — построен полностью (#57 MVP, #58 интеграция)
3-агентная параллельная сборка (worktree, непересекающиеся файлы) + интеграция main-thread'ом:
12 задач (T1-T10 + guardrail G1/G2), 9 осей (1-4 scorer + refusal, 5-6 runner reliability/stability,
7-9 LLM-judge). Тесты: scorer 39/39, judge 19/19, runner 28/28; dry-run 12/12 gate_pass.
`.claude/benchmark/text2sql-v2/`. Остаток до живого прогона: закрыть `_shape` для wide number_map с
производными ключами (T5 delta, T6 PNL_TOTAL) + подключить реального агента через `AgentSolver`.

## Бенчмарк v2 — живой прогон выполнен (#59)
- Live-mode `_shape` закрыт (per-task shape + case-insensitive ключи + алиасы). Фикстура грузится в
  изолированную `client_product_bench` (`seed_oracle.py`) — рабочую таблицу не трогаем.
- `OllamaSolver` (реальный агент через ollama). На реальном Oracle+ollama: ReferenceSolver 12/12;
  реальный qwen3-агент **5/12** (валит доменные traps, фабрикует G1) — бенчмарк дискриминирует качество.
- Отчёт: `.claude/benchmark/reports/2026-05-29-text2sql-v2-ollama-baseline/`.

## A/B harness-vs-noharness (#60 обвязка, #61 проба) — ВЫПОЛНЕНО
- Дизайн (апрув): claude --print строит NL→SQL impl; toggle = глобальный `~/.claude` on/off
  (механизм: bare CLAUDE_CONFIG_DIR + только creds; подтверждён hooks 4 vs 0); судья v2.
- Замеры: дисперсия оракула 5/5/5 (детерминирован); live reference 12/12; baseline 5/12.
- Проба `--builds 1`: **harness 4/12, noharness 5/12, delta −1 (n=1 = шум)**. Оба arm построили
  почти идентичные структурированные+тестируемые импл — methodology-столб не дал видимой дельты
  (Opus 4.8 и так пишет чисто). Отчёт `reports/2026-05-29-ab-harness-vs-noharness-b1/`.
- Вывод: single-shot не выявляет ценность practice-слоя (как #52) → нужен мульти-сессийный замер.
- Попутно: исправлен build-контракт (ollama-backed, не stdlib-toy; #61); executor устойчив к
  недоверенному SQL агента (#1cc5d01).

## Следующая задача: мульти-сессийный замер practice-слоя (главный открытый трек)
Единственный сценарий, где continuity-столб (#54) задействован: сессия N опирается на devlog/progress
1..N-1, судить КАЧЕСТВО (v2-оракул готов). Опц.: A/B `--builds 3+` для направленной single-shot
оценки; пред-существующие дыры system-guard (`find -delete`/`truncate`/`chmod -R /`).
**Сначала предложи план, дождись апрува, потом исполняй.**

## 🏆 Достижения этого арка (devlog #50–#61, 2026-05-29)
- **Practice-слой целиком**: переосмысление harness'а (setup→practice), 3 глобальных столба
  (methodology/continuity/guardrails) — каждый mechanical hook + CLAUDE.md §5/§6/§7, evidence-grounded.
- **system-guard**: закалён (фикс false-positive + HIGH-дыра, security-reviewer) → затем упрощён до
  DENY-only по решению оператора. Тест 29/29.
- **Бенчмарк качества text2sql v2** с нуля: разведка реального проекта 4 агентами → design → MVP →
  3-агентная параллельная сборка (12 задач × 9 осей) → интеграция → **живой e2e на Oracle+ollama**.
  Тесты scorer 39 / judge 19 / runner 44. Реальный агент 5/12 (дискриминирует качество, ловит
  фабрикацию G1).
- **A/B-инфраструктура** harness-vs-noharness + честная проба (delta −1, n=1) — строгий замер на
  качественном оракуле, подтвердил central thesis (#52).
- Дисциплина: ~16 коммитов на main, devlog #54–#61, reproduce/mutation-тесты, ничего не запушено,
  рабочая БД пользователя не тронута (изолированная bench-таблица), `.scratch/`/`files.zip` не тронуты.

## Ограничения
- Blast radius: правки в global `~/.claude/` влияют на все проекты → бэкап, advisory/exit-0,
  silent-когда-нерелевантно, обратимость, сообщай явно.
- Минимализм/дельта; не реинтродуцировать `harness-setup`; CLI-only (без Anthropic API).
- Empirical over theoretical (worktree A/B / dogfood). §5 test-quality активен глобально — пиши
  тесты через поведение, запускай, не псевдо-мусор. reproduce-test для любого нового хука. Surgical.

## Параллельный трек (позже)
«Правильный» бенчмарк practice-слоя: мульти-сессийный (сессия N опирается на devlog 1..N-1) +
судить КАЧЕСТВО тестов, не pass/fail. Single-shot зануляет ценность слоя. Инфра: `.claude/benchmark/`
(Oracle `ai-analyst-oracle`, Ollama). Полный handoff-промпт — в этом файле выше + devlog #50–53.

NEXT: мульти-сессийный бенчмарк practice-слоя (3 столба готовы — нужен замер ценности; single-shot её зануляет). Предложить сценарий (сессия N ← devlog 1..N-1, судить качество), получить апрув, исполнить.
