---
id: 68
date: 2026-06-01
title: "claude-code-harness skill de-versioned"
tags: [harness, principle, coherence, skills]
status: complete
---

# claude-code-harness skill de-versioned

## Контекст
Тот же model-agnostic триаж (#66/#67, [[feedback_model_agnostic_skills]]), теперь по
**глобальному канону** `~/.claude/skills/claude-code-harness/` — он едет в другие проекты,
поэтому version-привязки тут аукаются шире всего.

## De-versioned (behavioral → «a capable model», grounding-провенанс сохранён)
- `SKILL.md`: эпиграф-foundational-principle «Under Opus 4.8…» → «Under a capable model…»
  (+пометка «model-agnostic — don't re-pin; grounded on Opus 4.8»); description scope
  «Opus 4.8-specific» → «Opus-class-specific» (CC-2.x scope и provider-neutral-исключение целы).
- `harness-discipline.md`: «Opus 4.8 already does X» / «Opus 4.8 does both natively» → «a capable model…».
- `audit-checklist.md` §5: «Opus 4.8 picks a sane stack» / «4.8 tool triggering» / «4.8 thinking adaptive» → model-agnostic.
- `bootstrap-checklist.md`: «Opus 4.8 reads this itself» → «a capable model…»; fresh-context Evaluator
  row «adds little under Opus 4.8» → «under a capable model».

## Усилено (главное системное улучшение)
`audit-checklist.md` §1 переписан в **operational triage rule**: «pin specific model version in
*behavioral* prose → de-version; provenance/config/historical/citation/verbatim → keep» (с примерами).
Теперь любой будущий аудит harness'а применяет ту же дисциплину и **не срежет провенанс** заодно с
привязками. Это переносит правило из памяти оператора в сам отгружаемый канон.

## Намеренно сохранено (provenance/config/historical — НЕ behavioral)
- grounded-for-штампы (`Grounded for Opus 4.8 / CC v2.1.154+`), evidence-base verification-дата,
  «What changed for Opus 4.8» re-grounding note, citation-строка «What's new in Opus 4.8».
- `native-capabilities.md` — целиком dated inventory («as of Opus 4.8»); config-факты effort-tier
  (default high, 4.7 был xhigh), changelog «Changed since 2.1.143 / Opus 4.7».
- harness-discipline «survived the 4.7→4.8 transition» (историческое).

## Затронутые файлы
- `~/.claude/skills/claude-code-harness/{SKILL.md, references/harness-discipline.md,
  references/audit-checklist.md, references/bootstrap-checklist.md}` (вне git-репо)

## Related
- #66 (testing rules + tdd), #67 (lab foundational principle) — этот закрывает отгружаемый канон.
- [[feedback_model_agnostic_skills]] (operational triage rule теперь зашит и в audit-checklist).
