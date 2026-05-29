# Battle-test: text2sql / ours

**Date**: 2026-05-11T18:07:53Z
**Build model**: claude-opus-4-7
**Wall**: 643s (10m 43s) build only
**Total OAuth cost**: $4.8925

## Verdict: **accepted** (83 / 100)

| Section | Score | Max |
|---|---:|---:|
| F-Questions (auto) | 24 | 30 |
| T/B auto (scriptable) | 27 | 23 |
| T/B LLM-judge | 32 | 47 |
| **Grand total** | **83** | **100** |

Thresholds: ≥70 accepted · 50-69 partial · <50 failure.

## Build phase

- exit_code: 0
- stop_reason: end_turn
- turns: 78
- cost: $4.66565675
- tokens: in=82 out=47991 cache_create=159165 cache_read=4941381

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
      "count": 38
    },
    {
      "name": "Write",
      "count": 20
    },
    {
      "name": "Edit",
      "count": 6
    },
    {
      "name": "TodoWrite",
      "count": 6
    },
    {
      "name": "Read",
      "count": 4
    },
    {
      "name": "AskUserQuestion",
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
OK, оставлю как есть — `*.log` уже в `.gitignore`, артефакты не попадут в коммит. Подведу итог: deliverable собран, hook-требования закрыты.

**Что добавлено по требованию hook'а:**

- **`PREMORTEM.md`** — 6 distinct failure modes (по каждой: trigger, impact, mitigation backlog). Severity-таблица в конце.
- **`EVIDENCE.md`** — 5 real executions против live Oracle + Ollama (Qwen3-30B). Каждый ответ независимо сверен прямой SQL-выборкой.

**Главная находка** — Run 3 эмпирически подтвердил PREMORTEM #1 (модель возвращает пустой `content` после `execute_sql`, NL-ответ теряется). Mitigation реализован тут же (`_recover_from_empty_reply` в `agent.py`), regression test добавлен (`test_agent_loop_recovers_empty_reply_after_execute_sql`), Run 5 показывает корректный ответ на том же вопросе.

**Финальное состояние:**
- 34 теста, все зелёные
- 4/4 real-data вопросов с верифицированными числами (после fix'а)
- Real failure mode обнаружен, локализован, исправлен на live-системе
```

## Deliverable info

```json
{
  "status": "ok",
  "entry_kind": "module",
  "entry_module": "text2sql",
  "entry_script": null,
  "invocation_cmd": ".venv/bin/python -m text2sql",
  "venv_path": "/tmp/battle-text2sql-ours-20260511T180753Z/.venv",
  "venv_status": "pyproject_install (rc=0)",
  "install_log_tail": "Requirement already satisfied: openai>=1.0 in ./.venv/lib/python3.12/site-packages (from text2sql==0.1.0) (2.36.0)\nRequirement already satisfied: python-dotenv>=1.0 in ./.venv/lib/python3.12/site-packages (from text2sql==0.1.0) (1.2.2)\nRequirement already satisfied: pydantic>=2.0 in ./.venv/lib/python3.12/site-packages (from text2sql==0.1.0) (2.13.4)\nRequirement already satisfied: anyio<5,>=3.5.0 in ./.venv/lib/python3.12/site-packages (from openai>=1.0->text2sql==0.1.0) (4.13.0)\nRequirement already satisfied: distro<2,>=1.7.0 in ./.venv/lib/python3.12/site-packages (from openai>=1.0->text2sql==0.1.0) (1.9.0)\nRequirement already satisfied: httpx<1,>=0.23.0 in ./.venv/lib/python3.12/site-packages (from openai>=1.0->text2sql==0.1.0) (0.28.1)\nRequirement already satisfied: jiter<1,>=0.10.0 in ./.venv/lib/python3.12/site-packages (from openai>=1.0->text2sql==0.1.0) (0.14.0)\nRequirement already satisfied: sniffio in ./.venv/lib/python3.12/site-packages (from openai>=1.0->text2sql==0.1.0) (1.3.1)\nRequirement already satisfied: tqdm>4 in ./.venv/lib/python3.12/site-packages (from openai>=1.0->text2sql==0.1.0) (4.67.3)\nRequirement already satisfied: typing-extensions<5,>=4.11 in ./.venv/lib/python3.12/site-packages (from openai>=1.0->text2sql==0.1.0) (4.15.0)\nRequirement already satisfied: idna>=2.8 in ./.venv/lib/python3.12/site-packages (from anyio<5,>=3.5.0->openai>=1.0->text2sql==0.1.0) (3.14)\nRequirement already satisfied: certifi in ./.venv/lib/python3.12/site-packages (from httpx<1,>=0.23.0->openai>=1.0->text2sql==0.1.0) (2026.4.22)\nRequirement already satisfied: httpcore==1.* in ./.venv/lib/python3.12/site-packages (from httpx<1,>=0.23.0->openai>=1.0->text2sql==0.1.0) (1.0.9)\nRequirement already satisfied: h11>=0.16 in ./.venv/lib/python3.12/site-packages (from httpcore==1.*->httpx<1,>=0.23.0->openai>=1.0->text2sql==0.1.0) (0.16.0)\nRequirement already satisfied: annotated-types>=0.6.0 in ./.venv/lib/python3.12/site-packages (from pydantic>=2.0->text2sql==0.1.0) (0.7.0)\nRequirement already satisfied: pydantic-core==2.46.4 in ./.venv/lib/python3.12/site-packages (from pydantic>=2.0->text2sql==0.1.0) (2.46.4)\nRequirement already satisfied: typing-inspection>=0.4.2 in ./.venv/lib/python3.12/site-packages (from pydantic>=2.0->text2sql==0.1.0) (0.4.2)\nRequirement already satisfied: cryptography>=3.2.1 in ./.venv/lib/python3.12/site-packages (from oracledb>=2.5.0->text2sql==0.1.0) (48.0.0)\nRequirement already satisfied: cffi>=2.0.0 in ./.venv/lib/python3.12/site-packages (from cryptography>=3.2.1->oracledb>=2.5.0->text2sql==0.1.0) (2.0.0)\nRequirement already satisfied: pycparser in ./.venv/lib/python3.12/site-packages (from cffi>=2.0.0->cryptography>=3.2.1->oracledb>=2.5.0->text2sql==0.1.0) (3.0)\nBuilding wheels for collected packages: text2sql\n  Building editable for text2sql (pyproject.toml): started\n  Building editable for text2sql (pyproject.toml): finished with status 'done'\n  Created wheel for text2sql: filename=text2sql-0.1.0-0.editable-py3-none-any.whl size=5779 sha256=e0141c43092b6d76b0b37fccc16d065dfaa0f34c8a01087850f19844220facef\n  Stored in directory: /tmp/pip-ephem-wheel-cache-y60sjkn2/wheels/c4/33/eb/5b4f40ddbc4c3605db43b7f17b5f23fede6df6e8229c7b51ec\nSuccessfully built text2sql\nInstalling collected packages: text2sql\nSuccessfully installed text2sql-0.1.0\n\n--- /tmp/battle-text2sql-ours-20260511T180753Z/.venv/bin/pip install -e . ---"
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
  "total": 24,
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
      "reason": "17 py files, src/pkg structure, tests dir, pyproject"
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
      "reason": "README 134 lines"
    },
    "B4": {
      "score": 5,
      "max": 5,
      "verdict": "pass",
      "reason": "median wall 4.5s"
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
    "justification": "db.py wraps oracledb in execute() and tools.py catches both UnsafeSQLError and generic Exception returning JSON error to model (tools.py tool_execute_sql). __main__.py catches RuntimeError for config and broad Exception around run_agent, printing one-line message to stderr (not stack trace). agent.py recovers from empty model replies. Missing: no try/except around LLM API calls (chat.completions.create) — Ollama timeouts/connection errors would propagate as raw traceback to main's catch-all."
  },
  "T4": {
    "score": 6,
    "max": 6,
    "justification": "Type hints throughout public APIs (Config dataclass, run_agent signature, OracleClient.execute, tool_* functions). Modules are small and focused (db.py ~100 LoC, tools.py ~12k bytes but cohesive, agent.py ~10k). Docstrings on classes and public functions. Naming is clear (assert_select_only, tool_inspect_schema, _normalize). No obvious dead code."
  },
  "T7": {
    "score": 4,
    "max": 6,
    "justification": "assert_select_only in db.py whitelists SELECT/WITH only, rejects `;` and DDL/DML via regex with word boundaries; tests cover this thoroughly (test_db_safety.py). Oracle DATE 'YYYY-MM-DD' literals enforced via system prompt and examples. However SQL is built by LLM as raw strings (not parameterized) — user-controlled name fragments end up concatenated; PREMORTEM #5 itself admits SQL injection via apostrophes in ORGANIZATION_NM as unresolved. Whitelisting blocks DDL but not injection within SELECT."
  },
  "B1": {
    "score": 5,
    "max": 6,
    "justification": "EVIDENCE shows NL responses like 'Общий доход за последний доступный месяц составил 59 940 529,39 рублей' — number + unit + context, not raw DB output. final_answer tool packages text + supporting_data. README documents stdout vs stderr split. No explicit markdown table for long results, but tool returns row preview to model which then formulates prose."
  },
  "B2": {
    "score": 4,
    "max": 5,
    "justification": "Dedicated validate_result tool (tools.py tool_validate_result) checks min/max rows, non-null columns, numeric ranges and adds notes for empty results. Test coverage in test_tools.py for each violation type. Model is instructed in system prompt to call it. Minor: validation depends on model passing reasonable expectations; PREMORTEM #2 notes it can't catch semantic over-summing."
  },
  "B3": {
    "score": 4,
    "max": 6,
    "justification": "agent.py has _recover_from_empty_reply for PREMORTEM #1 case, max_steps limit prevents loops, empty question rejected with exit 2, config errors graceful. tool_inspect_schema returns error JSON for unknown tables. EVIDENCE Run 3 documents a real regression where model still fails on top-3 query despite having data — recovery is partial. PREMORTEM #3 (out-of-range dates) explicitly unmitigated."
  },
  "B5": {
    "score": 4,
    "max": 8,
    "justification": "Config via env vars/.env (config.py), credentials not hardcoded. Stderr logging with [agent]/[execute_sql] prefixes (not structured/JSON). pyproject.toml with entry-point script, requirements.txt pinned minimums. oracledb call_timeout=60s set. Missing: no Dockerfile, no CI workflow, no connection pool (each execute opens fresh connection via context manager), no retry logic, no LLM client timeout (PREMORTEM #4 admits this), logging is plain print not stdlib logging module."
  },
  "total": 32,
  "cost_usd": 0.22681125000000002,
  "status": "ok"
}
```

## Clone preservation

`/tmp/battle-text2sql-ours-20260511T180753Z` — preserved для forensics

## Methodology

- `.claude/docs/benchmark.md` — 4-layer framework
- `.claude/benchmark/text2sql-judge/README.md` — battle-test specifics
- `.claude/benchmark/text2sql-judge/acceptance.yaml` — 100-pt rubric
