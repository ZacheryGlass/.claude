# Worktree + merge protocol

How the orchestrator handles per-task worktrees, phase-end merge, tests, and rollback.

## Worktree lifecycle

1. **Task dispatch**: `Agent(..., isolation: "worktree", run_in_background: true, ...)` creates a worktree and branch for the task. The Agent returns the worktree path and branch name on completion.
2. **Dispatch record**: write `phase-N/dispatch.md` with a table: task id -> worktree path -> branch name. The orchestrator needs these paths to dispatch fix agents later.
3. **Task agent**: commits on the task branch. May produce multiple commits; the reviewer diff range captures all of them.
4. **Reviewers**: read-only, run in the main working copy. They use `git diff <target_branch>...phase-N/task-NN-<slug>` to read the diff without needing to enter the worktree.
5. **Fix agent**: `cd`s into the worktree (path passed in prompt), makes changes, commits as new commit on the task branch.
6. **Merge**: from the main working copy, merge the task branches into `phase-N/integration`.
7. **Cleanup**: after phase merges into `target_branch`, remove the per-task worktrees and branches (`git worktree remove`, `git branch -D phase-N/task-NN-<slug>`).

## dispatch.md format

```markdown
# Phase N dispatch

Dispatched at: <ISO-8601>

| Task | Branch | Worktree path |
|---|---|---|
| task-01-<slug> | phase-1/task-01-<slug> | <cwd>/../<repo>-task-01-<slug> |
| task-02-<slug> | phase-1/task-02-<slug> | <cwd>/../<repo>-task-02-<slug> |
```

The exact worktree path format depends on how `isolation: "worktree"` places worktrees; record whatever the Agent tool returns.

## Phase-end merge (after all tasks FIXED)

Run from the **main working copy** (not inside a worktree):

```bash
# 1. Create / reset integration branch from target
git branch -f phase-N/integration <target_branch>
git checkout phase-N/integration

# 2. Merge each task branch in PLAN.md order
for each task in phase N (in PLAN.md order):
    git merge --no-ff phase-N/task-NN-<slug> -m "merge: phase N task NN (<slug>)"
    if conflict:
        git merge --abort
        -> write phase-N/task-NN-merge-conflict.md with `git status` output + conflicted files list
        -> mark task RETRY-NEEDED in STATE.md
        -> append `BLOCKED: phase N merge conflict on task NN` to STATE.md
        -> exit

# 3. Run test command (from PLAN.md)
<test_command> 2>&1 | tee <state-dir>/phase-N/test-log.txt
if $? != 0:
    -> append `BLOCKED: phase N tests red -- see <state-dir>/phase-N/test-log.txt` to STATE.md
    -> exit

# 4. Fast-forward target into integration (preserving integration history)
git checkout <target_branch>
git merge --ff-only phase-N/integration

# 5. Write markers + commit
touch <state-dir>/phase-N/phase-complete
touch <state-dir>/phase-N/merged
# State dir is outside the repo -- no git add needed
git commit --allow-empty -m "chore(parallel-phases): phase N merged"

# 6. Cleanup
for each task in phase N:
    git worktree remove <worktree path> --force 2>/dev/null || true
    git branch -D phase-N/task-NN-<slug> 2>/dev/null || true
git branch -D phase-N/integration 2>/dev/null || true
git worktree prune
```

## When there is no test command

If PLAN.md sets `test_command: none` OR no test command could be auto-detected:

- Skip step 3.
- In STATE.md, write: `GATE: SKIPPED (no test command configured)`.
- Still fast-forward target.

The user accepted the risk by leaving `test_command: none`.

## Conflict resolution protocol (user-assisted)

When a merge conflict aborts the phase:

1. The orchestrator does NOT attempt `git mergetool` or automated resolution.
2. User can resolve manually by:
   - `cd` into one of the conflicting worktrees, rebase onto the other task's branch, resolve conflicts, commit, return.
   - Or rewrite PLAN.md to serialize the conflicting tasks into separate phases (requires restart via `rm -rf <state-dir>/`).
3. After user fixes: edit STATE.md to remove the `BLOCKED:` line and reset the RETRY-NEEDED task back to `FIXED`.
4. Re-run `/parallel-phases` -- the skill will retry the merge from scratch.

## Rollback on test failure

1. Leave the failing test log at `<state-dir>/phase-N/test-log.txt`.
2. `git checkout <target_branch>` (tests were run on integration; target is untouched if step 3 failed before step 4).
3. Delete `phase-N/integration` branch: `git branch -D phase-N/integration`.
4. `BLOCKED:` line in STATE.md points at the log.
5. User triages: either fixes manually (then removes BLOCKED and re-runs) or rewinds the phase by resetting tasks to PENDING.

## Safety rules

- Never force-push.
- Never `git reset --hard` on anything except freshly-created integration branches that the orchestrator owns.
- Never delete a task worktree until after its phase has merged successfully (otherwise we lose the ability to re-dispatch the fix agent).
- Never merge `phase-N/integration` into `target_branch` via `--no-ff` -- use `--ff-only`. If fast-forward fails, it means `target_branch` advanced during execution; abort with `BLOCKED: target branch moved during phase N -- rebase required`.
