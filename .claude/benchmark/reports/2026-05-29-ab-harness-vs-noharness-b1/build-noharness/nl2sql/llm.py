import json
import os
import sys

try:
    import httpx
    _USE_HTTPX = True
except ImportError:
    import urllib.request
    import urllib.error
    _USE_HTTPX = False


def call_llm(messages: list, temperature: float = 0.1, timeout: int = 120) -> str:
    """Call the LLM via OpenAI-compatible API. Returns the assistant message content."""
    api_url = os.environ.get("AI_ANALYST_API_URL", "http://localhost:11434/v1")
    api_key = os.environ.get("AI_ANALYST_API_KEY", "ollama")
    model = os.environ.get("AI_ANALYST_SQL_MODEL", "llama3.2")

    url = f"{api_url.rstrip('/')}/chat/completions"
    payload = {
        "model": model,
        "messages": messages,
        "temperature": temperature,
        "stream": False,
    }
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {api_key}",
    }

    print(f"[llm] POST {url}  model={model}", file=sys.stderr)

    if _USE_HTTPX:
        return _call_httpx(url, payload, headers, timeout)
    return _call_urllib(url, payload, headers, timeout)


def _call_httpx(url: str, payload: dict, headers: dict, timeout: int) -> str:
    with httpx.Client(timeout=timeout) as client:
        resp = client.post(url, json=payload, headers=headers)
        resp.raise_for_status()
        data = resp.json()
    return data["choices"][0]["message"]["content"]


def _call_urllib(url: str, payload: dict, headers: dict, timeout: int) -> str:
    import urllib.request
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers=headers, method="POST")
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        result = json.loads(resp.read().decode("utf-8"))
    return result["choices"][0]["message"]["content"]
