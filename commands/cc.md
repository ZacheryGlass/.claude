---
allowed-tools: Bash(git add:*), Bash(git status:*), Bash(git commit:*), Bash(git diff:*)
argument-hint: [description] | [multi-commit request]
description: Create intelligent conventional commits based on conversation context
---

## Context

- Current git status: !`git status`
- Current git diff (staged and unstaged changes): !`git diff HEAD`
- Current branch: !`git branch --show-current`
- Recent commits: !`git log --oneline -10`

## Your Task

Create conventional git commit(s) intelligently based on the request and conversation context.

### Behavior Based on Arguments

**No arguments (`/cc`):**
- ONLY commit files that are directly related to our recent conversation work
- Review recent conversation messages to identify which files we've been working on together
- Exclude any unrelated changes that happen to be in the working tree
- If unclear which files are "current work", ask the user for clarification

**With description (`/cc [description]`):**
- ONLY commit files that match the provided description
- Use the description to filter which changed files should be included
- Example: `/cc updates to slash commands` → only commit files in commands/ directory

**Multi-commit request (`/cc do two commits for X and Y`):**
- Parse the request to understand how many commits are needed
- Create separate commits for each described change set
- Example: `/cc do two commits, one for slash commands and one for skill-creator` → create 2 commits

### Critical Rules

1. **Never commit everything blindly** - Always filter based on conversation context or description
2. **Stage selectively** - Use `git add` to stage only the relevant files for each commit
3. **Use conversation history** - Look at recent messages to understand what we've been working on
4. **Ask when ambiguous** - If it's unclear what to commit, ask the user
5. **Conventional format required** - All commits MUST follow conventional commit format

### Conventional Commit Format

**Required format**: `type(scope): subject`

**Common types:**
- `feat`: New feature
- `fix`: Bug fix
- `refactor`: Code refactoring (no functional changes)
- `docs`: Documentation changes
- `chore`: Maintenance tasks, tooling, configs
- `test`: Test changes
- `style`: Code formatting, whitespace
- `perf`: Performance improvements

**Scope guidelines:**
- Use file/directory name or feature area
- Examples: `skills`, `commands`, `hooks`, `agents`
- Keep it short and meaningful

**Subject guidelines:**
- Use imperative mood (e.g., "add feature" not "added feature")
- Don't capitalize first letter
- No period at the end
- Be concise but descriptive

**Examples:**
- `feat(commands): add conversation-aware commit logic`
- `refactor(skills): restructure skill-creator into subdirectory`
- `fix(hooks): prevent duplicate execution on commit`
- `chore(deps): update python dependencies`