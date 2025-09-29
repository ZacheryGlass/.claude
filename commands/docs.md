---
description: Complete documentation workflow: review, implement fixes, and commit changes
argument-hint: [optional: specific file or directory to focus on]
---

# Documentation Workflow Command

## Context

Current working directory: !`pwd`

Recent changes: !`git log --oneline -5`

Documentation files: !`ls *.md 2>/dev/null`

## Your task

$ARGUMENTS

Execute a complete documentation workflow in three phases:

## Phase 1: Documentation Review
Use the doc-reviewer agent to analyze the current state of documentation:
- Identify code changes that need corresponding documentation updates
- Find documentation that has become outdated
- Suggest areas where new documentation should be added
- Review documentation quality and consistency

## Phase 2: Implement Changes
Use the doc-implementer agent to execute the review recommendations:
- Update existing documentation files
- Create new documentation where needed
- Fix broken links and references
- Ensure consistent formatting and quality

## Phase 3: Commit Changes
Use the committer agent to create a conventional commit for all documentation improvements.

If arguments are provided, focus the entire workflow on the specified files or directories. Otherwise, perform a comprehensive documentation review and update of the entire project.

Execute each phase sequentially, ensuring each agent completes its work before proceeding to the next phase.