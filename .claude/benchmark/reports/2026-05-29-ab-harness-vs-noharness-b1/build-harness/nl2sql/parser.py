import re


_NO_SQL_RE = re.compile(r'\bNO_SQL\b', re.IGNORECASE)
_MD_BLOCK_RE = re.compile(r'```(?:sql)?\s*\n?(.*?)```', re.DOTALL | re.IGNORECASE)
_SELECT_RE = re.compile(r'(SELECT\b.*)', re.DOTALL | re.IGNORECASE)
_LIMIT_RE = re.compile(r'\bLIMIT\s+(\d+)\b', re.IGNORECASE)


def extract_sql(response: str) -> str | None:
    """Return SQL string, 'NO_SQL', or None if nothing could be extracted."""
    text = response.strip()

    if not text:
        return None

    if _NO_SQL_RE.search(text):
        # Make sure it's not a stray mention inside a SQL comment
        if not re.match(r'^\s*SELECT\b', text, re.IGNORECASE):
            return "NO_SQL"

    # Try markdown code block first
    m = _MD_BLOCK_RE.search(text)
    if m:
        sql = m.group(1).strip()
        if _NO_SQL_RE.fullmatch(sql.strip()):
            return "NO_SQL"
        if sql:
            return _normalize(sql)

    # Try bare SELECT
    m = _SELECT_RE.search(text)
    if m:
        return _normalize(m.group(1).strip())

    return None


def _normalize(sql: str) -> str:
    """Remove trailing semicolons and fix LIMIT → FETCH FIRST N ROWS ONLY."""
    sql = sql.strip().rstrip(';').rstrip()
    sql = _LIMIT_RE.sub(lambda mo: f"FETCH FIRST {mo.group(1)} ROWS ONLY", sql)
    return sql
