---
id: 92
date: 2026-06-11
title: "Kit v1.5.1: clean fair-copy edition"
tags: [canon, plugin, release, editorial]
status: complete
---

# Kit v1.5.1: clean fair-copy edition

## Контекст
Оператор: «идеальный чистовой вариант без заметок на полях» — файлы kit'а должны читаться
как текущее состояние, без отсылок к тому, что и когда менялось.

## Изменения (editorial, фактов не меняет)
- **native-capabilities.md переписан начисто**: удалены все четыре «Changed in …» секции;
  выжившие факты вплавлены в тематические — новая секция «Settings, permissions, resilience»
  (native permissions-hardening, fallbackModel, requiredMin/MaxVersion, `--safe-mode` +
  `disableBundledSkills`), plugins-bullet получил skills-dir auto-load / `plugin init` /
  `plugin list`. Дехронификация: «renamed workflow→ultracode», «no longer research preview»,
  «was xhigh», «New since 2.1.143», «supersedes / docs lag» → утверждения текущего состояния
  с минимальным версионным провенансом вида «(v2.1.172+)».
- harness-discipline: «survived the 4.7→4.8 transition / what changed» → безвременная
  формулировка; grounding-штампы всех файлов унифицированы: «Grounded for the Fable 5 /
  Opus 4.8 generation, Claude Code v2.1.173 (June 2026)».
- evidence-base: секция «What changed for Opus 4.8» → «Empirical grounding notes (current
  model generation)»; Fable-нота переформулирована как evidence-факт, а не отчёт о re-ground.
- SKILL.md: headline-скобка упрощена до «evidence in references/evidence-base.md».
- Сохранены сознательно: дата у цен (ultrareview «Jun 2026» — числа обязаны нести дату),
  Watch-блок про Agent SDK credit (forward-looking, не история), процедурные термины
  re-grounding/strip (это ритуалы, не заметки), примеры внутри правила о провенансе
  в audit-checklist.

## Verify
Grep-sweep по паттернам «no longer|renamed|new since|changed in|was xhigh|survived|spot
re|supersedes|moved up|re-check» — остались только легитимные процедурные вхождения.
JSON plugin/marketplace валидны, версии синхронны 1.5.1; объём kit'а 1144 строки
(SKILL.md + 7 references). Tag `claude-code-harness--v1.5.1`.
