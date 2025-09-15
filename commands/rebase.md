---
allowed-tools: Bash(git:*)
description: Rebase current branch onto remote upstream branch with smart stash handling
argument-hint: [optional: target-branch-name]
---

# Git Rebase Command

## Context

Current git status: !`git status --porcelain`

Current branch: !`git branch --show-current`

Current commit: !`git rev-parse HEAD`

Remote tracking branch: !`git rev-parse --abbrev-ref @{upstream} 2>/dev/null || echo "No upstream branch"`

Remote status: !`git remote -v | head -1`

Recent commits: !`git log --oneline -5`

## Your task

Rebase the current branch onto the specified remote upstream branch with automatic stash management.

Arguments: $ARGUMENTS

**Expected format:**
- `[target-branch]`: Optional target branch name (e.g., "main", "develop", "feature/example")

**Behavior:**
1. If no arguments provided: rebase onto the remote tracking branch of current branch (e.g., `origin/current-branch`)
2. If branch name provided: rebase onto `origin/[branch-name]`
3. Always stash uncommitted changes before rebasing if working directory is dirty
4. Always fetch remote before rebasing to ensure latest state
5. Pop stash after successful rebase and handle any conflicts

**Process:**
1. Check if there are uncommitted changes and stash them if needed
2. Fetch from remote to get latest changes
3. Determine target branch (argument or upstream)
4. Perform the rebase onto `origin/[target-branch]`
5. If rebase successful and stash was created, pop the stash
6. Handle conflicts at each step with clear guidance

**Examples:**
- `/rebase` - Rebase current branch onto its remote tracking branch
- `/rebase main` - Rebase current branch onto `origin/main`
- `/rebase feature/example` - Rebase current branch onto `origin/feature/example`

**Important Requirements:**
- Always fetch before rebasing to ensure you have the latest remote state
- Stash uncommitted changes to avoid losing work
- Provide clear feedback at each step
- Handle rebase conflicts by providing guidance to user
- Handle stash pop conflicts by providing guidance to user
- Never proceed if in the middle of an existing rebase operation

**Error Handling:**
- Check for existing rebase in progress before starting
- Abort if no remote is configured
- Provide clear instructions if rebase conflicts occur
- Provide clear instructions if stash pop conflicts occur
- Ensure repository is left in a clean state even on failure