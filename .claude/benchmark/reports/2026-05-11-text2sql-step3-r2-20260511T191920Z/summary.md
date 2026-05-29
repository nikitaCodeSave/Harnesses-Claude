# Battle-test: text2sql / ours

**Date**: 2026-05-11T19:19:20Z
**Build model**: claude-opus-4-7
**Wall**: 1699s (28m 19s) build only
**Total OAuth cost**: $11.3351

## Verdict: **accepted** (92 / 100)

| Section | Score | Max |
|---|---:|---:|
| F-Questions (auto) | 27 | 30 |
| T/B auto (scriptable) | 27 | 23 |
| T/B LLM-judge | 38 | 47 |
| **Grand total** | **92** | **100** |

Thresholds: ≥70 accepted · 50-69 partial · <50 failure.

## Build phase

- exit_code: 0
- stop_reason: end_turn
- turns: 116
- cost: $11.081201499999999
- tokens: in=129 out=75311 cache_create=173426 cache_read=10961695

## Trajectory (Layer C)

```json
{
  "skills_triggered": [],
  "subagent_dispatches": {
    "count": 2,
    "types": [
      "discovery-critic"
    ]
  },
  "tool_calls_summary": [
    {
      "name": "Bash",
      "count": 69
    },
    {
      "name": "Read",
      "count": 34
    },
    {
      "name": "Write",
      "count": 22
    },
    {
      "name": "Edit",
      "count": 21
    },
    {
      "name": "TodoWrite",
      "count": 10
    },
    {
      "name": "Grep",
      "count": 5
    },
    {
      "name": "Agent",
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
Все три discovery-артефакта на месте, тесты зелёные:

**Дополнения после первого round'а критика**
- **SQL валидатор** (`db.py:_strip_strings_and_comments`) — вырезает строковые литералы и комментарии до keyword-scan; легитимные запросы вроде `LIKE '%DROP shipping%'`, `WHERE name = ';'`, `SELECT 'INSERT' FROM dual` больше не отклоняются. +4 unit-теста.
- **Message-history clipping** (`agent.py:_clip_for_history`) — обрезает rows в tool-response до 30 перед отправкой в LLM, сохраняя реальный `row_count`. Это корневая причина «budget exhausted» из Run 6 — теперь Run 6 даёт корректный ответ с топ-3 + общим count. +`TestClipForHistory`.
- **Empty `final_answer` nudge** — пустой `text=""` больше не приводит к молчаливому blank stdout, модель получает nudge и переотправляет. +1 unit-тест.
- **PREMORTEM #3** конвертирован из documented в addressed — `_data_range_note()` выполняет `SELECT MIN/MAX MONTH_DT` при старте сессии и впрыскивает реальный диапазон в системный промпт.
- **PREMORTEM #2, #10** → ACCEPT-RISK с обоснованием user-value tradeoff (за пределами bar для documented-only).
- **PREMORTEM #11** добавлен — Oracle-grant read-only role как deployment precondition; README документирует.

**Round-2 verdict:** `addressed=7 documented=2 new_critical=0 new_major=0 evidence=high` — gate проходит.

40/40 тестов зелёные. End-to-end на 5+ NL-вопросах работает.
```

## Deliverable info

```json
{
  "status": "ok",
  "entry_kind": "module",
  "entry_module": "text2sql_agent",
  "entry_script": null,
  "invocation_cmd": ".venv/bin/python -m text2sql_agent",
  "venv_path": "/tmp/battle-text2sql-ours-20260511T191920Z/.venv",
  "venv_status": "pyproject_install (rc=0)",
  "install_log_tail": "Requirement already satisfied: openai>=1.0 in ./.venv/lib/python3.12/site-packages (from text2sql-agent==0.1.0) (2.36.0)\nRequirement already satisfied: python-dotenv>=1.0 in ./.venv/lib/python3.12/site-packages (from text2sql-agent==0.1.0) (1.2.2)\nRequirement already satisfied: anyio<5,>=3.5.0 in ./.venv/lib/python3.12/site-packages (from openai>=1.0->text2sql-agent==0.1.0) (4.13.0)\nRequirement already satisfied: distro<2,>=1.7.0 in ./.venv/lib/python3.12/site-packages (from openai>=1.0->text2sql-agent==0.1.0) (1.9.0)\nRequirement already satisfied: httpx<1,>=0.23.0 in ./.venv/lib/python3.12/site-packages (from openai>=1.0->text2sql-agent==0.1.0) (0.28.1)\nRequirement already satisfied: jiter<1,>=0.10.0 in ./.venv/lib/python3.12/site-packages (from openai>=1.0->text2sql-agent==0.1.0) (0.14.0)\nRequirement already satisfied: pydantic<3,>=1.9.0 in ./.venv/lib/python3.12/site-packages (from openai>=1.0->text2sql-agent==0.1.0) (2.13.4)\nRequirement already satisfied: sniffio in ./.venv/lib/python3.12/site-packages (from openai>=1.0->text2sql-agent==0.1.0) (1.3.1)\nRequirement already satisfied: tqdm>4 in ./.venv/lib/python3.12/site-packages (from openai>=1.0->text2sql-agent==0.1.0) (4.67.3)\nRequirement already satisfied: typing-extensions<5,>=4.11 in ./.venv/lib/python3.12/site-packages (from openai>=1.0->text2sql-agent==0.1.0) (4.15.0)\nRequirement already satisfied: idna>=2.8 in ./.venv/lib/python3.12/site-packages (from anyio<5,>=3.5.0->openai>=1.0->text2sql-agent==0.1.0) (3.14)\nRequirement already satisfied: certifi in ./.venv/lib/python3.12/site-packages (from httpx<1,>=0.23.0->openai>=1.0->text2sql-agent==0.1.0) (2026.4.22)\nRequirement already satisfied: httpcore==1.* in ./.venv/lib/python3.12/site-packages (from httpx<1,>=0.23.0->openai>=1.0->text2sql-agent==0.1.0) (1.0.9)\nRequirement already satisfied: h11>=0.16 in ./.venv/lib/python3.12/site-packages (from httpcore==1.*->httpx<1,>=0.23.0->openai>=1.0->text2sql-agent==0.1.0) (0.16.0)\nRequirement already satisfied: annotated-types>=0.6.0 in ./.venv/lib/python3.12/site-packages (from pydantic<3,>=1.9.0->openai>=1.0->text2sql-agent==0.1.0) (0.7.0)\nRequirement already satisfied: pydantic-core==2.46.4 in ./.venv/lib/python3.12/site-packages (from pydantic<3,>=1.9.0->openai>=1.0->text2sql-agent==0.1.0) (2.46.4)\nRequirement already satisfied: typing-inspection>=0.4.2 in ./.venv/lib/python3.12/site-packages (from pydantic<3,>=1.9.0->openai>=1.0->text2sql-agent==0.1.0) (0.4.2)\nRequirement already satisfied: cryptography>=3.2.1 in ./.venv/lib/python3.12/site-packages (from oracledb>=2.5.0->text2sql-agent==0.1.0) (48.0.0)\nRequirement already satisfied: cffi>=2.0.0 in ./.venv/lib/python3.12/site-packages (from cryptography>=3.2.1->oracledb>=2.5.0->text2sql-agent==0.1.0) (2.0.0)\nRequirement already satisfied: pycparser in ./.venv/lib/python3.12/site-packages (from cffi>=2.0.0->cryptography>=3.2.1->oracledb>=2.5.0->text2sql-agent==0.1.0) (3.0)\nBuilding wheels for collected packages: text2sql-agent\n  Building editable for text2sql-agent (pyproject.toml): started\n  Building editable for text2sql-agent (pyproject.toml): finished with status 'done'\n  Created wheel for text2sql-agent: filename=text2sql_agent-0.1.0-0.editable-py3-none-any.whl size=3166 sha256=5116a7627d1ac6cb4c76c89795702838501c4626a9dc92d50fc4b66bde7b750c\n  Stored in directory: /tmp/pip-ephem-wheel-cache-d_aode2t/wheels/a0/2a/24/d197e70f7ee654a29ac2923939f2e0e2d8add03690008cb6dc\nSuccessfully built text2sql-agent\nInstalling collected packages: text2sql-agent\nSuccessfully installed text2sql-agent-0.1.0\n\n--- /tmp/battle-text2sql-ours-20260511T191920Z/.venv/bin/pip install -e . ---"
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
      "score": 8,
      "max": 8,
      "verdict": "pass",
      "reason": "4 test files, pytest passes"
    },
    "T6": {
      "score": 4,
      "max": 4,
      "verdict": "pass",
      "reason": "README 162 lines"
    },
    "B4": {
      "score": 5,
      "max": 5,
      "verdict": "pass",
      "reason": "median wall 5.7s"
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
    "justification": "Oracle errors wrapped in SqlExecutionError (db.py) and returned to model as {\"error\":...} via tools.py:execute_sql; __main__.main has top-level try/except returning exit code 1 (text2sql_agent/__main__.py); _data_range_note swallows failures gracefully; empty/null results produce honest 'no data' answers (EVIDENCE Run 4)."
  },
  "T4": {
    "score": 5,
    "max": 6,
    "justification": "Type hints throughout public API (Settings, Text2SqlAgent, tools), modular layout (agent.py, db.py, tools.py, schema.py, config.py) each well under 500 LoC, docstrings on classes/functions; minor smell: __import__('re') used in db.py module-level constants instead of normal import."
  },
  "T7": {
    "score": 5,
    "max": 6,
    "justification": "_validate_sql in db.py:120-144 whitelists SELECT/WITH only, scrubs string literals + comments before keyword scan, rejects multi-statements and forbidden DML keywords; SQL passed as single string to cur.execute (not parameterized but read-only by validator); CRITIC notes Oracle q-quote literal edge case as minor residual."
  },
  "B1": {
    "score": 6,
    "max": 6,
    "justification": "Final answers formatted as analyst messages with number + unit + context (e.g. '345,8 млн ₽' Run 2, '103 уникальных клиента' Run 1); system prompt mandates formatting with separators and units; final_answer tool packs text + supporting_data dict."
  },
  "B2": {
    "score": 5,
    "max": 5,
    "justification": "validate_result tool (tools.py) checks min_rows/max_rows, non_null_columns, numeric_ranges, truncation flag, and SQL errors; emits issues vs warnings distinction; agent flow uses it as step before final_answer (EVIDENCE Run 1 step 3)."
  },
  "B3": {
    "score": 5,
    "max": 6,
    "justification": "Out-of-range dates handled gracefully (Run 4 '2026' → 'нет данных'); empty model response triggers nudge logic (agent.py:151-165, tested); unknown table → {error:...}; DML in NL rejected at two layers (Run 3). PREMORTEM #3 partial-range case acknowledged as not flagged by model (Run 2 H1 only)."
  },
  "B5": {
    "score": 6,
    "max": 8,
    "justification": "Config via env vars with Settings.from_env() listing missing vars; .env loading via python-dotenv; stderr structured logging via _log; pyproject.toml with script entry-point; tests with live-skip fixtures; README documents read-only Oracle grant requirements. Missing: no Dockerfile, no CI workflow, no connection pool (connection-per-query), no retry logic, logs are plain prints not structured JSON."
  },
  "total": 38,
  "cost_usd": 0.253927,
  "status": "ok"
}
```

## Clone preservation

`/tmp/battle-text2sql-ours-20260511T191920Z` — preserved для forensics

## Methodology

- `.claude/docs/benchmark.md` — 4-layer framework
- `.claude/benchmark/text2sql-judge/README.md` — battle-test specifics
- `.claude/benchmark/text2sql-judge/acceptance.yaml` — 100-pt rubric
