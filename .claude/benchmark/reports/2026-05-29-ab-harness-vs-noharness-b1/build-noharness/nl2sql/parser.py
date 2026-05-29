"""Extract a clean SQL query (or NO_SQL) from an LLM response."""

import re
import sys


def extract_sql(response: str) -> str:
    """Return the SQL query from LLM output, or 'NO_SQL'."""
    if not response or not response.strip():
        return "NO_SQL"

    # Strip <think>...</think> reasoning blocks emitted by some models (e.g. Qwen3)
    text = re.sub(r"<think>.*?</think>", "", response, flags=re.DOTALL | re.IGNORECASE)
    text = text.strip()

    if not text:
        return "NO_SQL"

    # Explicit NO_SQL (possibly with surrounding punctuation / short sentence)
    if _is_no_sql(text):
        return "NO_SQL"

    # Prefer SQL extracted from a fenced code block (```sql ... ``` or ``` ... ```)
    block = re.search(r"```(?:sql)?\s*\n?(.*?)```", text, re.DOTALL | re.IGNORECASE)
    if block:
        candidate = block.group(1).strip()
        if candidate.upper().startswith("SELECT"):
            return _clean_sql(candidate)

    # Fall back: take everything from the first SELECT keyword to end-of-string
    m = re.search(r"(SELECT\s+.+)", text, re.DOTALL | re.IGNORECASE)
    if m:
        return _clean_sql(m.group(1).strip())

    print(f"[parser] no SQL found in: {text[:300]!r}", file=sys.stderr)
    return "NO_SQL"


def _is_no_sql(text: str) -> bool:
    """Return True when the response clearly means 'cannot answer'."""
    # Direct match: the whole response is NO_SQL (possibly with trailing punctuation)
    if re.fullmatch(r"NO_SQL[.,!]?", text.strip(), re.IGNORECASE):
        return True
    # Short response that contains NO_SQL and nothing that looks like SELECT
    if len(text) < 120 and "NO_SQL" in text.upper() and "SELECT" not in text.upper():
        return True
    return False


def _clean_sql(sql: str) -> str:
    """Normalise a raw SQL string."""
    # Drop trailing semicolons
    sql = sql.rstrip().rstrip(";").rstrip()
    # Drop any stray ``` that leaked through
    sql = re.sub(r"```.*$", "", sql, flags=re.DOTALL).strip()
    return sql
