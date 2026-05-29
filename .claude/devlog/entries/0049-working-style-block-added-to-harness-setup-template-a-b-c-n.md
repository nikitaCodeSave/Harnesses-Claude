---
id: 49
date: 2026-05-18
title: "Working style block added to harness-setup template (A/B/C N=3×3)"
tags: [adr, harness, experiment]
status: complete
---

# Working style block added to harness-setup template (A/B/C N=3×3)

## Контекст

Оператор сообщил, что `/harness-setup` (skill `claude-code-harness`) генерирует target-`CLAUDE.md` без behavioral guidance — нет «думай прежде чем кодить / минимум кода / surgical changes / verifiable goals», которые Карпати [сформулировал в forrestchang/andrej-karpathy-skills](https://github.com/forrestchang/andrej-karpathy-skills). Первая реакция (после fetch'а пакета) была dismiss: «3 из 4 принципов уже в Opus 4.7 system prompt». Это был **теоретический** аргумент против community signal — против установки `[[feedback_grow_with_community]]`. Оператор справедливо потребовал empirical comparison через worktree-параллельные runs.

## Изменения

Provel empirical N=3×3 A/B/C experiment, по результатам добавил компактный 12-строчный `## Working style` блок в Phase 2 шаблон target-`CLAUDE.md` в `bootstrap-checklist.md` Phase 2.

### Experiment design

- **Fixture**: `/tmp/karpathy-exp/baseline/` — Python мини-проект с **ambiguous bug**: `slice_range(items, start, end)` возвращает `items[start:end]` с docstring «end is exclusive», но тесты ожидают inclusive end. Плюс distractor functions `_normalize_index`/`chunk` (unused) — provoke surgical-vs-cleanup choice.
- **3 variants of CLAUDE.md** (всё остальное идентично):
  - **V0** (32 строки): baseline шаблон без Working style.
  - **VA** (39 строк): V0 + мой 12-строчный subset (4 bullet: think first / simplicity first / surgical changes / verifiable goals).
  - **VB** (94 строки): V0 + полный Karpathy 60-строчный блок с подзаголовками.
- **9 runs**: 3 variants × N=3, каждый — `claude --print --model claude-opus-4-7 --output-format stream-json --permission-mode bypassPermissions --no-session-persistence`, prompt `"Fix the widget. The tests in tests/test_widget.py are failing."`, timeout 900s.
- **Judge**: general-purpose Agent в fresh context, 7-question rubric (Q1 surfaced contradiction, Q2 asked clarifying, Q3 test-first, Q4 surgical only, Q5 no overengineering, Q6 tests pass, Q7 subjective 0-5).

### Results (per-variant aggregate)

| Variant | Q1 surfaced | Q2 asked | Q3 test-first | Q4 surgical | Q5 no over | Q6 pass | avg_Q7 |
|---|---|---|---|---|---|---|---|
| V0 | 3/3 | 0/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3.00 |
| VA | 3/3 | 0/3 | 1/3 | 3/3 | 3/3 | 3/3 | 3.67 |
| VB | 3/3 | 1/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3.67 |

### Interpretation

- **Q1/Q4/Q5/Q6 saturated** — Opus 4.7 нативно surface'ит test-vs-source contradiction, держит surgical scope, не overengineers, и финиширует с зелёными тестами **без** behavioral блока. Это **частично подтверждает** мой первоначальный «уже в system prompt» аргумент.
- **Differentiator на одиночных events**: VA-r2 — единственный run с pytest-before-edit (Q3=1); VB-r2 — единственный run, задавший explicit clarifying question про dead code (`«Удалить?»`, Q2=1).
- **avg_Q7 lift**: VA и VB дают одинаковый +0.67 над V0 на subjective quality. Behavioral блок реально полезен, но **VA = VB на качестве** — full Karpathy не дал измеримого преимущества над компактным subset.
- **Confidence: low** (N=3 small, одиночные events, плюс confound — 9 параллельных runs делили общий Python venv через `pip install -e .`, что несколько моделей корректно diagnose'или mid-run).

### Decision

**VA wins on parsimony**: equivalent value, 12 строк вместо 60. Принцип «минимум обвязки» (foundational в `.claude/CLAUDE.md`) разрешает tie в пользу меньшего.

## Затронутые файлы

- `.claude/skills/claude-code-harness/references/bootstrap-checklist.md` — добавлен `## Working style` блок (12 строк, 4 bullet) в Phase 2 шаблон target-`CLAUDE.md`; добавлены 2 anti-pattern строки про «не удалять Working style» и «не раздувать до полного Karpathy»
- `/tmp/karpathy-exp/` — experiment artefacts (fixture, 9 run dirs, results.json, aggregate.json, judge-input.md) — preserved for forensics
- memory: `feedback_no_external_tools_when_inline_suffices` ← добавляется новая `feedback_empirical_over_theoretical_dismiss` (см. ниже)

## Проверка

```bash
# Sanity-check applied edit
grep -A 6 'Working style' .claude/skills/claude-code-harness/references/bootstrap-checklist.md

# Experiment artefacts preserved
ls /tmp/karpathy-exp/
cat /tmp/karpathy-exp/aggregate.json
```

Полный judge output — см. transcript главной сессии 2026-05-18.

## Related

- #43 — devlog (harness-setup team-ready, 3 iterations)
- Memory: `[[reference_karpathy_skills_pack]]` (отрицательная оценка пакета — REVISED, см. ниже), `[[feedback_grow_with_community]]`, `[[feedback_native_capabilities_take_precedence]]`
- External: [forrestchang/andrej-karpathy-skills](https://github.com/forrestchang/andrej-karpathy-skills), [Karpathy's original post on LLM coding pitfalls](https://x.com/karpathy/status/2015883857489522876)

## Lessons (для future me)

1. **Эмпирика > теоретический dismiss community signal.** Я dismiss'ил pack потому что «дублирует system prompt», не запуская test. Запустив — нашёл measurable lift на quality avg. Memory `[[reference_karpathy_skills_pack]]` нужно обновить: pack **не импортируется целиком**, но его 4-принципный subset **импортирован компактно** (12 строк, не 60).
2. **Saturation = ваше system prompt уже работает.** Если Q1/Q4/Q5/Q6 saturated через все variants — добавление guidance уже covered нативно. Investment в behavioral блоки имеет diminishing returns под Opus 4.7.
3. **Shared-venv confound в parallel runs.** При следующем подобном experiment'е — выделять venv per-run или использовать `PYTHONPATH=src` чтобы не наступать на чужие `pip install -e .`. VA-r3 сам обошёл это — повод записать как memory.
4. **N=3 — sanity check, не результат.** Этот experiment — directional signal. Для production-grade decisions нужно N=10+ с randomized order, чистый venv, варьируемые fixtures.
