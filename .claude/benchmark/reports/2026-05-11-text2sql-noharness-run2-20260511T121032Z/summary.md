# Battle-test: text2sql / noharness

**Date**: 2026-05-11T12:28:01Z
**Build model**: claude-opus-4-7
**Wall**: 396s (6m 36s) build only
**Total OAuth cost**: $2.8025

## Verdict: **accepted** (81 / 100)

| Section | Score | Max |
|---|---:|---:|
| F-Questions (auto) | 18 | 30 |
| T/B auto (scriptable) | 27 | 23 |
| T/B LLM-judge | 36 | 47 |
| **Grand total** | **81** | **100** |

Thresholds: ≥70 accepted · 50-69 partial · <50 failure.

## Build phase

- exit_code: 0
- stop_reason: end_turn
- turns: 46
- cost: $2.6133990000000002
- tokens: in=55 out=29458 cache_create=89570 cache_read=2630891

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
      "count": 18
    },
    {
      "name": "Bash",
      "count": 16
    },
    {
      "name": "TodoWrite",
      "count": 5
    },
    {
      "name": "Edit",
      "count": 3
    },
    {
      "name": "Read",
      "count": 2
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
Готово. Резюме:

**Что собрано**
- Пакет `text2sql/`: `config`, `db`, `schema`, `validate`, `tools`, `agent`, `__main__`.
- Агентский цикл на OpenAI tool calling: модель сама выбирает шаги через `inspect_schema` / `execute_sql` / `validate_result` / `final_answer`. Лимит шагов = 12.
- Защитные политики: только SELECT/WITH, запрет цепочек statement'ов, обработка ошибок как сообщений в loop (агент сам исправляется), усечение крупных результатов.
- Оба entry-point соглашения работают: `python -m text2sql "…"` и `python main.py "…"`. Финальный NL-ответ — единственный stdout-print; диагностика в stderr (флаг `-v` для SQL trace).
- 28 unit-тестов, не требующих БД/LLM: SQL-валидация, sanity-проверки, цикл агента на `FakeLLM`+`FakeOracle`, целостность metadata.
- `pyproject.toml` на чистом setuptools (без uv), `requirements.txt`, `README.md` с описанием архитектуры и API.

**End-to-end проверено на реальной БД и Ollama**
- «Сколько уникальных клиентов?» → 103.
- «Доход за 2025 год?» → 345,8 млн руб.
- «Активных клиентов за последний месяц?» → 82 за июнь 2025.
```

## Deliverable info

```json
{
  "status": "ok",
  "entry_kind": "module",
  "entry_module": "text2sql",
  "entry_script": null,
  "invocation_cmd": ".venv/bin/python -m text2sql",
  "venv_path": "/tmp/battle-text2sql-noharness-20260511T122801Z/.venv",
  "venv_status": "pyproject_install (rc=0)",
  "install_log_tail": "Requirement already satisfied: httpx<1,>=0.23.0 in ./.venv/lib/python3.12/site-packages (from openai>=1.30.0->text2sql==0.1.0) (0.28.1)\nRequirement already satisfied: jiter<1,>=0.10.0 in ./.venv/lib/python3.12/site-packages (from openai>=1.30.0->text2sql==0.1.0) (0.14.0)\nRequirement already satisfied: pydantic<3,>=1.9.0 in ./.venv/lib/python3.12/site-packages (from openai>=1.30.0->text2sql==0.1.0) (2.13.4)\nRequirement already satisfied: sniffio in ./.venv/lib/python3.12/site-packages (from openai>=1.30.0->text2sql==0.1.0) (1.3.1)\nRequirement already satisfied: tqdm>4 in ./.venv/lib/python3.12/site-packages (from openai>=1.30.0->text2sql==0.1.0) (4.67.3)\nRequirement already satisfied: typing-extensions<5,>=4.11 in ./.venv/lib/python3.12/site-packages (from openai>=1.30.0->text2sql==0.1.0) (4.15.0)\nRequirement already satisfied: idna>=2.8 in ./.venv/lib/python3.12/site-packages (from anyio<5,>=3.5.0->openai>=1.30.0->text2sql==0.1.0) (3.14)\nRequirement already satisfied: certifi in ./.venv/lib/python3.12/site-packages (from httpx<1,>=0.23.0->openai>=1.30.0->text2sql==0.1.0) (2026.4.22)\nRequirement already satisfied: httpcore==1.* in ./.venv/lib/python3.12/site-packages (from httpx<1,>=0.23.0->openai>=1.30.0->text2sql==0.1.0) (1.0.9)\nRequirement already satisfied: h11>=0.16 in ./.venv/lib/python3.12/site-packages (from httpcore==1.*->httpx<1,>=0.23.0->openai>=1.30.0->text2sql==0.1.0) (0.16.0)\nRequirement already satisfied: annotated-types>=0.6.0 in ./.venv/lib/python3.12/site-packages (from pydantic<3,>=1.9.0->openai>=1.30.0->text2sql==0.1.0) (0.7.0)\nRequirement already satisfied: pydantic-core==2.46.4 in ./.venv/lib/python3.12/site-packages (from pydantic<3,>=1.9.0->openai>=1.30.0->text2sql==0.1.0) (2.46.4)\nRequirement already satisfied: typing-inspection>=0.4.2 in ./.venv/lib/python3.12/site-packages (from pydantic<3,>=1.9.0->openai>=1.30.0->text2sql==0.1.0) (0.4.2)\nRequirement already satisfied: cryptography>=3.2.1 in ./.venv/lib/python3.12/site-packages (from oracledb>=2.5.0->text2sql==0.1.0) (48.0.0)\nRequirement already satisfied: cffi>=2.0.0 in ./.venv/lib/python3.12/site-packages (from cryptography>=3.2.1->oracledb>=2.5.0->text2sql==0.1.0) (2.0.0)\nRequirement already satisfied: pycparser in ./.venv/lib/python3.12/site-packages (from cffi>=2.0.0->cryptography>=3.2.1->oracledb>=2.5.0->text2sql==0.1.0) (3.0)\nBuilding wheels for collected packages: text2sql\n  Building editable for text2sql (pyproject.toml): started\n  Building editable for text2sql (pyproject.toml): finished with status 'done'\n  Created wheel for text2sql: filename=text2sql-0.1.0-0.editable-py3-none-any.whl size=6190 sha256=b02a2801107b359aca4d88c01e019bc881980d753cf383b1fc99cc369f18dc61\n  Stored in directory: /tmp/pip-ephem-wheel-cache-4r80spdb/wheels/00/99/8f/0ce8baede7f60c6b2d5e3aca164e4d0dd811106ae510db6e98\nSuccessfully built text2sql\nInstalling collected packages: text2sql\n  Attempting uninstall: text2sql\n    Found existing installation: text2sql 0.1.0\n    Uninstalling text2sql-0.1.0:\n      Successfully uninstalled text2sql-0.1.0\nSuccessfully installed text2sql-0.1.0\n\n--- /tmp/battle-text2sql-noharness-20260511T122801Z/.venv/bin/pip install -e . ---"
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
      "score": 0,
      "max": 6,
      "verdict": "fail",
      "reason": "neither СМИРНОВ nor 2-clients found"
    },
    "Q5": {
      "score": 6,
      "max": 6,
      "verdict": "pass",
      "reason": "all 6 hubs within ±1"
    }
  },
  "total": 18,
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
      "reason": "15 py files, src/pkg structure, tests dir, pyproject"
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
      "reason": "4 test files, pytest passes"
    },
    "T6": {
      "score": 4,
      "max": 4,
      "verdict": "pass",
      "reason": "README 160 lines"
    },
    "B4": {
      "score": 5,
      "max": 5,
      "verdict": "pass",
      "reason": "median wall 5.5s"
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
    "justification": "agent.py wraps oracledb/validate errors in try/except returning structured {error, message} to LLM; __main__.py catches init/exec exceptions printing to stderr. Missing explicit handling around LLM API call (chat.completions.create) — uncaught network/API errors would propagate."
  },
  "T4": {
    "score": 6,
    "max": 6,
    "justification": "Comprehensive type hints on public funcs/classes (config.py, db.py, agent.py, validate.py), docstrings on modules/classes/functions, clear naming, modules well under 500 LoC, no obvious dead code."
  },
  "T7": {
    "score": 5,
    "max": 6,
    "justification": "validate_select enforces SELECT/WITH-only and rejects DDL/DML and statement chains (db.py:18-49). System prompt mandates DATE 'YYYY-MM-DD' literals. Generated SQL is interpolated by LLM (not parameterized), but whitelist policy mitigates injection vector. No explicit field whitelist against metadata.py."
  },
  "B1": {
    "score": 5,
    "max": 6,
    "justification": "System prompt explicitly requires NL answer with concrete numbers, units (руб./млн руб.), thousand separators, and brief interpretation; final_answer tool defined accordingly. No explicit markdown table rendering for long results — relies entirely on LLM compliance."
  },
  "B2": {
    "score": 5,
    "max": 5,
    "justification": "Dedicated validate_result tool (validate.py) checks min/max rows, non-null columns, value ranges, expected columns; system prompt instructs agent to invoke it on suspicious results. Tested in test_validate_result.py."
  },
  "B3": {
    "score": 5,
    "max": 6,
    "justification": "Agent loop recovers from SQL errors (test_agent_recovers_from_sql_error), supports plain-text termination fallback, has max_agent_steps=12 to prevent loops, validates inputs gracefully. Ambiguous NL handling delegated to LLM with no explicit clarification tool."
  },
  "B5": {
    "score": 5,
    "max": 8,
    "justification": "Config via env vars/.env (config.py), _required() raises on missing creds, basic stderr logging via _tool_log, max_rows/max_steps limits, AgentTrace for observability. Missing: Dockerfile, CI workflow, structured logging, connection pooling, retry/backoff on transient failures."
  },
  "total": 36,
  "cost_usd": 0.1891255,
  "status": "ok"
}
```

## Clone preservation

`/tmp/battle-text2sql-noharness-20260511T122801Z` — preserved для forensics

## Methodology

- `.claude/docs/benchmark.md` — 4-layer framework
- `.claude/benchmark/text2sql-judge/README.md` — battle-test specifics
- `.claude/benchmark/text2sql-judge/acceptance.yaml` — 100-pt rubric
