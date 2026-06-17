---
id: 109
date: 2026-06-17
title: "Staleness-guard ADR — content-discipline vs маркеры, kit v1.9.2"
tags: [adr, harness]
status: complete
supersedes: 108
---

# Staleness-guard ADR — content-discipline vs маркеры (kit v1.9.2)

## Контекст
Инцидент #108 (устаревший #49947-caveat в shipped-baseline нуклеировал редундантный skill в
dialog_analyzer) поднял вопрос: какими механизмами фабрика должна защищаться от staleness
отгружаемых claim'ов. Три предложения (A: durable/volatile split; B: inline expiry-маркеры +
grep-sweep; C: downstream-impact поле в devlog) + идея оператора использовать YAML-frontmatter
Anthropic-стандарта для структурированных provenance-меток. Решение принято через **4 параллельные
fresh-context grill-сессии** (§8: judge≠author, default-to-refute), каждая с веб-источниками.

## Изменения (Decision)
Сходящийся мета-вывод всех 4 критиков: **рычаг — content-discipline (не отгружать
скоропортящийся claim), а не метка/поле/таксономия. Любой «пометь-и-надейся» механизм инертен
без runner'а-потребителя.** Решающая in-repo улика: Watch-маркер в `api-constraint.md`
(«перепроверить после 15.06.2026») был **уже просрочен** на момент анализа — живое опровержение
самоэнфорса маркеров.

- **A → ПРИНЯТ как узкий content-gate, ОТКЛОНЁН как стоящая per-line таксономия.** Граница
  durable/volatile не crisp (Diátaxis сам предупреждает «easy to slip between forms»); широкая
  таксономия — over-reach §2 на n=1. Crisp-замена: ticket/CC-version-pinned факты → только в
  `native-capabilities.md` (dated, re-grounded, не shipped verbatim), никогда в `project-docs/*`.
- **B → ОТКЛОНЁН.** Маркер инертен (доказано просроченным Watch); grep `#NNNNN|CC 2.` ловит
  маркированное, а опасность — немаркированная проза; индустрия ловит staleness CI-раннером
  (eslint `expiring-todo-comments`), не аннотацией; redundant если A принят.
- **C → ОТКЛОНЁН как devlog-поле, ПРИНЯТ как Audit-grep.** Поле — флаг без адресата (аудитор
  стартует в downstream-проекте, не в lab-devlog'е); ADR `superseded-by` и IETF `Obsoletes:`
  эмпирически не каскадируют (ручной review). Рычаг — downstream-side grep сирот при corrective
  re-sync.
- **YAML-шапка → ОТКЛОНЕНА (идея оператора, обоснованное нет).** Anthropic-стандартного
  frontmatter для произвольных доков НЕ существует — `metadata:`/`version:` принадлежат
  agentskills.io-спеке для SKILL.md, не общим докам; эти baseline — проза, не компоненты →
  карго-культ. YAML-поле так же инертно, как HTML-комментарий (парсера нет, grep-verified).
  Асимметрия: HTML-комментарий невидим в отрендеренном markdown, YAML-frontmatter виден
  junk-блоком в downstream-доке → комментарий лучший носитель для verbatim-shipped.

**Реализовано (kit v1.9.0→v1.9.2, двумя шагами #108→#109):**
- `project-docs/workflow.md` — устаревший caveat (#108) и затем positive-нота «they compose»
  (#109) убраны; осталась durable-форма «use plan mode unless project defines its own ritual».
  Рефлексивно: grill переубедил автора — positive-нота сама volatile-claim («надгробие мёртвого
  бага»), её тоже выпилили.
- `SKILL.md` Maintenance — добавлен **content-gate** (A).
- `references/audit-checklist.md` — добавлен **orphan-sweep on corrective re-sync** (C).
- bump v1.9.2 + три shipped-by заголовка.
- `api-constraint.md` Watch-маркер **переверифицирован** (claude-code-guide + web): billing-сплит
  15.06.2026 поставлен на паузу в день вступления, headless `-p` на подписке цел; маркер
  переписан на «paused, not landed», не удалён.
- dialog_analyzer re-sync'нут до v1.9.2 (orphan-sweep чист).

## Затронутые файлы
- `~/.claude/skills/claude-code-harness/`: `references/project-docs/{workflow,testing,docs-discipline}.md`, `SKILL.md`, `references/audit-checklist.md`, `.claude-plugin/plugin.json` (v1.9.2)
- `/home/nikita/PROJECTS/Harnesses-Claude/.claude/rules/api-constraint.md` — Watch-маркер re-verified
- `/home/nikita/Документы/dialog_analyzer/.claude/docs/{workflow,testing,docs-discipline}.md` — re-sync v1.9.2

## Проверка
- `grep -rn "49947|disables Auto Mode|written plan file|they compose" references/` → 0 (kit clean)
- единая версия: plugin.json + 3 shipped-by = v1.9.2
- dialog_analyzer orphan-sweep на удалённый контент → 0 сирот в живом слое
- Watch-факт переверифицирован против first-party (Anthropic Help Center, code.claude.com/docs/en/headless)

## Alternatives considered (отклонены)
Inline expiry-маркеры (B), downstream-impact schema-поле (C), YAML-frontmatter conversion,
авто cross-project staleness-сканер — все либо инертны без runner'а, либо n=1-unearned по §2.
Источники: diataxis.fr/reference-explanation, anthropic.com/engineering (context-engineering),
eslint-plugin-unicorn expiring-todo-comments, adr.github.io + ietf RFC2026, agentskills.io/specification.

## Related
- #108 — v1.9.1 фикс (superseded этим: positive-нота из #108 выпилена в #109).
- Memory: [[reference_planmode_automode_conflict_resolved]].
