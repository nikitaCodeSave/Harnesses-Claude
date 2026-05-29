"""Validate that a generated SQL is safe and structurally acceptable."""

import re

# Balance (snapshot) columns must be averaged over multi-month periods, not summed.
_BALANCE_COLS = frozenset({"CA_LCY_SUM", "CA_LCY_RUB_SUM", "DEP_SUM"})

# DML / DDL keywords that must never appear as top-level statements.
_FORBIDDEN = frozenset(
    {"INSERT", "UPDATE", "DELETE", "DROP", "CREATE", "ALTER",
     "TRUNCATE", "MERGE", "EXECUTE", "EXEC"}
)


def validate_sql(sql: str) -> tuple:
    """
    Basic safety + structural validation.
    Returns (is_valid: bool, errors: list[str]).
    NO_SQL is always considered valid (no DB execution needed).
    """
    if sql == "NO_SQL":
        return True, []

    errors: list = []
    upper = sql.upper()

    if not upper.lstrip().startswith("SELECT"):
        errors.append("Query must start with SELECT")

    for kw in _FORBIDDEN:
        if re.search(rf"\b{kw}\b", upper):
            errors.append(f"Forbidden keyword: {kw}")

    if "CLIENT_PRODUCT" not in upper:
        errors.append("Query must reference table 'client_product'")

    open_p, close_p = sql.count("("), sql.count(")")
    if open_p != close_p:
        errors.append(f"Unbalanced parentheses: {open_p} '(' vs {close_p} ')'")

    # Domain rule: SUM(balance_col) over a query that spans multiple months is wrong.
    # Heuristic: if there is a date-range filter AND SUM(balance_col), flag it.
    has_range = bool(
        re.search(r"\bBETWEEN\b", upper)
        or re.search(r"MONTH_DT\s*>=", upper)
        or re.search(r"ADD_MONTHS\b", upper)
    )
    if has_range:
        for col in _BALANCE_COLS:
            if re.search(rf"\bSUM\s*\(\s*{col}\s*\)", upper):
                errors.append(
                    f"Balance column {col} should use AVG(), not SUM(), "
                    "when aggregating over multiple months"
                )

    return len(errors) == 0, errors


def check_domain_rules(sql: str) -> list:
    """Non-blocking domain warnings. Returns list of warning strings."""
    warnings: list = []
    upper = sql.upper()

    if re.search(r"\bLIMIT\s+\d+", upper):
        warnings.append(
            "Oracle does not support LIMIT — use 'FETCH FIRST N ROWS ONLY'"
        )

    return warnings
