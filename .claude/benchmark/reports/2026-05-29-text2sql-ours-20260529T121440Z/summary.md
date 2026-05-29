# Battle-test: text2sql / ours

**Date**: 2026-05-29T12:14:40Z
**Build model**: opus
**Wall**: 660s (11m 0s) build only
**Total OAuth cost**: $4.3044

## Verdict: **accepted** (81 / 100)

| Section | Score | Max |
|---|---:|---:|
| F-Questions (auto) | 21 | 30 |
| T/B auto (scriptable) | 27 | 23 |
| T/B LLM-judge | 33 | 47 |
| **Grand total** | **81** | **100** |

Thresholds: ≥70 accepted · 50-69 partial · <50 failure.

## Build phase

- exit_code: 0
- stop_reason: end_turn
- turns: 64
- cost: $4.083331000000001
- tokens: in=7017 out=39340 cache_create=114568 cache_read=4312571

## Trajectory (Layer C)

```json
{
  "skills_triggered": [],
  "subagent_dispatches": {
    "count": 0,
    "types": []
  },
  "tool_calls_summary": [
    {
      "name": "Bash",
      "count": 22
    },
    {
      "name": "Write",
      "count": 20
    },
    {
      "name": "TaskUpdate",
      "count": 8
    },
    {
      "name": "Edit",
      "count": 7
    },
    {
      "name": "TaskCreate",
      "count": 4
    },
    {
      "name": "Read",
      "count": 1
    },
    {
      "name": "ToolSearch",
      "count": 1
    }
  ],
  "invariant_pings": []
}
```

## Result excerpt

```
Все 30 тестов проходят, многомесячный кейс считается корректно. Готово.

## Итог

Реализован агентский text2sql-ассистент в пакете `ai_analyst/`. Архитектура — именно агентская: локальная LLM через tool calling сама выбирает следующий шаг, жёсткого пайплайна нет.

**Структура:**
```
ai_analyst/
  config.py    — загрузка .env (Oracle + LLM)
  db.py        — oracledb: подключение, read-only guard, нормализация типов
  schema.py    — рендер схемы из metadata.py
  llm.py       — OpenAI-совместимый клиент к Ollama
  tools.py     — 4 инструмента + JSON-схемы + состояние сессии
  prompts.py   — системный промпт
  agent.py     — агентский цикл (tool calling loop)
  cli.py       — stdout=ответ, stderr=диагностика, exit 0
main.py        — альтернативная точка входа
tests/         — 30 тестов
pyproject.toml / requirements.txt / README.md / .gitignore
```

**4 инструмента** (по ТЗ): `inspect_schema`, `execute_sql`, `validate_result`, `final_answer` — каждый с JSON-схемой для function calling.

**Entry-points** (оба работают): `python -m ai_analyst "<вопрос>"` и `python main.py "<вопрос>"` (плюс console script `ai-analyst`). Финальный NL-ответ — последний print в stdout, диагностика шагов — в stderr, exit code 0.

**Проверено на реальной БД** (7 разнотипных вопросов, цифры сверены напрямую с Oracle):
- общий доход 2025 → 345 802 507,40 ✓
- активные клиенты → 82 ✓
- топ-5 по доходу за посл�
```

## Deliverable info

```json
{
  "status": "ok",
  "entry_kind": "module",
  "entry_module": "ai_analyst",
  "entry_script": null,
  "invocation_cmd": ".venv/bin/python -m ai_analyst",
  "venv_path": "/tmp/battle-text2sql-ours-20260529T121440Z/.venv",
  "venv_status": "pyproject_install (rc=0)",
  "install_log_tail": "Requirement already satisfied: httpx<1,>=0.23.0 in ./.venv/lib/python3.12/site-packages (from openai>=1.0->ai-analyst==0.1.0) (0.28.1)\nRequirement already satisfied: jiter<1,>=0.10.0 in ./.venv/lib/python3.12/site-packages (from openai>=1.0->ai-analyst==0.1.0) (0.15.0)\nRequirement already satisfied: pydantic<3,>=1.9.0 in ./.venv/lib/python3.12/site-packages (from openai>=1.0->ai-analyst==0.1.0) (2.13.4)\nRequirement already satisfied: sniffio in ./.venv/lib/python3.12/site-packages (from openai>=1.0->ai-analyst==0.1.0) (1.3.1)\nRequirement already satisfied: tqdm>4 in ./.venv/lib/python3.12/site-packages (from openai>=1.0->ai-analyst==0.1.0) (4.67.3)\nRequirement already satisfied: typing-extensions<5,>=4.11 in ./.venv/lib/python3.12/site-packages (from openai>=1.0->ai-analyst==0.1.0) (4.15.0)\nRequirement already satisfied: idna>=2.8 in ./.venv/lib/python3.12/site-packages (from anyio<5,>=3.5.0->openai>=1.0->ai-analyst==0.1.0) (3.17)\nRequirement already satisfied: certifi in ./.venv/lib/python3.12/site-packages (from httpx<1,>=0.23.0->openai>=1.0->ai-analyst==0.1.0) (2026.5.20)\nRequirement already satisfied: httpcore==1.* in ./.venv/lib/python3.12/site-packages (from httpx<1,>=0.23.0->openai>=1.0->ai-analyst==0.1.0) (1.0.9)\nRequirement already satisfied: h11>=0.16 in ./.venv/lib/python3.12/site-packages (from httpcore==1.*->httpx<1,>=0.23.0->openai>=1.0->ai-analyst==0.1.0) (0.16.0)\nRequirement already satisfied: annotated-types>=0.6.0 in ./.venv/lib/python3.12/site-packages (from pydantic<3,>=1.9.0->openai>=1.0->ai-analyst==0.1.0) (0.7.0)\nRequirement already satisfied: pydantic-core==2.46.4 in ./.venv/lib/python3.12/site-packages (from pydantic<3,>=1.9.0->openai>=1.0->ai-analyst==0.1.0) (2.46.4)\nRequirement already satisfied: typing-inspection>=0.4.2 in ./.venv/lib/python3.12/site-packages (from pydantic<3,>=1.9.0->openai>=1.0->ai-analyst==0.1.0) (0.4.2)\nRequirement already satisfied: cryptography>=3.2.1 in ./.venv/lib/python3.12/site-packages (from oracledb>=2.5.0->ai-analyst==0.1.0) (48.0.0)\nRequirement already satisfied: cffi>=2.0.0 in ./.venv/lib/python3.12/site-packages (from cryptography>=3.2.1->oracledb>=2.5.0->ai-analyst==0.1.0) (2.0.0)\nRequirement already satisfied: pycparser in ./.venv/lib/python3.12/site-packages (from cffi>=2.0.0->cryptography>=3.2.1->oracledb>=2.5.0->ai-analyst==0.1.0) (3.0)\nBuilding wheels for collected packages: ai-analyst\n  Building editable for ai-analyst (pyproject.toml): started\n  Building editable for ai-analyst (pyproject.toml): finished with status 'done'\n  Created wheel for ai-analyst: filename=ai_analyst-0.1.0-0.editable-py3-none-any.whl size=3175 sha256=9b1d16bc10bf911d1899335cc457060b377f838562adbb36cc08c7790157e31f\n  Stored in directory: /tmp/claude-1000/pip-ephem-wheel-cache-dcl2ngbx/wheels/64/a7/32/ff16469b1f48b59e777172f5926a72d222b83874af4fbd8105\nSuccessfully built ai-analyst\nInstalling collected packages: ai-analyst\n  Attempting uninstall: ai-analyst\n    Found existing installation: ai-analyst 0.1.0\n    Uninstalling ai-analyst-0.1.0:\n      Successfully uninstalled ai-analyst-0.1.0\nSuccessfully installed ai-analyst-0.1.0\n\n--- /tmp/battle-text2sql-ours-20260529T121440Z/.venv/bin/pip install -e . ---"
}
```

## F-Question scores

```json
{
  "status": "ok",
  "per_question": {
    "Q1": {
      "score": 0,
      "max": 6,
      "verdict": "fail",
      "reason": "no number 10/9/11 found"
    },
    "Q2": {
      "score": 6,
      "max": 6,
      "verdict": "pass",
      "reason": "all 5 orgs found"
    },
    "Q3": {
      "score": 6,
      "max": 6,
      "verdict": "pass",
      "reason": "Large + growth signal"
    },
    "Q4": {
      "score": 3,
      "max": 6,
      "verdict": "partial",
      "reason": "2 clients but без СМИРНОВ"
    },
    "Q5": {
      "score": 6,
      "max": 6,
      "verdict": "pass",
      "reason": "all 6 hubs within ±1"
    }
  },
  "total": 21,
  "max": 30
}
```

## T/B auto scores

```json
{
  "status": "ok",
  "items": {
    "T1": {
      "score": 6,
      "max": 6,
      "verdict": "pass",
      "reason": "21 py files, src/pkg structure, tests dir, pyproject"
    },
    "T2": {
      "score": 4,
      "max": 4,
      "verdict": "pass",
      "reason": "oracledb + openai with version constraints"
    },
    "T5": {
      "score": 8,
      "max": 8,
      "verdict": "pass",
      "reason": "6 test files, pytest passes"
    },
    "T6": {
      "score": 4,
      "max": 4,
      "verdict": "pass",
      "reason": "README 96 lines"
    },
    "B4": {
      "score": 5,
      "max": 5,
      "verdict": "pass",
      "reason": "median wall 3.6s"
    }
  },
  "total": 27,
  "max": 27
}
```

## LLM-judge scores

```json
{
  "T3": {
    "score": 5,
    "max": 6,
    "justification": "agent.py wraps the tool loop in try/except, cli.py catches top-level Exception with graceful 'Ошибка:' message, tools.execute_sql returns {'error':...} instead of raising (test_tools_dispatch confirms), and db.month_range swallows connect failures returning None. Empty result is flagged by validate_result's non_empty check rather than fabricated. Minor gap: oracledb.connect() in db.connect() and chat() LLM calls are not individually wrapped, relying on the outer loop try."
  },
  "T4": {
    "score": 6,
    "max": 6,
    "justification": "Consistent type hints on public functions (e.g. run()->AgentResult, sanitize_sql(sql:str)->str, load_settings()->Settings), docstrings on all classes/functions, clear naming, dataclasses used cleanly. Each module is well under 500 LoC and concerns are separated (db/llm/tools/agent/prompts). No visible dead code or copy-paste."
  },
  "T7": {
    "score": 5,
    "max": 6,
    "justification": "db.sanitize_sql enforces single read-only SELECT/WITH, strips trailing ';', and blocks DML/DDL verbs (tests in test_db_guard cover delete/update/multi-statement). Prompt mandates Oracle DATE 'YYYY-MM-DD' literals and case-insensitive UPPER(...) LIKE. Weakness: SQL is free-form LLM-generated interpolation, not parameterized bind variables, so robustness rests on the guard/whitelist rather than true parameterization (month_range uses f-string table interpolation with noqa S608)."
  },
  "B1": {
    "score": 4,
    "max": 6,
    "justification": "final_answer produces a Russian NL answer with numbers + interpretation (README example: 'Общий доход банка за 2025 год составил 345 802 507,40 рублей...'), not raw DB rows. However there is no explicit handling/instruction to render long multi-row results as a markdown table; results are merely truncated to 200 rows, so larger outputs are not formatted as analyst-readable tables."
  },
  "B2": {
    "score": 5,
    "max": 6,
    "justification": "Dedicated validate_result tool with _validate supporting min_rows/max_rows, non_null_columns, and numeric_ranges checks; empty result is explicitly flagged (test_empty_result_flagged) and range violations surface in summary (test_numeric_range_violation_fails). The prompt instructs the agent to call validate_result before final_answer. Note: max for B2 is 5 per rubric; awarded near-full for solid sanity-check coverage."
  },
  "B3": {
    "score": 5,
    "max": 6,
    "justification": "agent loop guards against models that emit no tool_call via bounded nudges (max 2) then falls back to last text, and MAX_STEPS=10 prevents infinite looping on simple queries. Ambiguity is reduced by injecting the real data month_range and defining 'last month' = MAX(MONTH_DT). SQL errors are returned to the model for self-correction. Missing-field/clarification behavior is delegated to the LLM with no explicit clarify path, limiting full marks."
  },
  "B5": {
    "score": 3,
    "max": 8,
    "justification": "Config is cleanly via env vars/.env with no hardcoded credentials (config.py _require), connection has lazy connect + close() and a read-only guard. However logging is plain print-to-stderr (_log), not structured; and there is no Dockerfile, no CI workflow, no connection pool, and no retry/backoff logic — significant production-readiness gaps for the 8-pt item."
  },
  "total": 33,
  "cost_usd": 0.2211135,
  "status": "ok"
}
```

## Clone preservation

`/tmp/battle-text2sql-ours-20260529T121440Z` — preserved для forensics

## Methodology

- `.claude/docs/benchmark.md` — 4-layer framework
- `.claude/benchmark/text2sql-judge/README.md` — battle-test specifics
- `.claude/benchmark/text2sql-judge/acceptance.yaml` — 100-pt rubric
