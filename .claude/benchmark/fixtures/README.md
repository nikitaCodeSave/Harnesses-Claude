# Benchmark Fixtures

Self-contained test projects для tier 1 task suite. Synthetic, no external dependencies, fully reproducible, version-controlled в harness repo.

## Available fixtures

- `sample-py-app/` — minimal Python users-service с known bugs для tier 1 tasks T01-T07.

## Why fixtures in-repo

Self-contained harness pack: fixture доступна сразу after `git clone`, без external setup. Aligned с self-containment principle (см. `.claude/docs/principles.md` Foundational).

Alternative: external project via `FIXTURE_PATH` env var. Useful для running benchmark на real-world codebase. Default — synthetic in-repo fixture.

## Adding new fixture

1. Create `fixtures/<name>/` directory
2. Add `README.md` explaining purpose + known issues documented
3. Add minimal code structure (≥2 files, existing tests)
4. Update `tier1/tasks/*.yaml` если new tasks specific to fixture
5. Document здесь

## Comparison fixtures (roadmap)

Future: add fixtures mirroring real Anthropic samples / popular community harness'ов (everything-claude-code, claude-code-harness, Superpowers) для cross-harness behavioral comparison. Currently — synthetic only, structural comparison only.
