---
allowed-tools: Bash(git:*)
description: Create a new git worktree that tracks the remote default branch
argument-hint: (no arguments needed)
---

# Git Worktree Command

## Context

Current repository info: !`git remote get-url origin 2>/dev/null || echo "No remote origin found"`

Current branch: !`git branch --show-current`

Existing worktrees: !`git worktree list`

Existing branches: !`git branch --list 'worktree*'`

Default remote branch: !`git remote show origin 2>/dev/null | grep "HEAD branch" | cut -d: -f2 | xargs || git branch -r | grep -E 'origin/(main|master)' | head -1 | sed 's/.*origin\///'`

## Your task

Create a new git worktree with an auto-generated branch name that tracks the remote default branch.

**Behavior:**
1. Determine the default remote branch (origin/main or origin/master)
2. Find all existing branches named `worktree*` to determine the next available number
3. Create a new branch named `worktreeN` where N is the next sequential number (starting at 1)
4. Create the worktree at a path like `/worktreeN` 
5. Set the new local branch to track the remote default branch as upstream (i.e. `origin/main`)

**Process:**
1. Fetch latest changes from remote: `git fetch origin`
2. Determine the default remote branch:
   - First, try `git remote show origin | grep "HEAD branch"` to find the repository's default branch name
   - Verify the branch exists in remote with `git branch -r`
   - If the default branch doesn't exist remotely or cannot be determined, check for origin/main, then origin/master
   - If neither exists, fail with a clear error message: "Unable to determine default remote branch. Please ensure origin/main or origin/master exists."
3. List existing worktree branches: `git branch --list 'worktree*'`
4. Determine next available number:
   - Parse the branch names to find the highest number used
   - Use the next sequential number (e.g., if worktree1 exists, use worktree2)
   - If no worktree branches exist, start with worktree1
5. Create the worktree tracking the remote branch:
   - Use: `git worktree add --track -b worktreeN /worktreeN origin/branch-name`
   - This creates the branch, sets up tracking, and creates the worktree directory
   - The -b flag creates a new branch named worktreeN
   - The --track flag ensures upstream tracking is configured
   - Specifying origin/branch-name as the starting point sets the branch to that commit and configures the upstream
6. Display success message with:
   - The new branch name (worktreeN)
   - The absolute path to the worktree
   - The upstream tracking branch (origin/main or origin/master)
   - Confirmation that tracking is set up correctly

**Examples:**
- `/worktree` - Creates worktree1 at /worktree1 tracking origin/main (or origin/master)
- `/worktree` (when worktree1 exists) - Creates worktree2 at /worktree2 tracking origin/main (or origin/master)

**Important Notes:**
- The command takes NO arguments - branch names are always auto-generated
- The new branch always tracks the remote default branch (origin/main or origin/master)
- Each worktree gets a numbered branch name starting from 1
- The worktree directory is created in the parent directory of the current repository