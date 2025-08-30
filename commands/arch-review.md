---
description: Review architecture of specified path(s), or staged/unstaged git changes.
argument-hint: [path/to/directory]... (optional)
allowed-tools: Bash(git:diff)
---
Use the **architecture-reviewer** subagent to conduct a thorough architectural review.

Your analysis target is determined by the following rules:

1.  **If file or directory paths are provided as arguments**, your review must focus exclusively on them: **$ARGUMENTS**

2.  **If no arguments are provided**, your analysis MUST focus on the recent git changes provided below. Please prioritize the **'Staged Changes'**. If that section is empty, then analyze the **'Unstaged Changes'**.

### Context from Git (if no arguments provided)

**Staged Changes (Priority 1):**
```diff
!git diff --staged
```

**Unstaged Changes (Priority 2):**
```diff
!git diff HEAD
```
---
*Your final report should evaluate the code against the principles of Separation of Concerns, SOLID, Scalability, and Maintainability.*