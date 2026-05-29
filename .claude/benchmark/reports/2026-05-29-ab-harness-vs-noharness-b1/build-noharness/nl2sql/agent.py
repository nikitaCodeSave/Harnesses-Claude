"""Main NL→SQL agent: orchestrates LLM calls, parsing, validation, and retry."""

import sys

from nl2sql.llm import call_llm
from nl2sql.parser import extract_sql
from nl2sql.schema import SYSTEM_PROMPT
from nl2sql.validator import check_domain_rules, validate_sql

MAX_RETRIES = 3


class NL2SQLAgent:
    def __init__(self):
        self._system = SYSTEM_PROMPT

    def query(self, question: str) -> str:
        """Convert a Russian analytics question to an Oracle SQL query or 'NO_SQL'."""
        messages = [
            {"role": "system", "content": self._system},
            {"role": "user", "content": question},
        ]

        for attempt in range(MAX_RETRIES):
            try:
                print(f"[agent] attempt {attempt + 1}/{MAX_RETRIES}", file=sys.stderr)
                raw = call_llm(messages, temperature=0.1)
                print(f"[agent] raw response ({len(raw)} chars): {raw[:400]!r}", file=sys.stderr)

                sql = extract_sql(raw)
                print(f"[agent] extracted: {sql[:200]!r}", file=sys.stderr)

                if sql == "NO_SQL":
                    return "NO_SQL"

                is_valid, errors = validate_sql(sql)
                if is_valid:
                    for w in check_domain_rules(sql):
                        print(f"[agent] warning: {w}", file=sys.stderr)
                    return sql

                print(f"[agent] validation errors: {errors}", file=sys.stderr)

                # Ask the model to repair on the next iteration
                messages.append({"role": "assistant", "content": raw})
                messages.append(
                    {
                        "role": "user",
                        "content": (
                            f"SQL validation errors: {'; '.join(errors)}. "
                            "Fix the query and return ONLY the corrected Oracle SELECT, "
                            "or return NO_SQL if the question cannot be answered "
                            "from the client_product table."
                        ),
                    }
                )

            except Exception as exc:
                print(
                    f"[agent] error on attempt {attempt + 1}: "
                    f"{type(exc).__name__}: {exc}",
                    file=sys.stderr,
                )
                if attempt == MAX_RETRIES - 1:
                    return "NO_SQL"

        print("[agent] max retries exceeded", file=sys.stderr)
        return "NO_SQL"
