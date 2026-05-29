# Progress: harness as development-practice layer

**Quick state (2026-05-29):** Harness переосмыслен как **standing development-practice
layer** (не bootstrap). Из 3 столбов: **methodology — ✅ сделан**, **continuity — ✅ сделан**
(devlog #54), **guardrails — следующий**. Изменения этой сессии **не закоммичены** (см. `git status`).

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

## Следующая задача: столб 3 — guardrails
Цель: per-project «чего НЕ делать» (sensitive paths/команды → DENY, what-not-to-do constraints).
В отличие от continuity/methodology (глобальные), guardrails **per-project** по природе (зависят
от стека/секретов/инфры). Открытый вопрос: сколько кодировать глобально (baseline DENY: rm -rf,
git push --force, secret-файлы) vs оставлять проектному CLAUDE.md/settings. Empirical: не вводить
по теории — проверить, что Opus 4.8 не делает нативно (он уже осторожен с деструктивом).
**Сначала предложи план, дождись апрува, потом исполняй.**

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

NEXT: столб 3 (guardrails) — предложить план (что DENY-baseline глобально vs per-project), решить дельту относительно нативной осторожности Opus 4.8, получить апрув, исполнить.
