import sys

from .llm import call_llm
from .parser import extract_sql
from .prompt import build_system_prompt, build_user_prompt
from .validator import validate_sql

MAX_RETRIES = 2


def nl_to_sql(question: str) -> str:
    """Translate a Russian analytical question to an Oracle SQL query or 'NO_SQL'."""
    system_prompt = build_system_prompt()
    base_user_prompt = build_user_prompt(question)

    last_error: str = ""

    for attempt in range(MAX_RETRIES + 1):
        if attempt == 0:
            user_prompt = base_user_prompt
        else:
            print(f"[agent] retry {attempt}/{MAX_RETRIES}: {last_error}", file=sys.stderr)
            user_prompt = (
                base_user_prompt
                + f"\n\nПредыдущий ответ был некорректным: {last_error}. "
                "Верни ТОЛЬКО корректный Oracle SQL SELECT-запрос к client_product "
                "или строку NO_SQL. Без пояснений."
            )

        try:
            raw = call_llm(system_prompt, user_prompt)
        except Exception as e:
            last_error = f"LLM error: {e}"
            continue

        print(f"[agent] raw: {repr(raw[:300])}", file=sys.stderr)

        result = extract_sql(raw)

        if result is None:
            last_error = "Не удалось извлечь SQL из ответа"
            continue

        if result == "NO_SQL":
            return "NO_SQL"

        is_valid, error = validate_sql(result)
        if not is_valid:
            last_error = error
            continue

        return result

    print(f"[agent] все попытки исчерпаны, последняя ошибка: {last_error}", file=sys.stderr)
    return "NO_SQL"
