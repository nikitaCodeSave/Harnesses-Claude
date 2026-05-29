# Adversarial post-test audit prompt

You are a senior code reviewer auditing this codebase for **production readiness**.

The codebase is in your current working directory. The deliverable is supposed to solve a real-world problem described in the SPEC section below.

## Your task

In **10 minutes** find as many distinct, demonstrable real-world failure modes as you can.

A **failure mode** is a class of input or condition under which this code:
- silently produces wrong results, OR
- crashes, OR
- fails to handle a scenario it claims to handle, OR
- omits capability that the domain manifestly requires for a useful answer.

USE your domain expertise. If the spec is about Oracle SQL — use Oracle knowledge. If about web APIs — use web knowledge. Look for what's **missing** as well as what's broken.

## Methodology

1. Read the SPEC below to understand domain + intended behavior.
2. Survey code structure (`ls`, `Read`).
3. For each failure mode:
   - **Best**: run a reproducer (`Bash`, read-only).
   - **Acceptable**: cite specific code line + concrete trigger.
   - **Discouraged**: speculation without concrete trigger.

## Constraints

- **READ-ONLY**: do not modify files. Do not run destructive Bash. No git commits, no installs of new packages, no rewriting files.
- 10 minutes max — quality over quantity. Better 5 sharp findings than 20 speculative.
- Skip cosmetic / style / linting issues. Focus on **behavior**.
- No fixes — just findings.
- Each finding must name the failure mode, not generically "bad error handling".

## Output format

For each finding emit **one JSON object on its own line**, no surrounding prose:

```
{"id": 1, "category": "correctness", "description": "...", "reproducer": "...", "code_ref": "file:line", "severity": "major", "demonstrability": "verified"}
```

Categories: `correctness | data_integrity | error_handling | edge_case | security | performance | semantics | missing_feature | testing_quality`

Severity: `critical | major | minor`
- **critical**: silent wrong result on common input, or crash on baseline scenario, or security hole
- **major**: silent wrong result on plausible input, or breaks on documented edge case
- **minor**: degraded behavior, fixable workaround exists

Demonstrability: `verified | reasoned | speculative`
- **verified**: ran the reproducer, observed failure
- **reasoned**: code-path inspection + concrete trigger, not executed
- **speculative**: pattern-based guess, no concrete trigger

After all JSON lines, emit one summary line:

```
SUMMARY: total=N critical=N major=N minor=N verified=N reasoned=N speculative=N
```

Then stop. No recommendations, no prose.
