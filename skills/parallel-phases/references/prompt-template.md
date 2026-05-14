# Task Prompt Template

Every task prompt in PLAN.md must be self-contained. The agent has zero conversation context.

## Required sections

```
Project: <language> project at <absolute path> (<one-line description>).
Read CLAUDE.md for full build instructions, project context, and conventions.

IMPORTANT RESTRICTIONS:
<list hard restrictions -- no network, no credentials, no deployment, etc.>

<CONTEXT: what files to read first, with line numbers and why>

<IMPLEMENTATION: step-by-step instructions>
Each step should reference:
- Exact file path
- Line number or line range where the change goes
- Short code excerpt showing the CURRENT state (so the agent can locate it)
- What to change and why

<ACCEPTANCE CRITERIA>
Bullet list of verifiable conditions.

<VERIFICATION>
Exact shell commands to run (build, test, lint).

COMMITS (create exactly N commits):
1. First commit:
   ```
   git add <specific files>
   git commit -m "<conventional commit message>"
   ```
2. Second commit:
   ...
```

## Guidelines

- **Be specific about what to read first.** List 3-8 files with line ranges. Don't say "read the codebase" -- say "read src/foo.h lines 10-50 for the Foo struct."

- **Include code excerpts at modification points.** The agent needs to locate the exact insertion/replacement point. 3-5 lines of surrounding context is enough.

- **Use conventional commits.** Format: `type(scope): description`. Types: feat, fix, refactor, test, docs, chore.

- **One logical change per commit.** If a task has distinct parts (e.g., production code + tests), use separate commits.

- **Name new files explicitly.** Don't say "create a test file" -- say "create `tests/test_foo.c`."

- **Specify Makefile/build-config changes precisely.** Say "append to TEST_SRCS on line 98" not "add to the Makefile."

- **Include verification that proves correctness**, not just compilation. If the task adds a feature, the test that exercises it is part of verification. If the task modifies behavior, the backtest or integration test that detects regression is part of verification.

## Anti-patterns

- **Vague scope:** "Refactor the module" -- which functions? which files?
- **Missing line numbers:** "Update the struct" -- there are 50 structs in the file
- **No commit instructions:** agent may not commit, or may commit with a generic message
- **Assumed context:** "As discussed above" -- the agent has no "above"
- **Missing restrictions:** agent spawns network calls or reads real credentials
