# Battle-test: text2sql / noharness

**Date**: 2026-05-11T12:35:26Z
**Build model**: claude-opus-4-7
**Wall**: 586s (9m 46s) build only
**Total OAuth cost**: $4.4679

## Verdict: **accepted** (87 / 100)

| Section | Score | Max |
|---|---:|---:|
| F-Questions (auto) | 27 | 30 |
| T/B auto (scriptable) | 23 | 23 |
| T/B LLM-judge | 37 | 47 |
| **Grand total** | **87** | **100** |

Thresholds: ≥70 accepted · 50-69 partial · <50 failure.

## Build phase

- exit_code: 0
- stop_reason: end_turn
- turns: 72
- cost: $4.2383282499999995
- tokens: in=81 out=42569 cache_create=113237 cache_read=4929122

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
      "count": 31
    },
    {
      "name": "Write",
      "count": 21
    },
    {
      "name": "Edit",
      "count": 7
    },
    {
      "name": "TodoWrite",
      "count": 7
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
Готово. Краткая сводка по проделанной работе:

**Архитектура (`ai_analyst/`)**
- `agent.py` — цикл tool-calling (max 12 ходов), сам определяет последовательность. При старте делает 1 SQL-probe `MIN/MAX(MONTH_DT)` и закрепляет реальный horizon в system prompt — это убрало основную галлюцинацию (модель ставила в нарратив «текущую» дату из своего мира).
- `tools.py` — 4 tool'а с OpenAI-схемами: `inspect_schema`, `execute_sql`, `validate_result`, `final_answer`.
- `db.py` — `OracleClient` с жёсткой read-only защитой (`assert_read_only` блокирует DDL/DML/multi-statement) и нормализацией Date/Decimal/LOB → JSON-сериализуемые типы.
- `validators.py` — sanity-check (min_rows / non_null / non_negative / value_ranges).
- `schema.py`, `prompts.py`, `config.py`, `llm.py` — обёртки.

**Entry-points** — оба требуемых работают: `python -m ai_analyst "..."` и `python main.py "..."`. Финальный NL-ответ — на stdout (`--quiet` глушит stderr), exit 0 при успехе.

**Тесты** — 37 unit-тестов, все проходят. Не требуют ни Oracle, ни Ollama: oracle мокается через `_FakeOracle`, LLM — через `_ScriptedLLM` со скриптом ответов.

**Smoke-проверка end-to-end на 4 запросах** (ответы сверены с прямым SQL):
- "Сколько уникальных клиентов?" → 103 ✓
- "Общий доход за 2025?" → 345 802 507,40 руб. ✓
- "Топ-5 за последний месяц" → 5 организаций с точными суммами ✓
- "Объём ВЭД за 2025?" → 21 152 034 931,69 руб. ✓

**Env-convention** соблюдё
```

## Deliverable info

```json
{
  "status": "ok",
  "entry_kind": "module",
  "entry_module": "ai_analyst",
  "entry_script": null,
  "invocation_cmd": ".venv/bin/python -m ai_analyst",
  "venv_path": "/tmp/battle-text2sql-noharness-20260511T123526Z/.venv",
  "venv_status": "pyproject_install (rc=0)",
  "install_log_tail": "Requirement already satisfied: openai>=1.0 in ./.venv/lib/python3.12/site-packages (from ai_analyst==0.1.0) (2.36.0)\nRequirement already satisfied: python-dotenv>=1.0.0 in ./.venv/lib/python3.12/site-packages (from ai_analyst==0.1.0) (1.2.2)\nRequirement already satisfied: anyio<5,>=3.5.0 in ./.venv/lib/python3.12/site-packages (from openai>=1.0->ai_analyst==0.1.0) (4.13.0)\nRequirement already satisfied: distro<2,>=1.7.0 in ./.venv/lib/python3.12/site-packages (from openai>=1.0->ai_analyst==0.1.0) (1.9.0)\nRequirement already satisfied: httpx<1,>=0.23.0 in ./.venv/lib/python3.12/site-packages (from openai>=1.0->ai_analyst==0.1.0) (0.28.1)\nRequirement already satisfied: jiter<1,>=0.10.0 in ./.venv/lib/python3.12/site-packages (from openai>=1.0->ai_analyst==0.1.0) (0.14.0)\nRequirement already satisfied: pydantic<3,>=1.9.0 in ./.venv/lib/python3.12/site-packages (from openai>=1.0->ai_analyst==0.1.0) (2.13.4)\nRequirement already satisfied: sniffio in ./.venv/lib/python3.12/site-packages (from openai>=1.0->ai_analyst==0.1.0) (1.3.1)\nRequirement already satisfied: tqdm>4 in ./.venv/lib/python3.12/site-packages (from openai>=1.0->ai_analyst==0.1.0) (4.67.3)\nRequirement already satisfied: typing-extensions<5,>=4.11 in ./.venv/lib/python3.12/site-packages (from openai>=1.0->ai_analyst==0.1.0) (4.15.0)\nRequirement already satisfied: idna>=2.8 in ./.venv/lib/python3.12/site-packages (from anyio<5,>=3.5.0->openai>=1.0->ai_analyst==0.1.0) (3.14)\nRequirement already satisfied: certifi in ./.venv/lib/python3.12/site-packages (from httpx<1,>=0.23.0->openai>=1.0->ai_analyst==0.1.0) (2026.4.22)\nRequirement already satisfied: httpcore==1.* in ./.venv/lib/python3.12/site-packages (from httpx<1,>=0.23.0->openai>=1.0->ai_analyst==0.1.0) (1.0.9)\nRequirement already satisfied: h11>=0.16 in ./.venv/lib/python3.12/site-packages (from httpcore==1.*->httpx<1,>=0.23.0->openai>=1.0->ai_analyst==0.1.0) (0.16.0)\nRequirement already satisfied: annotated-types>=0.6.0 in ./.venv/lib/python3.12/site-packages (from pydantic<3,>=1.9.0->openai>=1.0->ai_analyst==0.1.0) (0.7.0)\nRequirement already satisfied: pydantic-core==2.46.4 in ./.venv/lib/python3.12/site-packages (from pydantic<3,>=1.9.0->openai>=1.0->ai_analyst==0.1.0) (2.46.4)\nRequirement already satisfied: typing-inspection>=0.4.2 in ./.venv/lib/python3.12/site-packages (from pydantic<3,>=1.9.0->openai>=1.0->ai_analyst==0.1.0) (0.4.2)\nRequirement already satisfied: cryptography>=3.2.1 in ./.venv/lib/python3.12/site-packages (from oracledb>=2.5.0->ai_analyst==0.1.0) (48.0.0)\nRequirement already satisfied: cffi>=2.0.0 in ./.venv/lib/python3.12/site-packages (from cryptography>=3.2.1->oracledb>=2.5.0->ai_analyst==0.1.0) (2.0.0)\nRequirement already satisfied: pycparser in ./.venv/lib/python3.12/site-packages (from cffi>=2.0.0->cryptography>=3.2.1->oracledb>=2.5.0->ai_analyst==0.1.0) (3.0)\nBuilding wheels for collected packages: ai_analyst\n  Building editable for ai_analyst (pyproject.toml): started\n  Building editable for ai_analyst (pyproject.toml): finished with status 'done'\n  Created wheel for ai_analyst: filename=ai_analyst-0.1.0-0.editable-py3-none-any.whl size=3129 sha256=e9e804994b2e8178fe97c035992ad7acaf7c356435fa1dc647158c601bbb9361\n  Stored in directory: /tmp/pip-ephem-wheel-cache-681wt9c6/wheels/f2/3b/18/16fbe69a19906344c93d4403674ed38e0830464267e18caed5\nSuccessfully built ai_analyst\nInstalling collected packages: ai_analyst\nSuccessfully installed ai_analyst-0.1.0\n\n--- /tmp/battle-text2sql-noharness-20260511T123526Z/.venv/bin/pip install -e . ---"
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
      "reason": "18 py files, src/pkg structure, tests dir, pyproject"
    },
    "T2": {
      "score": 4,
      "max": 4,
      "verdict": "pass",
      "reason": "oracledb + openai with version constraints"
    },
    "T5": {
      "score": 4,
      "max": 8,
      "verdict": "partial",
      "reason": "5 test files, pytest exit=2"
    },
    "T6": {
      "score": 4,
      "max": 4,
      "verdict": "pass",
      "reason": "README 137 lines"
    },
    "B4": {
      "score": 5,
      "max": 5,
      "verdict": "pass",
      "reason": "median wall 3.3s"
    }
  },
  "total": 23,
  "max": 27
}
```

## LLM-judge scores

```json
{
  "T3": {
    "score": 6,
    "max": 6,
    "justification": "agent.py wraps oracle.connect() and llm.chat() in try/except returning graceful AgentResult with error messages (not stack traces); tools.py tool_execute_sql catches DB errors as dict; db.py raises UnsafeSqlError on bad SQL; agent recognizes empty results and nudges model to re-query rather than fabricate."
  },
  "T4": {
    "score": 6,
    "max": 6,
    "justification": "Consistent type hints on all public functions (Agent.run, OracleClient.execute, validate, etc.), dataclasses used cleanly, docstrings on classes and modules, all modules under 500 LoC, descriptive naming (UnsafeSqlError, _normalize_cell, ToolContext), no obvious dead code."
  },
  "T7": {
    "score": 6,
    "max": 6,
    "justification": "db.py assert_read_only whitelists SELECT/WITH and blocks DDL/DML/multi-statement via regex; prompt.py rule 4 mandates Oracle DATE 'YYYY-MM-DD' literals and rule 6 uses UPPER()...LIKE pattern; SQL is constructed by LLM from metadata-driven schema rather than NL string concatenation."
  },
  "B1": {
    "score": 5,
    "max": 6,
    "justification": "final_answer prompt requires concrete numbers with units (руб, шт, мес) and 1-3 sentence interpretation (prompts.py rule 9); supporting_data carries structured data separately; however no explicit markdown-table handling for long results — relies on LLM judgement."
  },
  "B2": {
    "score": 5,
    "max": 5,
    "justification": "Dedicated validators.py with validate() checking min/max rows, non_null_columns, value_ranges, non_negative_columns; exposed as validate_result tool; prompt rule 8 instructs to check empty/NaN and rebuild SQL; agent._probe_data_range pins date range to prevent hallucination."
  },
  "B3": {
    "score": 5,
    "max": 6,
    "justification": "MAX_TURNS=12 prevents infinite loops; empty question handled explicitly; text-only LLM response is nudged toward tool calls (test_handles_text_only_response_by_nudging); data range probed upfront to avoid date hallucinations; clarification of ambiguous NL not explicitly implemented — relies on prompt instruction."
  },
  "B5": {
    "score": 4,
    "max": 8,
    "justification": "Config via env vars with .env (config.py from_env), diagnostic logging to stderr (_log), CLI with --quiet/--max-turns, OracleClient context manager for graceful close, request timeout/retries on LLM client; but no structured logging, no Dockerfile, no CI workflow, no connection pooling, no retry on transient Oracle errors."
  },
  "total": 37,
  "cost_usd": 0.22963925,
  "status": "ok"
}
```

## Clone preservation

`/tmp/battle-text2sql-noharness-20260511T123526Z` — preserved для forensics

## Methodology

- `.claude/docs/benchmark.md` — 4-layer framework
- `.claude/benchmark/text2sql-judge/README.md` — battle-test specifics
- `.claude/benchmark/text2sql-judge/acceptance.yaml` — 100-pt rubric
