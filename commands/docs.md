---
description: Run documentation updater to analyze and improve project documentation
argument-hint: [optional: specific file or directory to focus on]
---

# Documentation Updater Command

## Context

Current working directory: !`pwd`

Recent changes: !`git log --oneline -5`

Documentation files: !`ls *.md 2>/dev/null`

## Your task

$ARGUMENTS

Launch the doc-updater agent to analyze the current state of documentation and provide recommendations for improvements.

The doc-updater agent will:
- Identify code changes that need corresponding documentation updates
- Find documentation that has become outdated
- Suggest areas where new documentation should be added
- Review documentation quality and consistency

If arguments are provided, focus the analysis on the specified files or directories. Otherwise, perform a comprehensive documentation review of the entire project.

Use the Task tool to launch the doc-updater agent with appropriate context about the current project state.