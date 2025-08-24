---
allowed-tools: Bash(git:*)
description: Commit changes with conventional commit format
argument-hint: [optional: "all" to stage all changes, or commit type/message]
---

# Git Commit Command

## Context

Current git status: !`git status --porcelain`

Staged changes: !`git diff --cached --name-only`

## Your task

$ARGUMENTS

You need to commit changes using conventional commit format. 

**Conventional Commit Format:**
```
<type>(<scope>): <description>

[optional body]

[optional footer(s)]
```

**Common types:**
- feat: new feature
- fix: bug fix  
- docs: documentation changes
- style: formatting, missing semicolons, etc
- refactor: code change that neither fixes bug nor adds feature
- test: adding missing tests
- chore: changes to build process or auxiliary tools

**Behavior:**
- If no arguments: commit staged changes with conventional format
- If "all" argument: stage all unstaged changes, then commit with conventional format
- If custom message provided: use it directly

**Process:**
1. Check git status to understand what changes exist
2. If "all" argument provided, stage all changes with `git add .`
3. Generate appropriate conventional commit message based on the changes
4. Commit with the generated or provided message
5. Show the final commit result

Make sure to analyze the changes to determine the appropriate commit type and generate a meaningful description.