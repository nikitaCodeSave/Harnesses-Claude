import os
import pytest


@pytest.fixture(autouse=True)
def env_vars():
    """Ensure required env vars are present for every test."""
    defaults = {
        "AI_ANALYST_API_URL": "http://localhost:11434/v1",
        "AI_ANALYST_API_KEY": "test-key",
        "AI_ANALYST_SQL_MODEL": "test-model",
    }
    for k, v in defaults.items():
        os.environ.setdefault(k, v)
    yield
