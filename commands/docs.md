---
allowed-tools: Bash(python:*), Bash(pip:*)
description: Sync Claude Code documentation from docs.anthropic.com
argument-hint: [optional: specific page name to sync]
---

# Documentation Sync Command

## Context

Current documentation status: !`ls -la docs/ | head -10`

## Your task

$ARGUMENTS

Sync the latest Claude Code documentation from https://docs.anthropic.com/en/docs/claude-code/

If arguments are provided, try to sync only that specific page. Otherwise, sync all documentation.

Run the documentation sync script located at `sync-docs.py` in the current directory.

After syncing, provide a brief summary of:
- How many files were updated
- Any errors encountered  
- Total documentation pages available locally