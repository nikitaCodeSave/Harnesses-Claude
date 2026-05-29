# Battle-test: text2sql / ours

**Date**: 2026-05-11T12:10:32Z
**Build model**: claude-opus-4-7
**Wall**: 508s (8m 28s) build only
**Total OAuth cost**: $3.7418

## Verdict: **accepted** (91 / 100)

| Section | Score | Max |
|---|---:|---:|
| F-Questions (auto) | 27 | 30 |
| T/B auto (scriptable) | 27 | 23 |
| T/B LLM-judge | 37 | 47 |
| **Grand total** | **91** | **100** |

Thresholds: ≥70 accepted · 50-69 partial · <50 failure.

## Build phase

- exit_code: 0
- stop_reason: end_turn
- turns: 55
- cost: $3.526328750000001
- tokens: in=64 out=38363 cache_create=112461 cache_read=3728105

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
      "count": 18
    },
    {
      "name": "TodoWrite",
      "count": 6
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
      "name": "ToolSearch",
      "count": 1
    }
  ],
  "invariant_pings": []
}
```

## Result excerpt

```
Готово.

**Что собрал:**
- Агентский text2sql с tool-calling через OpenAI-совместимый API (Ollama) поверх Oracle XE (`oracledb`).
- 4 tool'а с JSON-Schema (structured input): `inspect_schema`, `execute_sql`, `validate_result`, `final_answer` — модель сама выбирает следующий шаг, жёсткого pipeline нет.
- Safety SQL (только SELECT/WITH, без multi-statement, без DDL/DML) — на уровне Dispatcher и Oracle-клиента (defence-in-depth).
- Оба entry-point'а: `python -m text2sql "..."` и `python main.py "..."`, последний blocking print — финальный ответ, exit code 0.
- Setuptools `pyproject.toml` + `requirements.txt`, без `uv`.
- 37 unit-тестов проходят (стабы для OpenAI SDK и Oracle, без живых сервисов).
- README с архитектурой, запуском, безопасностью и ограничениями.

**End-to-end проверка с живыми сервисами:**
- `python -m text2sql "какой общий доход за 2025 год?"` → "Общий доход по всем клиентам за 2025 год составил 345 802 507,40 рублей." (4 шага агента).
- `python -m text2sql --show-trace "сколько уникальных клиентов в базе?"` → "В базе данных зарегистрировано 103 уникальных клиента." Trace показал ожидаемую последовательность `inspect_schema → execute_sql → validate_result → final_answer`.

**Что в репо:**
```
text2sql/{__init__,__main__,agent,config,db,llm,prompts,schema,tools,validator}.py
tests/{conftest,test_db_safety,test_schema,test_tools,test_validator,test_agent_loop}.py
main.py  pyproject.toml  requirements.txt  README.md
```

Остался артефакт `trace.err` (stderr-сброс отладочн
```

## Deliverable info

```json
{
  "status": "ok",
  "entry_kind": "module",
  "entry_module": "text2sql",
  "entry_script": null,
  "invocation_cmd": ".venv/bin/python -m text2sql",
  "venv_path": "/tmp/battle-text2sql-ours-20260511T121032Z/.venv",
  "venv_status": "pyproject_install (rc=0)",
  "install_log_tail": "Requirement already satisfied: openai>=1.0 in ./.venv/lib/python3.12/site-packages (from text2sql==0.1.0) (2.36.0)\nRequirement already satisfied: python-dotenv>=1.0 in ./.venv/lib/python3.12/site-packages (from text2sql==0.1.0) (1.2.2)\nRequirement already satisfied: anyio<5,>=3.5.0 in ./.venv/lib/python3.12/site-packages (from openai>=1.0->text2sql==0.1.0) (4.13.0)\nRequirement already satisfied: distro<2,>=1.7.0 in ./.venv/lib/python3.12/site-packages (from openai>=1.0->text2sql==0.1.0) (1.9.0)\nRequirement already satisfied: httpx<1,>=0.23.0 in ./.venv/lib/python3.12/site-packages (from openai>=1.0->text2sql==0.1.0) (0.28.1)\nRequirement already satisfied: jiter<1,>=0.10.0 in ./.venv/lib/python3.12/site-packages (from openai>=1.0->text2sql==0.1.0) (0.14.0)\nRequirement already satisfied: pydantic<3,>=1.9.0 in ./.venv/lib/python3.12/site-packages (from openai>=1.0->text2sql==0.1.0) (2.13.4)\nRequirement already satisfied: sniffio in ./.venv/lib/python3.12/site-packages (from openai>=1.0->text2sql==0.1.0) (1.3.1)\nRequirement already satisfied: tqdm>4 in ./.venv/lib/python3.12/site-packages (from openai>=1.0->text2sql==0.1.0) (4.67.3)\nRequirement already satisfied: typing-extensions<5,>=4.11 in ./.venv/lib/python3.12/site-packages (from openai>=1.0->text2sql==0.1.0) (4.15.0)\nRequirement already satisfied: idna>=2.8 in ./.venv/lib/python3.12/site-packages (from anyio<5,>=3.5.0->openai>=1.0->text2sql==0.1.0) (3.14)\nRequirement already satisfied: certifi in ./.venv/lib/python3.12/site-packages (from httpx<1,>=0.23.0->openai>=1.0->text2sql==0.1.0) (2026.4.22)\nRequirement already satisfied: httpcore==1.* in ./.venv/lib/python3.12/site-packages (from httpx<1,>=0.23.0->openai>=1.0->text2sql==0.1.0) (1.0.9)\nRequirement already satisfied: h11>=0.16 in ./.venv/lib/python3.12/site-packages (from httpcore==1.*->httpx<1,>=0.23.0->openai>=1.0->text2sql==0.1.0) (0.16.0)\nRequirement already satisfied: annotated-types>=0.6.0 in ./.venv/lib/python3.12/site-packages (from pydantic<3,>=1.9.0->openai>=1.0->text2sql==0.1.0) (0.7.0)\nRequirement already satisfied: pydantic-core==2.46.4 in ./.venv/lib/python3.12/site-packages (from pydantic<3,>=1.9.0->openai>=1.0->text2sql==0.1.0) (2.46.4)\nRequirement already satisfied: typing-inspection>=0.4.2 in ./.venv/lib/python3.12/site-packages (from pydantic<3,>=1.9.0->openai>=1.0->text2sql==0.1.0) (0.4.2)\nRequirement already satisfied: cryptography>=3.2.1 in ./.venv/lib/python3.12/site-packages (from oracledb>=2.5.0->text2sql==0.1.0) (48.0.0)\nRequirement already satisfied: cffi>=2.0.0 in ./.venv/lib/python3.12/site-packages (from cryptography>=3.2.1->oracledb>=2.5.0->text2sql==0.1.0) (2.0.0)\nRequirement already satisfied: pycparser in ./.venv/lib/python3.12/site-packages (from cffi>=2.0.0->cryptography>=3.2.1->oracledb>=2.5.0->text2sql==0.1.0) (3.0)\nBuilding wheels for collected packages: text2sql\n  Building editable for text2sql (pyproject.toml): started\n  Building editable for text2sql (pyproject.toml): finished with status 'done'\n  Created wheel for text2sql: filename=text2sql-0.1.0-0.editable-py3-none-any.whl size=5720 sha256=f80df0344661a0ed56754610ee201fc2a09808667db52e21c00a0941f3fb7b3e\n  Stored in directory: /tmp/pip-ephem-wheel-cache-nby2kkss/wheels/88/57/b3/6ec0181179e6e7f025945d50b0f7a63680b0260def06d6887e\nSuccessfully built text2sql\nInstalling collected packages: text2sql\nSuccessfully installed text2sql-0.1.0\n\n--- /tmp/battle-text2sql-ours-20260511T121032Z/.venv/bin/pip install -e . ---"
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
      "reason": "23 py files, src/pkg structure, tests dir, pyproject"
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
      "reason": "README 125 lines"
    },
    "B4": {
      "score": 5,
      "max": 5,
      "verdict": "pass",
      "reason": "median wall 4.3s"
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
    "justification": "Try/except wraps Oracle/LLM init and agent run in __main__.py with logged stack trace + user-friendly stderr message; ToolDispatcher catches SQLSafetyError and arbitrary exceptions, returning structured error dicts to the LLM (tools.py). JSON parse errors in agent.py handled gracefully. Minor gap: no explicit retry on Oracle connection failures."
  },
  "T4": {
    "score": 6,
    "max": 6,
    "justification": "Consistent type hints throughout (dataclasses, Protocol, return types). Module docstrings on every file, function docstrings on public APIs. Modules well under 500 LoC each. Clean separation: agent/db/tools/validator/schema/config. No dead code observed."
  },
  "T7": {
    "score": 5,
    "max": 6,
    "justification": "assert_safe_select in db.py whitelists SELECT/WITH prefix, blocks DDL/DML keywords, rejects multi-statement via ';'. Defence-in-depth: check duplicated in dispatcher and OracleClient. Tests cover SQL injection vectors (test_db_safety.py). Prompt instructs DATE 'YYYY-MM-DD' literals. Slight risk: regex-based keyword block could be bypassed by comments/encoded payloads, no actual parameter binding."
  },
  "B1": {
    "score": 5,
    "max": 6,
    "justification": "final_answer tool schema explicitly requires NL response in Russian with numbers + units (рубли/шт) + period/filters, 1-5 sentences (prompts.py, tools.py). Test example shows '123 456 789 руб.' formatting. SYSTEM_PROMPT forbids raw SQL in final answer. Markdown tables for long results not explicitly handled."
  },
  "B2": {
    "score": 5,
    "max": 5,
    "justification": "validator.py provides full sanity-check: min/max rows, empty result, truncation, non_null_columns, non_negative_columns checks. ValidationReport surfaces warnings. SYSTEM_PROMPT mandates validate_result call before final_answer. Tests cover all validation branches (test_validator.py)."
  },
  "B3": {
    "score": 5,
    "max": 6,
    "justification": "Max iterations exit with graceful Russian message (agent.py). Unknown table returns error dict with available_tables (tools.py test_inspect_schema_unknown_table). LLM-returns-plain-text path handled. Empty question rejected in CLI. Ambiguous NL relies on LLM to clarify rather than explicit disambiguation logic, but agent doesn't loop infinitely."
  },
  "B5": {
    "score": 6,
    "max": 8,
    "justification": "Structured logging via logging module with stderr handler, configurable verbosity (__main__.py). Config fully via env vars / .env (no hardcoded creds in config.py). Proper exit codes (0/1/2). Connection uses context managers. Missing: no Dockerfile, no CI workflow, no connection pooling (short-lived connect per query), no retry logic on transient failures."
  },
  "total": 37,
  "cost_usd": 0.21547224999999998,
  "status": "ok"
}
```

## Clone preservation

`/tmp/battle-text2sql-ours-20260511T121032Z` — preserved для forensics

## Methodology

- `.claude/docs/benchmark.md` — 4-layer framework
- `.claude/benchmark/text2sql-judge/README.md` — battle-test specifics
- `.claude/benchmark/text2sql-judge/acceptance.yaml` — 100-pt rubric
