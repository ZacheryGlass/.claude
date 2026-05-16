---
description: Run all standard review agents in parallel on current changes
argument-hint: [optional: specific files or commit range to review]
---

# Review Gauntlet

Run the full standard review suite in parallel, then address all findings.

## Context

Recent changes: !`git log --oneline -5`

Modified files (unstaged): !`git diff --name-only`

Staged files: !`git diff --cached --name-only`

Diff summary: !`git diff --stat HEAD`

## Target

$ARGUMENTS

If arguments specify files or a commit range, review that. Otherwise review unstaged + staged changes (i.e. recent work not yet committed, or the most recent commit if working tree is clean).

## Step 1: Launch All Reviewers in Parallel

Launch ALL of the following agents simultaneously using the Agent tool (one message, multiple tool calls). Each agent receives the same change context identified above.

1. **structural-completeness-reviewer** -- Verify changes are fully integrated, old code removed, no orphaned references or incomplete wiring.

2. **bug-finder** -- Hunt for logical errors, race conditions, unhandled edge cases, off-by-one errors, null dereferences.

3. **silent-failure-hunter** -- Find swallowed errors, inappropriate fallbacks, catch blocks that hide failures, error paths that produce no observable signal.

4. **c-safety-reviewer** -- Check memory safety (buffer overflows, use-after-free, double-free), resource lifecycle (fd/socket leaks in error paths), integer overflow, crypto misuse, re-entrancy in callbacks.

5. **compatibility-reviewer** -- Verify no silent breakage of consumers: env vars, CLI flags, API shapes, state file formats, struct layouts, deploy scripts, documentation examples.

Each agent prompt must include:
- The specific files changed (from context above)
- The actual diff content (use `git diff` or `git show` as appropriate)
- Instruction to review ONLY the changes, not the entire codebase

## Step 2: Synthesize Results

After ALL agents return, produce a unified report:

```
## Review Gauntlet Results

### Critical / Must-Fix
[Items from any reviewer that block commit -- CRITICAL or HIGH severity]

### Should-Fix
[MEDIUM severity items worth addressing now]

### Advisory
[LOW severity or informational notes]

### Pass Summary
[Which reviewers found no issues]
```

## Step 3: Fix Critical and Should-Fix Items

Immediately implement fixes for all Critical and Should-Fix items. Do not ask for permission -- just fix them.

For Advisory items, list them but do not fix unless trivially addressable in the same change.

## Step 4: Re-verify

After fixing, run a quick sanity check:
- `make` (or appropriate build command) to verify compilation
- Confirm fixes don't introduce new issues obvious from reading the diff

Do NOT re-run the full gauntlet. Trust the fixes unless the build fails.
