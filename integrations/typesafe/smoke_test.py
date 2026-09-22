#!/usr/bin/env python3
"""Smoke test: list models, then run one minimal Noul question against a pinned Jev."""

import json
import os
import pathlib
import urllib.request

from typesafe_sdk import Noul, TypeSafeClient

# Pin the exact version. An alias (jev-latest) moves on release and would carry
# calibrated thresholds over to a different model. See docs/typesafe/models.md.
MODEL = "jev-1.13.0"

# Minimal .env loader; the SDK itself reads TYPESAFE_API_KEY from the environment.
env_path = pathlib.Path(__file__).parent / ".env"
for line in env_path.read_text().splitlines():
    if line.strip() and not line.startswith("#"):
        key, _, value = line.partition("=")
        os.environ.setdefault(key.strip(), value.strip())

api_key = os.environ["TYPESAFE_API_KEY"]

print("=" * 60)
print("1. GET https://api.typesafe.ai/v1/models")
print("=" * 60)

request = urllib.request.Request(
    "https://api.typesafe.ai/v1/models",
    headers={"Authorization": f"Bearer {api_key}"},
)
with urllib.request.urlopen(request, timeout=30) as response:
    print(f"HTTP {response.status}")
    print(json.dumps(json.loads(response.read()), indent=2, ensure_ascii=False))

print()
print("=" * 60)
print(f"2. POST /v1/systemone — one Noul, model pinned to {MODEL}")
print("=" * 60)

with TypeSafeClient(model=MODEL) as client:
    result = client.system_one(
        "Help! My payouts have been failing for 3 days.",
        {"is_urgent": Noul(instructions="Does this message convey urgency?")},
    )

print(f"answer.is_urgent.noul = {result.nouls['is_urgent'].noul}")
print(f"response.model        = {result.model}")
print(f"response.usage        = {result.usage}")
print(f"response.request_id   = {result.request_id}")
