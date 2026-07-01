---
name: git-worktree-prune
description: Safely prune stale git worktrees and local branches left over from past sessions, deleting only those with no unique work so no commit is ever lost. Use when a repo has accumulated worktrees and branches over many sessions and needs cleanup. Triggers include "prune worktrees", "delete stale branches", "clean up git worktrees/branches", "remove old worktrees", "which branches are safe to delete".
---

# Git Worktree & Branch Prune

Remove stale worktrees and local branches from old sessions **without ever losing a commit**.

## Safety invariant

- A **branch** is deleted only when every commit on it is reachable from some *other* surviving ref (another local branch, a remote-tracking branch `origin/*`, or a tag). Branches with unique commits are kept.
- A **worktree** is removed only when it is **clean** (no uncommitted or untracked changes). The branch it held is preserved.
- The **primary worktree**, the **current branch**, and `main`/`master` are always kept.

## Usage

Always dry-run first (the default — it changes nothing), review the plan, then apply:

```bash
python scripts/prune_git.py --repo <path>            # dry-run: prints KEEP/REMOVE/DELETE plan
python scripts/prune_git.py --repo <path> --apply    # execute after reviewing the dry-run
```

Flags:
- `--fetch` — run `git fetch --all --prune` first so branches already merged/pushed to a remote are recognized as deletable. Without it the tool is more *conservative* (stale remotes only ever cause it to keep more, never lose work).
- `--protect BRANCH` — always keep this branch (repeatable). Use for branches with no unique commits that you still want to keep (see below).
- `--repo PATH` — a path inside the target repo (default: cwd).

## Review the DELETE list before `--apply`

The "no unique commits" rule is about *commits*, not intent. A branch can be flagged **DELETE** while still being meaningful — most commonly a **feature branch that a descendant now subsumes** (e.g., you branched `research/x` off `feat/y`, so `feat/y`'s commits now also live on `research/x`). No commit is lost if it's deleted, but the branch *name* and its PR track are. Keep such a branch with `--protect <name>`.

Every removal is printed with its reason; a branch shown as `KEEP -- N unique commit(s)` holds work found nowhere else and is never touched.

## Notes

- Never deletes remote-tracking refs, tags, or the reflog — only local branches and worktree checkouts.
- Removing a worktree that holds a branch (even a protected one like `main`) frees the branch without deleting it; you can then check it out in the primary worktree.
- Worktrees whose directory is already gone are cleaned via `git worktree prune`.
- On Windows, run under Git Bash / a UTF-8 console (`PYTHONIOENCODING=utf-8`) if paths contain non-ASCII characters.
