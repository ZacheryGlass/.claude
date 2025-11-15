---
allowed-tools: Bash(git add:*), Bash(git status:*), Bash(git commit:*), Bash(git diff:*)
argument-hint: [description] | [multi-commit request]
description: Create intelligent git commits based on conversation context
model: haiku
---

## Context

- Current git status: !`git status`
- Current git diff (staged and unstaged changes): !`git diff HEAD`
- Current branch: !`git branch --show-current`
- Recent commits: !`git log --oneline -10`

## Your Task

Create git commit(s) intelligently based on the request and conversation context.

### Behavior Based on Arguments

**No arguments (`/commit`):**
- ONLY commit files that are directly related to our recent conversation work
- Review recent conversation messages to identify which files we've been working on together
- Exclude any unrelated changes that happen to be in the working tree
- If unclear which files are "current work", ask the user for clarification

**With description (`/commit [description]`):**
- ONLY commit files that match the provided description
- Use the description to filter which changed files should be included
- Example: `/commit updates to slash commands` → only commit files in commands/ directory

**Multi-commit request (`/commit do two commits for X and Y`):**
- Parse the request to understand how many commits are needed
- Create separate commits for each described change set
- Example: `/commit do two commits, one for slash commands and one for skill-creator` → create 2 commits

### Critical Rules

1. **Never commit everything blindly** - Always filter based on conversation context or description
2. **Stage selectively** - Use `git add` to stage only the relevant files for each commit
3. **Use conversation history** - Look at recent messages to understand what we've been working on
4. **Ask when ambiguous** - If it's unclear what to commit, ask the user
5. **Simple messages** - Write clear, descriptive commit messages (not conventional format)

### Commit Message Guidelines

- Be concise but descriptive
- Focus on "why" and "what" changed
- Use imperative mood (e.g., "Add feature" not "Added feature")
- Follow the project's existing commit message style from git log
- Never include metrics (e.g., "100x improvement", "removed 350 lines", "180% faster")
- Avoid sales pitch language - focus on what changed, not how impressive it is