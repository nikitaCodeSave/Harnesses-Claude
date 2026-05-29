import re

_DML_RE = re.compile(
    r'^\s*(INSERT|UPDATE|DELETE|DROP|CREATE|ALTER|TRUNCATE|MERGE|GRANT|REVOKE)\b',
    re.IGNORECASE,
)


def validate_sql(sql: str) -> tuple[bool, str]:
    """Return (is_valid, error_message). NO_SQL always passes."""
    if not sql or sql.strip().upper() == "NO_SQL":
        return True, ""

    s = sql.strip()

    if not re.match(r'^\s*SELECT\b', s, re.IGNORECASE):
        return False, "SQL должен начинаться с SELECT"

    if _DML_RE.match(s):
        return False, "DML-операции запрещены"

    if not re.search(r'\bFROM\b', s, re.IGNORECASE):
        return False, "SQL должен содержать FROM"

    return True, ""
