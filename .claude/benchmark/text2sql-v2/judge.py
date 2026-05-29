"""Axes 7-9 LLM-as-judge for benchmark v2 (qualitative profile, non-blocking).

These axes grade the natural-language *answer* (`submission["answer"]`) the
agent returns alongside its SQL/result, not the SQL itself (axes 1-4 do that
deterministically in `scorer.py`). They need judgement a regex can't give, so
they go through an LLM via the same OpenAI-compatible endpoint the source
`AI_analyst_migration` project uses (ollama by default).

  Axis 7  faithfulness (1-5): every number in the answer traces to `result`;
          the aggregation type is named correctly (avg/sum/max); no invented
          trends or causes.
  Axis 8  consistency (bool): the period / entities stated in the NL answer
          match the filters actually present in the SQL.
  Axis 9  depth (1-5): all parts of the question answered; context/comparison
          rather than a bare number; truncation/incompleteness flagged.

`judge_answer(task, submission)` returns:
  {"faithfulness": int, "consistency": bool, "depth": int,
   "violations": [...], "judge_status": "ok" | "skipped"}

DEGRADE CONTRACT: if there is no answer to judge, or the LLM endpoint is
unreachable / errors / returns garbage, we return judge_status="skipped" with
neutral fields and NEVER raise. Axes 7-9 are a profile, not a gate — a missing
judge must not break a run.

Config comes only from the environment (no creds in code, no reading any
project's .env):
  AI_ANALYST_API_URL    base_url (fallback http://localhost:11434/v1)
  AI_ANALYST_JUDGE_MODEL model name (fallback DEFAULT_MODEL below)
  AI_ANALYST_API_KEY    api key (fallback "ollama" — ollama ignores it)
"""
from __future__ import annotations

import json
import os
import re

DEFAULT_BASE_URL = "http://localhost:11434/v1"
DEFAULT_MODEL = "GenAI/Qwen3-30B-A3B"
DEFAULT_API_KEY = "ollama"

# Neutral verdict returned whenever the judge cannot run. faithfulness/depth at
# the rubric floor (1) and consistency False keep a skipped axis from silently
# looking like a pass; judge_status="skipped" is the signal that it didn't run.
_SKIPPED = {
    "faithfulness": 1,
    "consistency": False,
    "depth": 1,
    "violations": [],
    "judge_status": "skipped",
}


def _strip_think(text: str) -> str:
    """Drop reasoning-model <think>...</think> noise, mirroring the source
    project's extraction (core/sql/extraction.py, infrastructure/utils.py)."""
    if not text:
        return ""
    # text after a closing </think> is the real payload (open tag may be absent)
    m = re.search(r"</think>", text, re.IGNORECASE)
    if m:
        text = text[m.end():]
    # and remove any remaining balanced blocks
    text = re.sub(r"<think>.*?</think>", "", text, flags=re.DOTALL | re.IGNORECASE)
    return text.strip()


def _extract_json(text: str) -> dict | None:
    """Pull the first JSON object out of a model reply, tolerant of code fences
    and prose around it. Returns None if nothing parseable is found."""
    text = _strip_think(text)
    if not text:
        return None
    # try the whole string first, then the first {...} span
    candidates = [text]
    start = text.find("{")
    end = text.rfind("}")
    if start != -1 and end != -1 and end > start:
        candidates.append(text[start:end + 1])
    for c in candidates:
        try:
            obj = json.loads(c)
        except (ValueError, TypeError):
            continue
        if isinstance(obj, dict):
            return obj
    return None


def _get_client():
    """Construct the OpenAI-compatible client lazily. Returns None if the SDK
    is unavailable or construction fails — the caller degrades to skipped."""
    try:
        from openai import OpenAI
    except Exception:
        return None
    base_url = os.environ.get("AI_ANALYST_API_URL") or DEFAULT_BASE_URL
    api_key = os.environ.get("AI_ANALYST_API_KEY") or DEFAULT_API_KEY
    try:
        return OpenAI(api_key=api_key, base_url=base_url, max_retries=0)
    except Exception:
        return None


def _model_name() -> str:
    return os.environ.get("AI_ANALYST_JUDGE_MODEL") or DEFAULT_MODEL


_RUBRIC = """\
You are a strict grader of a data-analyst's natural-language ANSWER. You are
given the user QUESTION, the SQL the analyst ran, the raw RESULT it returned,
and the analyst's ANSWER. Grade ONLY the ANSWER against the SQL and RESULT.
Do not re-run anything. Do not be generous.

Score three axes:

axis 7 — faithfulness (integer 1..5):
  Every number in the ANSWER must trace to RESULT. The aggregation word used
  (average / sum / maximum / count) must match what RESULT represents. No
  invented trends, causes, or growth claims that RESULT does not support.
  5 = fully grounded; 1 = fabricated numbers or wrong aggregation named.

axis 8 — consistency (boolean true/false):
  The period and entities the ANSWER talks about must match the filters in the
  SQL (e.g. if SQL filters Q3 2025 but the ANSWER says "in 2024", that is false).

axis 9 — depth (integer 1..5):
  Did the ANSWER address every part of the QUESTION? Is there context or
  comparison rather than a bare number? If the data was truncated/incomplete,
  is that flagged? 5 = complete and contextual; 1 = bare or partial.

For every problem you find, add a short string to "violations".

Reply with ONE JSON object and nothing else:
{"faithfulness": <1-5>, "consistency": <true|false>, "depth": <1-5>,
 "violations": ["...", "..."]}
"""


def _build_prompt(task, submission) -> str:
    return (
        f"QUESTION:\n{task.get('nl', '')}\n\n"
        f"SQL:\n{submission.get('sql', '')}\n\n"
        f"RESULT:\n{json.dumps(submission.get('result'), ensure_ascii=False, default=str)}\n\n"
        f"ANSWER:\n{submission.get('answer', '')}\n"
    )


def _coerce_score(value, lo: int, hi: int, default: int) -> int:
    try:
        n = int(round(float(value)))
    except (TypeError, ValueError):
        return default
    return max(lo, min(hi, n))


def _parse_verdict(obj: dict) -> dict:
    """Map a parsed judge JSON onto the strict return contract, clamping
    out-of-range scores and coercing types defensively."""
    violations = obj.get("violations", [])
    if not isinstance(violations, list):
        violations = [str(violations)]
    violations = [str(v) for v in violations]
    return {
        "faithfulness": _coerce_score(obj.get("faithfulness"), 1, 5, 1),
        "consistency": bool(obj.get("consistency", False)),
        "depth": _coerce_score(obj.get("depth"), 1, 5, 1),
        "violations": violations,
        "judge_status": "ok",
    }


def judge_answer(task, submission, client=None) -> dict:
    """Grade the NL answer on axes 7-9 via the LLM judge.

    `client` may be injected (any object exposing
    `.chat.completions.create(model=..., messages=...)`) for testing; when
    None a real OpenAI-compatible client is built from the environment.

    Never raises. Degrades to judge_status="skipped" when there is no answer
    to grade, the endpoint is unavailable, or the reply is unparseable.
    """
    answer = (submission.get("answer") or "").strip() if submission else ""
    if not answer:
        return dict(_SKIPPED)

    if client is None:
        client = _get_client()
    if client is None:
        return dict(_SKIPPED)

    messages = [
        {"role": "system", "content": _RUBRIC},
        {"role": "user", "content": _build_prompt(task, submission)},
    ]
    try:
        response = client.chat.completions.create(
            model=_model_name(),
            messages=messages,
            temperature=0,
        )
        content = response.choices[0].message.content
    except Exception:
        return dict(_SKIPPED)

    obj = _extract_json(content or "")
    if obj is None:
        return dict(_SKIPPED)
    return _parse_verdict(obj)
