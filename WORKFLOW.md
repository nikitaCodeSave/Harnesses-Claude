# Development workflow with Claude Code

Текущий (Opus 4.8 / Claude Code 2.1.169, 2026-06) workflow для разработчика высокого класса.
Плотный портативный гайд от старта проекта до пайплайна — с акцентом на рычаги, двигающие качество. Первоисточники — внизу.

> Это human-facing гайд. Машинный routing-spine для main thread'а — `.claude/docs/workflow.md`.

---

## 0. Установка, на которой стоит всё остальное

- **Harness важнее модели — и его надо переучивать.** «Review your configuration every 3-6 months because instructions tuned for older models constrain newer ones» [[1]]. Под способной моделью **минимум обвязки = максимум продуктивности**: каждый компонент кодирует assumption «модель не умеет X»; умеет нативно → компонент вреден.
- **Не микроменеджь модель:** `effort=high` (дефолт 4.8 — не понижай на `medium` для нетривиалки), adaptive thinking ON (не управляй thinking-бюджетом вручную), sampling-параметры (`temperature`/`top_p`/`top_k`) на 4.8 убрать совсем (HTTP 400). [[2]]

---

## 1. Старт проекта — первая сессия

Цель первой сессии — **не код, а конфигурация окружения + контракт**, собранный из разговора (не upfront-анкетой — под 4.8 контракт всплывает органически).

- **`/init`** — Claude читает репо → стартовый `CLAUDE.md` (≤200 строк, **indexer, не store**: ссылается на `docs/`, не дублирует). Greenfield (нет кода / нет `.git`) → можно opinionated стек с rationale; existing → уважай конвенции **verbatim**.
- **Зафиксируй 5 пунктов контракта** по мере появления: стек (без молчаливых дефолтов) · project mode (new/mature) · acceptance criteria первого deliverable · механизм верификации (test cmd / lint / screenshot / manual) · sensitive paths → DENY.
- **Guardrails — сразу и реактивно.** Опасное (prod-config, реальная БД, deploy-скрипт, секрет) → `permissions.deny` в `.claude/settings.json` + строка «never touch X» в `CLAUDE.md`. **Механический guard переживает потерю контекста, инструкция — нет.** [[2]][[8]]

---

## 2. Требования и PRD

- **Думай вслух, не предполагай молча.** Несколько интерпретаций → выложи их, не выбирай тихо; проще решение → скажи. Уточняющие вопросы — только на развилках, реально меняющих *что* строить (не на том, что выводится из кода).
- **Контекст-слой = версионируемый артефакт, не одноразовый setup:** «Claude can't learn without you recording context… version it, grow it, maintain it». [[9]]
- **PRD-lite (1 страница), не бюрократия** (simplicity-first):

  ```
  Проблема:       что болит и у кого
  Пользователь:   кто, в каком сценарии
  Success (done): 3-5 наблюдаемых критериев (= acceptance criteria)
  Out of scope:   что НЕ делаем (защита от goal drift)
  Открытое:       отложенные решения → ADR
  ```
- **Acceptance criteria = наблюдаемое поведение через публичный интерфейс** («пользователь оформляет заказ с валидной корзиной»), не «сделать хорошо». Это **оракул, пронизывающий весь пайплайн**.
- **GLOSSARY first-use:** первый domain-термин/аббревиатура → запись. PRD живёт в `docs/` (или `.claude/progress/<slug>.md` для крупной in-flight задачи).

---

## 3. Дизайн и решения — до кода

Вход в фазу **Plan** (механика — в Спине ниже). Здесь фиксируешь *что решено и почему*.

- Архитектурные развилки — built-in **`Plan`-агент** / Plan mode; тяжёлое планирование — `/ultraplan` (cloud, 3 A/B-варианта). [[3]]
- **Каждое нетривиальное решение → ADR** (Context / Decision / Consequences / Alternatives). Порог простой: *объяснение заняло бы >5 мин → ADR*.
- Нетривиальный кодбейз → bootstrap проектных доков (`ARCHITECTURE` / `CODE-MAP` / `GLOSSARY` / `CONVENTIONS` / `ADR/` / `RUNBOOKS/`), **read-before-write** — реальное содержимое, не boilerplate.
- **Built-ins first:** не плоди кастомных `PM→Architect→Dev→QA` субагентов — оркестратор это **ты** (main thread). [[4]]

---

## Пайплайн одним взглядом

```
КОНТРАКТ      →  ТРЕБОВАНИЯ        →  ДИЗАЙН       →  WORK             →  REVIEW            →  СЛЕД
/init            PRD-lite             Plan mode       1 main thread       self+tests/lint      devlog
стек/mode        acceptance=оракул    Plan-агент      RED→GREEN→refactor  /review              progress→devlog
DENY-правила     GLOSSARY             ADR / docs      ultracode если      fresh-context §8     doc-with-code
                                                      scope>1 контекст    ultrareview(high)    MEMORY
      └──────────────── оракул (acceptance criteria) пронизывает весь поток ────────────────┘
```

Правило выбора режима: план в 2-3 шага в голове → single thread in-conversation · план становится кодом / сотни независимых операций / scope>1 контекст → dynamic workflow (`ultracode`) · дорого-необратимо и «выглядит готовым» → добавь fresh-context критика.

---

## Спина: Plan → Work → Review (ядро execution)

Дефолт для **нетривиальной** задачи. Typo / one-liner — сразу Work → Review.

### PLAN — отделить «понять» от «делать»
- **Plan mode** (`Shift+Tab`×2 или `--permission-mode plan`): read-only разведка до первой записи на диск. Тяжёлое планирование — built-in `Plan`-агент через Task, либо `/ultraplan` (cloud) для архитектурных развилок.
- **Acceptance criteria явно** (что = «done»), critical files, альтернативы. Это оракул, против которого крутится Review. Решение, объяснять которое >5 мин → ADR.
- Формализация «done» как **sprint-contract** (deliverables + success metrics до кода). [[3]]

### WORK — один поток, весь lifecycle в одном контексте
- **1 main thread, 1M контекст** — фича целиком без handoff'ов. Single-agent — дефолт для most coding; multi-agent Anthropic явно называет «ill-suited» для большинства кодинга. [[4]]
- **Test-driven как runnable-оракул**, не как догма очерёдности: read → тест на наблюдаемое поведение через публичный интерфейс (RED) → impl → GREEN → refactor. Тест обязан быть способен упасть. **Никогда не ослабляй тест ради зелёного.**
- **5 тест-инвариантов** (компактно): тест в **той же сессии**, что и код · способен упасть · живёт **рядом с кодом** · **один тест — одно поведение** · **регрессионный тест перед фиксом бага** (воспроизвести RED → фикс → GREEN). Мокай только реально внешнюю границу (tool/API/network), не внутренности.
- `TaskCreate`/`TaskUpdate` для >3 шагов (L0, session-scoped).
- **Subagent — только** при (а) изоляции контекста (broad scan загрязнит main), (б) параллельности независимых проверок, (в) auto-compact rescue. Иначе main thread сам. [[4]]

### REVIEW — главный рычаг
- Self-review + tests/lint/type-check всегда. **«Looks done ≠ is done»** — гоняй фичу end-to-end, не только unit/`curl`.
- `/review` (built-in, local, codebase-aware) на каждый substantive change; `claude ultrareview` (cloud-fleet, ~20мин) — для high-stakes.
- **Независимая верификация = fresh context, не self-recheck.** In-context «перепроверь себя» добавляет ≈0 — автор якорится на своём решении (Anthropic называет это **self-preferential bias** — одна из трёх failure-mode длинных/параллельных прогонов, наряду с *agentic laziness* «бросил, объявив done» и *goal drift* «констрейнты ушли через compaction»; изолированные субагенты лечат все три структурно [[7]]). Рычаг — **отдельный fresh-context критик (subagent / новая сессия), которому велено опровергать, а не подтверждать** (judge≠author / Planner→Generator→Evaluator). Сильный вариант: evaluator взаимодействует с **живым приложением** (Playwright MCP) перед оценкой, калиброван быть скептичным. [[3]] Это ⊥ TDD: TDD — *как строить*, это — *кто судит*.

---

## Лестница верификации (cheapest → strongest)

`in-prompt check` → `/goal <condition>` (re-checked каждый ход [[5]]) → **Stop-hook** (детерминированный гейт) → **fresh-context критик / dynamic workflow**.

Дай Claude петлю, которую он закрывает сам — «the single highest-leverage thing you can do» [[2]]. Анти-паттерн: одна end-session проверка (two-gate снижает false-completion ~35%→4%).

---

## Continuity — три слоя, не путать

| Слой | Где | Роль |
|---|---|---|
| **devlog** | `.claude/devlog/`, git | эпизодика «что и почему» после фичи/фикса/решения |
| **progress journal** | `.claude/progress/<slug>.md` | in-flight state задачи >1ч / ≥3 решений; переживает compact → конвертируется в devlog |
| **auto-memory** | `MEMORY.md` | атемпоральные факты / преференции |

Рамка: **файл = authoritative state, контекст эфемерен** — читаешь курированные снапшоты, не историю. [[6]]

---

## Когда выходить за один контекст (и только тогда)

Scope **превышает один контекст** (codebase-sweep, миграция, trust-critical find→refute→converge):

- **Built-in dynamic workflows** — keyword **`ultracode`** (trigger word, не отдельный режим; переименован с `workflow` в 2.1.160 — голое «workflow» больше не триггерит) или просто попроси. Claude пишет собственный `.js`-harness под задачу: скрипт держит план/цикл/промежуточные результаты, в контекст входит только финал; **harness = output задачи, не предусловие**, переживает прерывание (resume). Стоит **заметно больше токенов** — не дефолт. [[7]]
- **НЕ** строй кастомный PM→Architect→Dev→QA pipeline (built-ins-first).
- **Недоверенный вход в fan-out → quarantine**: субагенты, читающие untrusted-контент (web/issues/email), отделены от тех, кто выполняет high-privilege действия — privilege-separation против prompt-injection. [[7]]
- Параллельные ветки — `-w` worktree + `claude agents` (с 2.1.169 `--json` отдаёт `id`/`state`/`--all` для observability фронта). Async-ожидание — `Monitor` tool, **никогда** bash `sleep`.

---

## Ритуал поверх всего

Раз в 3-6 мес (или на мажорном апгрейде модели) — **аудит harness'а на staleness**: что модель теперь делает нативно → выкинуть. Быстрый тест «модель или обвязка» — `--safe-mode` (старт с отключёнными CLAUDE.md/skills/hooks/MCP, 2.1.169): если без harness'а не хуже — компонент устарел. Под 4.6+ Anthropic сама убрала ручные context-resets и sprint-decomposition («context anxiety» ушла). [[1]][[3]]

---

## Источники (first-party)

- [1] [How Claude Code works in large codebases](https://www.claude.com/blog/how-claude-code-works-in-large-codebases-best-practices-and-where-to-start) (2026-05-14) — harness-matters-more-than-model
- [2] [Claude Code best practices](https://code.claude.com/docs/en/best-practices) — verification loop, effort, thinking
- [3] [Harness Design for Long-Running Application Development](https://www.anthropic.com/engineering/harness-design-long-running-apps) (2026-03) — P→G→E, sprint-contracts, evaluator с live-app
- [4] [Sub-agents](https://code.claude.com/docs/en/sub-agents) — single-agent default, subagent discipline
- [5] [/goal](https://code.claude.com/docs/en/goal) — completion conditions, re-check каждый ход
- [6] [Effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) + [Effective context engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)
- [7] [A harness for every task: dynamic workflows in Claude Code](https://claude.com/blog/a-harness-for-every-task-dynamic-workflows-in-claude-code) (2026-06-02, Shihipar & Bidasaria) — Claude пишет свой `.js`-harness; 3 failure-mode (laziness / self-preferential bias / goal drift); quarantine pattern; `ultracode` = trigger word
- [8] [Claude Code Sandboxing](https://www.anthropic.com/engineering/claude-code-sandboxing) + [Settings](https://code.claude.com/docs/en/settings) — permissions (deny/ask/allow), guardrails, OS-level sandbox
- [9] [Onboarding Claude Code like a new developer](https://claude.com/blog/onboarding-claude-code-like-a-new-developer-lessons-from-17-years-of-development) (MacLean) — контекст-слой как версионируемый артефакт; «record context, version it, grow it»

<!-- last-updated: 2026-06-09 · target: Opus 4.8 / Claude Code 2.1.169 -->
