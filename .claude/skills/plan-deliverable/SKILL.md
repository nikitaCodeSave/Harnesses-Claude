---
name: plan-deliverable
description: Convert a stated goal into a 1-page deliverable spec with acceptance criteria and verification mechanism, NOT a task breakdown. Use when developer states a goal without explicit acceptance criteria. Skip when goal already has clear acceptance criteria.
disable-model-invocation: true
context: fork
agent: deliverable-planner
---

Goal от пользователя: $ARGUMENTS.

Произведи 1-страничную deliverable spec со структурой:
- **Goal**: одно предложение
- **Acceptance criteria**: 3-7 пунктов, каждый верифицируемый
- **Verification**: команда / lint / manual checklist
- **Out of scope**: явный список того, что НЕ входит

НЕ декомпозируй на микро-задачи. Если goal неоднозначен — задай ≤3 вопросов через AskUserQuestion, потом завершай spec.
