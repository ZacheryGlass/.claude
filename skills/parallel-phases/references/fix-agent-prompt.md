# Fix agent prompt

The fix agent reads all 3 reviewer reports for a task, classifies each finding, fixes what is accept-worthy, and commits as a follow-up on the task's existing branch.

## Dispatch parameters

```
Agent(
  description: "fix agent for task-NN",
  subagent_type: "general-purpose",
  model: "opus",
  run_in_background: true,
  prompt: <template below>
)
```

**Do NOT pass `isolation`.** The fix agent must run in the task's existing worktree so its commit lands on the task branch. Pass the worktree path in the prompt so the agent `cd`s into it.

## Prompt template

```
You are the fix agent for phase-N task <TASK-ID> (<task-slug>).

Worktree path: <absolute worktree path from phase-N/dispatch.md>
Task branch:   phase-N/task-NN-<slug>
Target branch: <target_branch>

Your inputs (read these first; all 3 reports exist):
  <absolute path>/<state-dir>/phase-N/task-NN-review-bugs.md
  <absolute path>/<state-dir>/phase-N/task-NN-review-structural.md
  <absolute path>/<state-dir>/phase-N/task-NN-review-architecture.md

The task's original prompt (for context):
<paste task prompt from PLAN.md>

## Your job

1. Change directory to the worktree:
     cd "<worktree path>"

2. Read all 3 reviewer reports completely.

3. Build a combined findings list across all 3 reports. Deduplicate obvious overlaps.

4. Classify each finding as one of:

   - accept  = real, actionable, in scope for this task. Fix now.
   - defer   = real but out of scope for this task (belongs in a separate task or future
               work). Note for the user, do NOT fix.
   - reject  = false positive, based on reviewer misreading or a convention they don't know
               about. Do NOT fix.

   When in doubt between accept and defer: if the fix is <20 LOC and touches only files
   already modified in this task, prefer accept. Otherwise defer.

5. Implement all `accept` findings. Edit only files in the task's scope or files directly
   needed for the fix. Do NOT refactor unrelated code.

6. Run the project's quick-check commands if obvious (lint, typecheck, unit tests for the
   touched files). If test command from PLAN.md exists and completes in under ~60 seconds,
   run it. If longer-running, skip -- the phase-end gate will catch regressions.

7. Commit (new commit, never --amend, no co-author):
     git add <changed paths>
     git commit -m "fix(review): address <count> findings on <task-slug>"

   If no `accept` findings (all defer/reject), do NOT create an empty commit. Skip straight
   to step 8 with an empty-fix summary.

8. Write your summary to:
     <absolute path>/<state-dir>/phase-N/task-NN-fix.md

   Format:

     # Fix summary: phase-N task-NN (<task-slug>)

     Fix commit: <hash or "no-op">
     Findings processed: <total count across 3 reports>

     ## Classification

     | # | Source | Severity | File:line | One-line finding | Action |
     |---|---|---|---|---|---|
     | 1 | bugs | HIGH | src/x.c:42 | null deref in error path | accept |
     | 2 | bugs | LOW | src/x.c:80 | prefer early-return | reject (convention) |
     | 3 | structural | MEDIUM | src/y.h | orphan header | accept |
     | 4 | architecture | MEDIUM | src/* | layer leak | defer |

     ## Accepted (implemented)
     - <one-line each: what was fixed>

     ## Deferred (NOT fixed; for user follow-up)
     - <one-line each: what and why>

     ## Rejected (false positive)
     - <one-line each: what and why>

## Constraints

- You are on the task branch. Never checkout a different branch.
- Never merge, rebase, or push. Only commit.
- Never add Claude as a commit author or co-author. Use default git author only.
- Do NOT spawn subagents.
- Do NOT modify <state-dir>/ files other than writing task-NN-fix.md.
- If you hit a blocker (e.g., a finding requires major architectural change you cannot
  do in scope), defer it and note the reason.

When done, output only a one-line confirmation containing the fix commit hash (or "no-op")
and the path to task-NN-fix.md.
```

## Orchestrator handling after fix agent returns

- **Fix commit created**: read task-NN-fix.md to verify the commit hash matches `git log -1 phase-N/task-NN-<slug> --format=%H`. Set task status to `FIXED`.
- **No-op (no accept findings)**: task-NN-fix.md should say `Fix commit: no-op`. Set task status to `FIXED`. This is a valid outcome.
- **Fix agent failed**: task-NN-fix.md missing or malformed, no new commit on branch -> set task status to `FIX-FAILED`, append `BLOCKED: fix agent failed on task <id>` to STATE.md, exit.
