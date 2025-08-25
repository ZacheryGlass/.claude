---
allowed-tools: Bash(git:*), Bash(mkdir:*), Bash(ls:*), Bash(pwd:*)
description: Create a new git worktree from the current repository
argument-hint: [branch-name] [path]
---

# Git Worktree Command

## Context

Current repository info: !`git remote get-url origin 2>/dev/null || echo "No remote origin found"`

Current branch: !`git branch --show-current`

Current commit: !`git rev-parse HEAD`

Current working directory: !`pwd`

## Your task

Create a new git worktree based on the arguments provided.

Arguments: $ARGUMENTS

**Expected format:**
- `[branch-name]`: Optional branch name for the new worktree (defaults to current branch name + timestamp)
- `[path]`: Optional path where to create the worktree (defaults to ../repo-name-branch-name)

**Behavior:**
1. If no arguments provided: create worktree at current commit with auto-generated branch name in ../repo-name-branch-timestamp directory
2. If only branch name provided: create worktree at current commit with specified branch name
3. If both branch and path provided: create worktree at current commit with specified branch name and path
4. Always creates worktree at the exact commit that is currently checked out
5. Create the worktree directory if it doesn't exist

**Process:**
1. Get current commit SHA
2. Determine branch name (use argument or auto-generate from current branch + timestamp)
3. Determine the target path for the worktree
4. Create the worktree at current commit using `git worktree add -b <new-branch> <path> HEAD`
5. Display success message with path to new worktree

**Examples:**
- `/worktree` - Creates worktree at current commit with auto-generated branch at ../repo-name-branch-timestamp
- `/worktree feature-branch` - Creates worktree at current commit with branch 'feature-branch'
- `/worktree feature-branch ../feature-worktree` - Creates worktree at current commit in specified path