# sample-py-app

Minimal Python users-service fixture для tier 1 benchmark task suite.

## Structure

```
app.py        — UsersService (synchronous, in-memory) с known bugs
test_app.py   — baseline test suite (passing pre-Claude changes)
```

Pure Python — no external dependencies (no FastAPI / Pydantic / etc.) for simplest possible setup. Requires pytest (already в harness allowed-tools).

## Running baseline tests

```bash
cd .claude/benchmark/fixtures/sample-py-app
python3 -m pytest test_app.py -v
```

Expected: 6 tests pass (baseline state).

## Known issues для benchmark

| Task | File / line | Issue | Expected fix |
|------|-------------|-------|--------------|
| T01 | app.py | No health-check method on UsersService | Add health() + test |
| T02 | app.py UsersService.add_user | Silent overwrite на duplicate email | Detect duplicate + raise/return error + regression test |
| T03 | app.py | All logic в single file (monolith) | Split UsersService into separate service + handlers modules |
| T07 | test_app.py | No tests for delete_user edge cases / list_users ordering | Add coverage tests |

Other tasks (T04 docs, T05 lint, T06 research) operate on fixture as-is.
