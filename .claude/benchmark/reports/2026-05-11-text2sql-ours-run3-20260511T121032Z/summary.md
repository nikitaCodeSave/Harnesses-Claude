# Battle-test: text2sql / ours

**Date**: 2026-05-11T12:19:38Z
**Build model**: claude-opus-4-7
**Wall**: 455s (7m 35s) build only
**Total OAuth cost**: $3.4648

## Verdict: **accepted** (93 / 100)

| Section | Score | Max |
|---|---:|---:|
| F-Questions (auto) | 27 | 30 |
| T/B auto (scriptable) | 27 | 23 |
| T/B LLM-judge | 39 | 47 |
| **Grand total** | **93** | **100** |

Thresholds: ≥70 accepted · 50-69 partial · <50 failure.

## Build phase

- exit_code: 0
- stop_reason: end_turn
- turns: 50
- cost: $3.242376250000001
- tokens: in=59 out=36386 cache_create=111313 cache_read=3273450

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
      "name": "Write",
      "count": 21
    },
    {
      "name": "Bash",
      "count": 15
    },
    {
      "name": "Edit",
      "count": 4
    },
    {
      "name": "Read",
      "count": 4
    },
    {
      "name": "TodoWrite",
      "count": 4
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
Готово. Что собрано:

**Структура.**
- `ai_analyst/` — package: `config.py`, `db.py`, `llm.py`, `tools.py`, `prompts.py`, `agent.py`, `cli.py`, `__main__.py`.
- `main.py` — альтернативный entry-point. Оба canonical-инвокейшна работают: `python -m ai_analyst "..."` и `python main.py "..."`.
- `pyproject.toml` (setuptools), `requirements.txt`, `README.md`.
- `tests/` — 61 unit-тест, без сети, через фейковый Oracle и фейковый OpenAI-клиент.

**Tools (function calling через OpenAI-совместимый API):**
- `inspect_schema(table)` — отдаёт LLM описание таблицы и примеры SQL из `metadata.py`.
- `execute_sql(sql, max_rows?)` — read-only Oracle через `oracledb`; allowlist (`SELECT`/`WITH`), запрет multi-statement и DML/DDL, лимит строк.
- `validate_result(result, expectations?)` — sanity-check (размер, non-null/numeric/non-negative по колонкам).
- `final_answer(text, supporting_data?)` — маркер завершения цикла; agent loop опознаёт `__final_answer__` и прерывается.

**Agent loop** (`agent.py`): чистый цикл `chat.completions.create(tools=...)`, `tool_choice="auto"`, `temperature=0.0`. Восстановление после ошибок инструментов, fallback на text-only ответ, лимит `--max-steps` (12).

**Безопасность.** SQL-валидация — вторая линия защиты после промпта: одиночный SELECT/WITH без `;`, явный blocklist опасных ключевых слов.

**Тесты:** `PYTHONPATH=. .venv/bin/pytest tests/` → 61 passed. Покрывают валидацию SQL, все 4 tool'а, agent loop с фейк-LLM (включая recovery, unknown tool, bad JSON, max_steps), загрузку конфига и CLI (stdout/stderr/stdin/exit-c
```

## Deliverable info

```json
{
  "status": "ok",
  "entry_kind": "module",
  "entry_module": "ai_analyst",
  "entry_script": null,
  "invocation_cmd": ".venv/bin/python -m ai_analyst",
  "venv_path": "/tmp/battle-text2sql-ours-20260511T121938Z/.venv",
  "venv_status": "pyproject_install (rc=0)",
  "install_log_tail": "Requirement already satisfied: openai>=1.0 in ./.venv/lib/python3.12/site-packages (from ai-analyst==0.1.0) (2.36.0)\nRequirement already satisfied: python-dotenv>=1.0 in ./.venv/lib/python3.12/site-packages (from ai-analyst==0.1.0) (1.2.2)\nRequirement already satisfied: anyio<5,>=3.5.0 in ./.venv/lib/python3.12/site-packages (from openai>=1.0->ai-analyst==0.1.0) (4.13.0)\nRequirement already satisfied: distro<2,>=1.7.0 in ./.venv/lib/python3.12/site-packages (from openai>=1.0->ai-analyst==0.1.0) (1.9.0)\nRequirement already satisfied: httpx<1,>=0.23.0 in ./.venv/lib/python3.12/site-packages (from openai>=1.0->ai-analyst==0.1.0) (0.28.1)\nRequirement already satisfied: jiter<1,>=0.10.0 in ./.venv/lib/python3.12/site-packages (from openai>=1.0->ai-analyst==0.1.0) (0.14.0)\nRequirement already satisfied: pydantic<3,>=1.9.0 in ./.venv/lib/python3.12/site-packages (from openai>=1.0->ai-analyst==0.1.0) (2.13.4)\nRequirement already satisfied: sniffio in ./.venv/lib/python3.12/site-packages (from openai>=1.0->ai-analyst==0.1.0) (1.3.1)\nRequirement already satisfied: tqdm>4 in ./.venv/lib/python3.12/site-packages (from openai>=1.0->ai-analyst==0.1.0) (4.67.3)\nRequirement already satisfied: typing-extensions<5,>=4.11 in ./.venv/lib/python3.12/site-packages (from openai>=1.0->ai-analyst==0.1.0) (4.15.0)\nRequirement already satisfied: idna>=2.8 in ./.venv/lib/python3.12/site-packages (from anyio<5,>=3.5.0->openai>=1.0->ai-analyst==0.1.0) (3.14)\nRequirement already satisfied: certifi in ./.venv/lib/python3.12/site-packages (from httpx<1,>=0.23.0->openai>=1.0->ai-analyst==0.1.0) (2026.4.22)\nRequirement already satisfied: httpcore==1.* in ./.venv/lib/python3.12/site-packages (from httpx<1,>=0.23.0->openai>=1.0->ai-analyst==0.1.0) (1.0.9)\nRequirement already satisfied: h11>=0.16 in ./.venv/lib/python3.12/site-packages (from httpcore==1.*->httpx<1,>=0.23.0->openai>=1.0->ai-analyst==0.1.0) (0.16.0)\nRequirement already satisfied: annotated-types>=0.6.0 in ./.venv/lib/python3.12/site-packages (from pydantic<3,>=1.9.0->openai>=1.0->ai-analyst==0.1.0) (0.7.0)\nRequirement already satisfied: pydantic-core==2.46.4 in ./.venv/lib/python3.12/site-packages (from pydantic<3,>=1.9.0->openai>=1.0->ai-analyst==0.1.0) (2.46.4)\nRequirement already satisfied: typing-inspection>=0.4.2 in ./.venv/lib/python3.12/site-packages (from pydantic<3,>=1.9.0->openai>=1.0->ai-analyst==0.1.0) (0.4.2)\nRequirement already satisfied: cryptography>=3.2.1 in ./.venv/lib/python3.12/site-packages (from oracledb>=2.5.0->ai-analyst==0.1.0) (48.0.0)\nRequirement already satisfied: cffi>=2.0.0 in ./.venv/lib/python3.12/site-packages (from cryptography>=3.2.1->oracledb>=2.5.0->ai-analyst==0.1.0) (2.0.0)\nRequirement already satisfied: pycparser in ./.venv/lib/python3.12/site-packages (from cffi>=2.0.0->cryptography>=3.2.1->oracledb>=2.5.0->ai-analyst==0.1.0) (3.0)\nBuilding wheels for collected packages: ai-analyst\n  Building editable for ai-analyst (pyproject.toml): started\n  Building editable for ai-analyst (pyproject.toml): finished with status 'done'\n  Created wheel for ai-analyst: filename=ai_analyst-0.1.0-0.editable-py3-none-any.whl size=5766 sha256=dd590526e5d7e3523cc6e63144dae78cb3985b84ee5b51ec85d4e9df6dee6381\n  Stored in directory: /tmp/pip-ephem-wheel-cache-f4_pmakq/wheels/40/2f/63/982e8b51352327234c44e0cb7042f973dd23ff817d21580b75\nSuccessfully built ai-analyst\nInstalling collected packages: ai-analyst\nSuccessfully installed ai-analyst-0.1.0\n\n--- /tmp/battle-text2sql-ours-20260511T121938Z/.venv/bin/pip install -e . ---"
}
```

## F-Question scores

```json
{
  "status": "ok",
  "per_question": {
    "Q1": {
      "score": 6,
      "max": 6,
      "verdict": "pass",
      "reason": "found 10 / десять"
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
  "total": 27,
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
      "reason": "22 py files, src/pkg structure, tests dir, pyproject"
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
      "reason": "README 122 lines"
    },
    "B4": {
      "score": 5,
      "max": 5,
      "verdict": "pass",
      "reason": "median wall 6.2s"
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
    "score": 6,
    "max": 6,
    "justification": "Comprehensive try/except: agent.py wraps tool handlers (line ~115 `try: tool_output = handler(args)` with BLE001), tools.py make_execute_sql catches SqlValidationError and generic exceptions returning {error: ...} dict, cli.py wraps run_question in try/except returning exit code 1 with stderr message. JSON decode errors in tool_calls handled gracefully. Empty results explicitly flagged by validate_result rather than fabricated."
  },
  "T4": {
    "score": 6,
    "max": 6,
    "justification": "Type hints on all public functions (load_config, assert_readonly_sql, Agent.run, etc.). Docstrings on modules, classes, and key functions. Clear naming (OracleClient, QueryResult, ToolHandler). Modules well under 500 LoC. Dataclasses (Config, AgentResult, QueryResult) used cleanly. No dead code observed."
  },
  "T7": {
    "score": 6,
    "max": 6,
    "justification": "db.py:assert_readonly_sql whitelists only SELECT/WITH, rejects multi-statement (semicolons), and blocks DML/DDL keywords via regex. Schema fields sourced from metadata.py (not user input). System prompt instructs Oracle DATE 'YYYY-MM-DD' literals (prompts.py). LLM generates SQL but is constrained by allowlist validation; no string concat of user NL into SQL."
  },
  "B1": {
    "score": 5,
    "max": 6,
    "justification": "System prompt explicitly requires NL responses with units (rubles/штуки/%) and human-readable formatting like '1.23 млрд ₽', '12 345 клиентов'; final_answer tool returns text-only output to stdout. No explicit markdown-table handling for long results, but supporting_data flag provides structured JSON option."
  },
  "B2": {
    "score": 5,
    "max": 5,
    "justification": "Dedicated validate_result tool with checks: min/max_rows, non_null_columns, numeric_columns, non_negative_columns. Flags empty results, NULL values, non-numeric data, missing columns. Prompt explicitly instructs agent to call validate_result after execute_sql and react to issues."
  },
  "B3": {
    "score": 5,
    "max": 6,
    "justification": "Agent recovers from SQL errors (tested in test_recovers_from_sql_error), handles unknown tools, bad JSON args, text-only LLM responses with fallback. Max-steps cap prevents infinite loops. Empty stdin question rejected via argparse.error. Ambiguous NL handling relies on LLM choosing sensible defaults — no explicit clarification flow."
  },
  "B5": {
    "score": 6,
    "max": 8,
    "justification": "Config via env vars with required validation (no hardcoded creds), .env via python-dotenv. OracleClient with context-manager, explicit close(), lazy connect. Verbose diagnostics to stderr (basic logging, not structured). pyproject.toml with entry point script. No Dockerfile, no CI workflow, no retry logic, no connection pooling, no structured logging library."
  },
  "total": 39,
  "cost_usd": 0.22238850000000002,
  "status": "ok"
}
```

## Clone preservation

`/tmp/battle-text2sql-ours-20260511T121938Z` — preserved для forensics

## Methodology

- `.claude/docs/benchmark.md` — 4-layer framework
- `.claude/benchmark/text2sql-judge/README.md` — battle-test specifics
- `.claude/benchmark/text2sql-judge/acceptance.yaml` — 100-pt rubric
