# Battle-test: text2sql / ours

**Date**: 2026-05-11T18:29:18Z
**Build model**: claude-opus-4-7
**Wall**: 717s (11m 57s) build only
**Total OAuth cost**: $5.1422

## Verdict: **accepted** (90 / 100)

| Section | Score | Max |
|---|---:|---:|
| F-Questions (auto) | 24 | 30 |
| T/B auto (scriptable) | 27 | 23 |
| T/B LLM-judge | 39 | 47 |
| **Grand total** | **90** | **100** |

Thresholds: ≥70 accepted · 50-69 partial · <50 failure.

## Build phase

- exit_code: 0
- stop_reason: end_turn
- turns: 80
- cost: $4.895894750000001
- tokens: in=93 out=47652 cache_create=125003 cache_read=5845722

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
      "count": 36
    },
    {
      "name": "Write",
      "count": 23
    },
    {
      "name": "TodoWrite",
      "count": 10
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
Готово. Discovery-артефакты созданы:

- **`PREMORTEM.md`** — 6 различных failure modes, каждый как `##` heading с triggers (откуда возникает) и impact (как ломает grader-выход). Покрывает: trap-поле FX vs VED, Ollama format mismatch, отсутствие `final_answer` tool, edge незакрытого месяца, сетевые сбои, округление в NL-ответе.

- **`EVIDENCE.md`** — 9 реальных запусков против Oracle XE + Ollama (модель `Qwen3-30B-A3B-Instruct-2507`). Каждый run: input → output → ground-truth SQL → exit code → какая failure mode из PREMORTEM сработала или была проверена. Сырые артефакты — `evidence_runs/r*.json` и `r*.stderr`. Сводная таблица: 7/7 успешных run'ов дали верные цифры (4× exact, 2× ≈округление, 1× trap-формулировка пройдена), 2 edge-кейса (пусто, фейк-поле) обработаны корректно.
```

## Deliverable info

```json
{
  "status": "ok",
  "entry_kind": "module",
  "entry_module": "text2sql",
  "entry_script": null,
  "invocation_cmd": ".venv/bin/python -m text2sql",
  "venv_path": "/tmp/battle-text2sql-ours-20260511T182918Z/.venv",
  "venv_status": "pyproject_install (rc=0)",
  "install_log_tail": "Requirement already satisfied: openai>=1.0.0 in ./.venv/lib/python3.12/site-packages (from text2sql==0.1.0) (2.36.0)\nRequirement already satisfied: python-dotenv>=1.0.0 in ./.venv/lib/python3.12/site-packages (from text2sql==0.1.0) (1.2.2)\nRequirement already satisfied: pydantic>=2.0.0 in ./.venv/lib/python3.12/site-packages (from text2sql==0.1.0) (2.13.4)\nRequirement already satisfied: anyio<5,>=3.5.0 in ./.venv/lib/python3.12/site-packages (from openai>=1.0.0->text2sql==0.1.0) (4.13.0)\nRequirement already satisfied: distro<2,>=1.7.0 in ./.venv/lib/python3.12/site-packages (from openai>=1.0.0->text2sql==0.1.0) (1.9.0)\nRequirement already satisfied: httpx<1,>=0.23.0 in ./.venv/lib/python3.12/site-packages (from openai>=1.0.0->text2sql==0.1.0) (0.28.1)\nRequirement already satisfied: jiter<1,>=0.10.0 in ./.venv/lib/python3.12/site-packages (from openai>=1.0.0->text2sql==0.1.0) (0.14.0)\nRequirement already satisfied: sniffio in ./.venv/lib/python3.12/site-packages (from openai>=1.0.0->text2sql==0.1.0) (1.3.1)\nRequirement already satisfied: tqdm>4 in ./.venv/lib/python3.12/site-packages (from openai>=1.0.0->text2sql==0.1.0) (4.67.3)\nRequirement already satisfied: typing-extensions<5,>=4.11 in ./.venv/lib/python3.12/site-packages (from openai>=1.0.0->text2sql==0.1.0) (4.15.0)\nRequirement already satisfied: idna>=2.8 in ./.venv/lib/python3.12/site-packages (from anyio<5,>=3.5.0->openai>=1.0.0->text2sql==0.1.0) (3.14)\nRequirement already satisfied: certifi in ./.venv/lib/python3.12/site-packages (from httpx<1,>=0.23.0->openai>=1.0.0->text2sql==0.1.0) (2026.4.22)\nRequirement already satisfied: httpcore==1.* in ./.venv/lib/python3.12/site-packages (from httpx<1,>=0.23.0->openai>=1.0.0->text2sql==0.1.0) (1.0.9)\nRequirement already satisfied: h11>=0.16 in ./.venv/lib/python3.12/site-packages (from httpcore==1.*->httpx<1,>=0.23.0->openai>=1.0.0->text2sql==0.1.0) (0.16.0)\nRequirement already satisfied: annotated-types>=0.6.0 in ./.venv/lib/python3.12/site-packages (from pydantic>=2.0.0->text2sql==0.1.0) (0.7.0)\nRequirement already satisfied: pydantic-core==2.46.4 in ./.venv/lib/python3.12/site-packages (from pydantic>=2.0.0->text2sql==0.1.0) (2.46.4)\nRequirement already satisfied: typing-inspection>=0.4.2 in ./.venv/lib/python3.12/site-packages (from pydantic>=2.0.0->text2sql==0.1.0) (0.4.2)\nRequirement already satisfied: cryptography>=3.2.1 in ./.venv/lib/python3.12/site-packages (from oracledb>=2.5.0->text2sql==0.1.0) (48.0.0)\nRequirement already satisfied: cffi>=2.0.0 in ./.venv/lib/python3.12/site-packages (from cryptography>=3.2.1->oracledb>=2.5.0->text2sql==0.1.0) (2.0.0)\nRequirement already satisfied: pycparser in ./.venv/lib/python3.12/site-packages (from cffi>=2.0.0->cryptography>=3.2.1->oracledb>=2.5.0->text2sql==0.1.0) (3.0)\nBuilding wheels for collected packages: text2sql\n  Building editable for text2sql (pyproject.toml): started\n  Building editable for text2sql (pyproject.toml): finished with status 'done'\n  Created wheel for text2sql: filename=text2sql-0.1.0-0.editable-py3-none-any.whl size=6022 sha256=42ad222debb8ac4e94ca07df8fe8c770eaf4dbf51061440299ebcdcb1fd45db8\n  Stored in directory: /tmp/pip-ephem-wheel-cache-javvoy_r/wheels/a8/01/79/60ab853e8149926f33285c68093f747ff50456f0041c7e7398\nSuccessfully built text2sql\nInstalling collected packages: text2sql\nSuccessfully installed text2sql-0.1.0\n\n--- /tmp/battle-text2sql-ours-20260511T182918Z/.venv/bin/pip install -e . ---"
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
      "reason": "README 125 lines"
    },
    "B4": {
      "score": 5,
      "max": 5,
      "verdict": "pass",
      "reason": "median wall 3.3s"
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
    "justification": "try/except wrapping at multiple levels: `__main__.py` top-level guard for Agent.run, `agent.py` json.loads in try/except with bad_json_arguments handling, `tools.py` would wrap execute_sql (per evidence). UnsafeSqlError raises graceful error, validate reports issues without stack traces. Empty result triggers warnings in validate.py."
  },
  "T4": {
    "score": 6,
    "max": 6,
    "justification": "Type hints on all public functions (`Config.load`, `OracleClient.run_select`, `validate`, etc.), docstrings on modules and classes, modules well under 500 LoC (tools.py largest at ~10KB). Clear naming (Expectations, ValidationReport, ToolRegistry, AgentResult), no obvious dead code or copy-paste."
  },
  "T7": {
    "score": 5,
    "max": 6,
    "justification": "`assert_safe_select` in db.py blocks DML/DDL keywords, multi-statements, requires SELECT/WITH prefix, applied twice (in OracleClient.run_select and ToolRegistry). Prompts.py instructs Oracle DATE 'YYYY-MM-DD' literals. Whitelisting not strict (LLM generates SQL freely) but guard is robust. NL injection vector neutralized by SELECT-only enforcement."
  },
  "B1": {
    "score": 6,
    "max": 6,
    "justification": "Evidence runs show NL answers formatted as analyst messages: 'В базе зарегистрировано 103 уникальных клиента', '345,8 млн руб', top-5 with numbered list and amounts in млн руб. Prompt explicitly mandates human-readable form ('1.23 млрд руб.') with interpretation."
  },
  "B2": {
    "score": 5,
    "max": 5,
    "justification": "Dedicated `validate.py` module with Expectations (min_rows, required_columns, non_null_columns, numeric_ranges, truncated warning). System prompt mandates validate_result call before final_answer. Reports issues and warnings explicitly (all-NULL flagged as suspicious, range violations, truncation warnings)."
  },
  "B3": {
    "score": 5,
    "max": 6,
    "justification": "PREMORTEM documents 6 failure modes with mitigations. Fallback when LLM emits content without final_answer (hint message + final fallback in _build_result). max_iterations configurable via CLI. Edge cases for empty SQL, JSON parse errors handled. Run 4 shows iteration limit edge case acknowledged but resolved. Ambiguous NL handling relies on prompt — no explicit clarification step."
  },
  "B5": {
    "score": 6,
    "max": 8,
    "justification": "Logging via stdlib `logging` module across modules (info/debug levels), config exclusively via env vars / .env (no hardcoded creds), pyproject.toml + requirements.txt, CLI with --verbose and --json. Connection-per-request rather than pool, no retry logic, no Dockerfile or CI workflow present in tree, no graceful shutdown/connection-pool."
  },
  "total": 39,
  "cost_usd": 0.24630724999999998,
  "status": "ok"
}
```

## Clone preservation

`/tmp/battle-text2sql-ours-20260511T182918Z` — preserved для forensics

## Methodology

- `.claude/docs/benchmark.md` — 4-layer framework
- `.claude/benchmark/text2sql-judge/README.md` — battle-test specifics
- `.claude/benchmark/text2sql-judge/acceptance.yaml` — 100-pt rubric
