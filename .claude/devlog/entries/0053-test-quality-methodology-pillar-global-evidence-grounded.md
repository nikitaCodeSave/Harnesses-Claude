---
id: 53
date: 2026-05-29
title: "Test-quality methodology pillar (global, evidence-grounded)"
tags: [feature, harness, adr]
status: complete
---

# Test-quality methodology pillar (global, evidence-grounded)

## Контекст
Оператор сформулировал недостающее звено: harness ценен как **standing development-practice
layer** (заточить Claude под разработку), а не как разовый bootstrap; и не хватало надёжного
методологического слоя (приходилось переруливать BDD/TDD в каждом проекте, чтобы не было
псевдо-тестов). Реализуем первый столб — **методологию** — на доказательной базе, а не на догме.

База: research-workflow `wnq3iqbgh` (20 агентов, 750k токенов, 13/15 load-bearing claims
verified SUPPORTED против первичных источников). Ключевой вывод: **рычаг — runnable oracle +
assert поведения + запусти-и-итерируй, а НЕ red-first ordering** (форсирование процедурного TDD
может увеличивать регрессии на слабых моделях; test-first не коррелирует с успехом). Псевдо-тесты
измерены: агенты пишут print-пробы вместо ассертов ~5–7×, reward-hack'ают тесты ~50% на трудных
задачах. Test-first полезен узко: commit failing tests = anti-tamper checkpoint.

## Изменения (всё в ГЛОБАЛЬНОМ слое — это практика для всех проектов)
1. **Reference-док** `~/.claude/skills/tdd/references/agent-test-evidence.md` — T1-grounded
   evidence (lever vs ordering, pseudo-tests, verify-loop, separate evaluator, 4.8-specifics,
   источники с tier).
2. **`~/.claude/skills/tdd/SKILL.md`** — добавлена секция «the lever is the oracle, not the
   ordering» (red-first опционален, commit-before-impl, run-and-iterate, anti-pseudo); ядро
   скилла (behavior>implementation, vertical slices) сохранено (MIT-upstream, surgical).
3. **`~/.claude/CLAUDE.md` §5** — компактный standing-инвариант (assert поведения через
   публичный интерфейс; назвать сценарии; запусти+итерируй; «tests pass»≠done, verify e2e;
   commit failing tests до импла; mock только внешнюю границу; red-green — дефолт, не догма).
4. **`~/.claude/hooks/test-quality-reminder.sh`** — advisory Stop-хук (exit 0 always): молчит
   если тест-файлы не менялись; иначе чек-лист + высокоточный pseudo-test флаг (asserts=0 ∧
   prints>0). Language-agnostic, без hard-deps, видит untracked-файлы.
5. **`~/.claude/settings.json`** — Stop-хук подключён (бэкап сделан, JSON провалидирован).

## Дизайн-решение (ADR-суть)
Кодируем **дельту** (то, чего у Opus нет по умолчанию: твоя методология + continuity), не **базу**.
Методология = **рычаги** (oracle/behavior/run/anti-tamper), НЕ ordering-догма — это противоречило бы
доказательствам. Доставка тремя механизмами: standing-инструкция (CLAUDE.md §5) + on-demand глубина
(tdd-скилл) + механический advisory-гейт (хук) — по принципу «mechanical invariants > prompt advice»,
но lightweight (4.8 сам флагует огрехи ~4× чаще → тяжёлая обвязка не нужна).

## Проверка
- Хук reproduce-test (dogfood §5): 3 кейса — silent без тест-изменений; reminder+⚠pseudo-flag на
  print-без-assert тесте; reminder без флага на assert-тесте; exit 0, без ошибок. Поймал и починил
  2 бага по ходу (git diff не видел untracked; `grep -c||echo 0` давал «0\n0»).
- `settings.json` → valid JSON, Stop-хук зарегистрирован.

## Затронутые файлы
- `~/.claude/skills/tdd/references/agent-test-evidence.md` (new)
- `~/.claude/skills/tdd/SKILL.md`, `~/.claude/CLAUDE.md`, `~/.claude/settings.json`
- `~/.claude/hooks/test-quality-reminder.sh` (new)

## Related
- #52 — бенчмарк (harness=overhead на low-exploration single-shot); подтвердил, что ценность
  harness'а в continuity/методологии, не в bootstrap.
- #50/#51 — консолидация стартера + re-ground 4.8.
- Next pillars: **continuity** (devlog+progress+SessionStart-surfacing как глобальный дефолт),
  **guardrails** (per-project settings). + правильный мульти-сессийный бенчмарк, чтобы измерить
  ценность этого слоя (single-shot её зануляет).
