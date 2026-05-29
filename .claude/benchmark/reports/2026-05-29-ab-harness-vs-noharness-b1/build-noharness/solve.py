#!/usr/bin/env python3
"""
NL→SQL entry point.

Usage:
    python3 solve.py "<question in Russian>"

Prints to stdout: an Oracle SELECT query, or NO_SQL if the question cannot
be answered from the client_product table.
All diagnostic output goes to stderr.
"""

import os
import sys


def main() -> None:
    if len(sys.argv) < 2:
        print("Usage: python3 solve.py \"<question>\"", file=sys.stderr)
        print("NO_SQL")
        sys.exit(1)

    question = " ".join(sys.argv[1:]).strip()
    if not question:
        print("NO_SQL")
        sys.exit(0)

    missing = [
        v for v in ("AI_ANALYST_API_URL", "AI_ANALYST_API_KEY", "AI_ANALYST_SQL_MODEL")
        if not os.environ.get(v)
    ]
    if missing:
        print(f"[solve] Missing env vars: {', '.join(missing)}", file=sys.stderr)
        print("NO_SQL")
        sys.exit(1)

    # Import here so that missing env vars are caught first
    from nl2sql.agent import NL2SQLAgent

    agent = NL2SQLAgent()
    result = agent.query(question)
    print(result)


if __name__ == "__main__":
    main()
