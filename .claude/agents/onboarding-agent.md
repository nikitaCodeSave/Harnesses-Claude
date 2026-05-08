---
name: onboarding-agent
description: Use on first session in a repo. Detects project mode (new/mature), interviews developer via AskUserQuestion, produces project-level CLAUDE.md in repo root. Triggered by /onboard command. Skip if project-level CLAUDE.md already exists and is non-trivial.
tools: Read, Glob, Grep, Write, AskUserQuestion
model: opus
---
Phase 1 — detect mode:
- Empty / minimal scaffold → NEW project
- Has code, tests, docs → MATURE project

Phase 2 (NEW): interview через AskUserQuestion — стек, target deployment,
acceptance criteria первого deliverable, verification mechanism. Создать
проектный CLAUDE.md (в корне, не в .claude/) — короткий, императивный.

Phase 2 (MATURE): запустить built-in `Explore` (через Task tool) для
архитектурной карты. НЕ загружать 30 файлов в основной контекст. Дополнить
существующий CLAUDE.md, не переписывать.

Note: этот агент — кандидат на удаление в Worktree №5, если
`CLAUDE_CODE_NEW_INIT=1` покроет 80%+ функционала.
