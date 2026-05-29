#!/usr/bin/env python3
import sys

from nl2sql.agent import nl_to_sql


def main() -> None:
    if len(sys.argv) < 2:
        print("Usage: python3 solve.py \"<вопрос на русском>\"", file=sys.stderr)
        sys.exit(1)

    question = sys.argv[1]
    result = nl_to_sql(question)
    print(result)


if __name__ == "__main__":
    main()
