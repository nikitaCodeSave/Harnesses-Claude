import json
import os
import sys

import httpx


def get_config() -> tuple[str, str, str]:
    url = os.environ.get("AI_ANALYST_API_URL", "http://localhost:11434/v1")
    key = os.environ.get("AI_ANALYST_API_KEY", "ollama")
    model = os.environ.get("AI_ANALYST_SQL_MODEL", "llama3")
    return url.rstrip("/"), key, model


def call_llm(system_prompt: str, user_prompt: str, temperature: float = 0.1) -> str:
    url, key, model = get_config()

    payload = {
        "model": model,
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_prompt},
        ],
        "temperature": temperature,
        "stream": False,
    }

    try:
        with httpx.Client(timeout=120.0) as client:
            response = client.post(
                f"{url}/chat/completions",
                headers={
                    "Content-Type": "application/json",
                    "Authorization": f"Bearer {key}",
                },
                json=payload,
            )
            response.raise_for_status()
            data = response.json()
            content = data["choices"][0]["message"]["content"]
            return content
    except httpx.HTTPStatusError as e:
        print(f"[llm] HTTP {e.response.status_code}: {e.response.text[:300]}", file=sys.stderr)
        raise
    except httpx.RequestError as e:
        print(f"[llm] Request error: {e}", file=sys.stderr)
        raise
    except (KeyError, IndexError, json.JSONDecodeError) as e:
        print(f"[llm] Response parse error: {e}", file=sys.stderr)
        raise
