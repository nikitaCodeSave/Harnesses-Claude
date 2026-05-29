# Battle-test: text2sql / ours

**Date**: 2026-05-11T11:12:38Z
**Build model**: claude-opus-4-7
**Wall**: 426s (7m 6s) build only
**Total OAuth cost**: $3.1966

## Verdict: **partial** (51 / 100)

| Section | Score | Max |
|---|---:|---:|
| F-Questions (auto) | 24 | 30 |
| T/B auto (scriptable) | 27 | 23 |
| T/B LLM-judge | 0 | 47 |
| **Grand total** | **51** | **100** |

Thresholds: ≥70 accepted · 50-69 partial · <50 failure.

## Build phase

- exit_code: 0
- stop_reason: end_turn
- turns: 50
- cost: $3.196579249999999
- tokens: in=59 out=32253 cache_create=124001 cache_read=3229906

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
      "count": 24
    },
    {
      "name": "Write",
      "count": 15
    },
    {
      "name": "TodoWrite",
      "count": 5
    },
    {
      "name": "Edit",
      "count": 2
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
Готово. Что собрано:

**Структура** (flat-layout, чтобы `metadata.py` оставался в корне и импортировался напрямую):
- `text2sql/` — пакет: `config`, `db`, `llm`, `tools`, `agent`, `__main__`
- `main.py` — альтернативный entry-point (`python main.py "..."`)
- `tests/` — 32 теста, проходят без живых Oracle/Ollama
- `pyproject.toml` + `requirements.txt` (setuptools, без uv)

**Агент**:
- 4 tools через OpenAI tool calling: `inspect_schema`, `execute_sql`, `validate_result`, `final_answer`
- Свободный порядок — модель сама выбирает шаг
- Лимиты: 12 итераций, 6 попыток SQL, 200 строк на запрос
- Fallback на plain-text если модель не дёрнула `final_answer` (Qwen так и делает)

**Безопасность**:
- `assert_select_only` блокирует DDL/DML/multistatement по regex
- Лимит rows + truncation flag

**Проверено end-to-end** против живого Oracle XE + Qwen3 30B на 4 разных вопросах:
- `сколько уникальных клиентов` → 103 ✓
- `топ-3 по доходу за 2025` → АО АГРОКОРП 25.03М / КОСМОСИНДУСТРИЯ 24.72М / СТАЛЬПРОМ 18.23М ✓
- `объём FX EUR за последний месяц` → 3 683 642 547.58 ₽ ✓
- `активные клиенты за последний месяц` → 82 (после правки промпта — модель сначала выдумала `CLOSE_DT IS NULL` дав 92, но в схеме есть `ACT_1M`; добавил в system prompt правило "не изобретать эвристики при наличии прямого поля")

**Запуск**: `python main.py "вопрос"` или `python -m text2sql "вопрос"`. Финальный ответ — последний
```

## Deliverable info

```json
{
  "status": "ok",
  "entry_kind": "module",
  "entry_module": "text2sql",
  "entry_script": null,
  "invocation_cmd": ".venv/bin/python -m text2sql",
  "venv_path": "/tmp/battle-text2sql-ours-20260511T111238Z/.venv",
  "venv_status": "pyproject_install (rc=0)",
  "install_log_tail": "Requirement already satisfied: openai>=1.0 in ./.venv/lib/python3.12/site-packages (from text2sql==0.1.0) (2.36.0)\nRequirement already satisfied: python-dotenv>=1.0 in ./.venv/lib/python3.12/site-packages (from text2sql==0.1.0) (1.2.2)\nRequirement already satisfied: pydantic>=2.0 in ./.venv/lib/python3.12/site-packages (from text2sql==0.1.0) (2.13.4)\nRequirement already satisfied: anyio<5,>=3.5.0 in ./.venv/lib/python3.12/site-packages (from openai>=1.0->text2sql==0.1.0) (4.13.0)\nRequirement already satisfied: distro<2,>=1.7.0 in ./.venv/lib/python3.12/site-packages (from openai>=1.0->text2sql==0.1.0) (1.9.0)\nRequirement already satisfied: httpx<1,>=0.23.0 in ./.venv/lib/python3.12/site-packages (from openai>=1.0->text2sql==0.1.0) (0.28.1)\nRequirement already satisfied: jiter<1,>=0.10.0 in ./.venv/lib/python3.12/site-packages (from openai>=1.0->text2sql==0.1.0) (0.14.0)\nRequirement already satisfied: sniffio in ./.venv/lib/python3.12/site-packages (from openai>=1.0->text2sql==0.1.0) (1.3.1)\nRequirement already satisfied: tqdm>4 in ./.venv/lib/python3.12/site-packages (from openai>=1.0->text2sql==0.1.0) (4.67.3)\nRequirement already satisfied: typing-extensions<5,>=4.11 in ./.venv/lib/python3.12/site-packages (from openai>=1.0->text2sql==0.1.0) (4.15.0)\nRequirement already satisfied: idna>=2.8 in ./.venv/lib/python3.12/site-packages (from anyio<5,>=3.5.0->openai>=1.0->text2sql==0.1.0) (3.14)\nRequirement already satisfied: certifi in ./.venv/lib/python3.12/site-packages (from httpx<1,>=0.23.0->openai>=1.0->text2sql==0.1.0) (2026.4.22)\nRequirement already satisfied: httpcore==1.* in ./.venv/lib/python3.12/site-packages (from httpx<1,>=0.23.0->openai>=1.0->text2sql==0.1.0) (1.0.9)\nRequirement already satisfied: h11>=0.16 in ./.venv/lib/python3.12/site-packages (from httpcore==1.*->httpx<1,>=0.23.0->openai>=1.0->text2sql==0.1.0) (0.16.0)\nRequirement already satisfied: annotated-types>=0.6.0 in ./.venv/lib/python3.12/site-packages (from pydantic>=2.0->text2sql==0.1.0) (0.7.0)\nRequirement already satisfied: pydantic-core==2.46.4 in ./.venv/lib/python3.12/site-packages (from pydantic>=2.0->text2sql==0.1.0) (2.46.4)\nRequirement already satisfied: typing-inspection>=0.4.2 in ./.venv/lib/python3.12/site-packages (from pydantic>=2.0->text2sql==0.1.0) (0.4.2)\nRequirement already satisfied: cryptography>=3.2.1 in ./.venv/lib/python3.12/site-packages (from oracledb>=2.5.0->text2sql==0.1.0) (48.0.0)\nRequirement already satisfied: cffi>=2.0.0 in ./.venv/lib/python3.12/site-packages (from cryptography>=3.2.1->oracledb>=2.5.0->text2sql==0.1.0) (2.0.0)\nRequirement already satisfied: pycparser in ./.venv/lib/python3.12/site-packages (from cffi>=2.0.0->cryptography>=3.2.1->oracledb>=2.5.0->text2sql==0.1.0) (3.0)\nBuilding wheels for collected packages: text2sql\n  Building editable for text2sql (pyproject.toml): started\n  Building editable for text2sql (pyproject.toml): finished with status 'done'\n  Created wheel for text2sql: filename=text2sql-0.1.0-0.editable-py3-none-any.whl size=3082 sha256=be494a388d599600cbecfdf8d8f91069e69f6376874c3154bcc2c1b88ed36e1e\n  Stored in directory: /tmp/pip-ephem-wheel-cache-m95alyfo/wheels/f5/c2/99/0ae3143cc47bce93cfb6abad07421e25386367f186f4e2ecbe\nSuccessfully built text2sql\nInstalling collected packages: text2sql\nSuccessfully installed text2sql-0.1.0\n\n--- /tmp/battle-text2sql-ours-20260511T111238Z/.venv/bin/pip install -e . ---"
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
      "reason": "README 113 lines"
    },
    "B4": {
      "score": 5,
      "max": 5,
      "verdict": "pass",
      "reason": "median wall 2.9s"
    }
  },
  "total": 27,
  "max": 27
}
```

## LLM-judge scores

```json
{}
```

## Clone preservation

`/tmp/battle-text2sql-ours-20260511T111238Z` — preserved для forensics

## Methodology

-  — 4-layer framework
-  — battle-test specifics
-  — 100-pt rubric
