---
description: Use bug-finder agent to hunt for logical errors and potential runtime issues
argument-hint: [optional: specific file, directory, or function to focus on]
---

# Bug Finder Command

## Context

Current working directory: !`pwd`

Recent changes: !`git log --oneline -5`

Modified files (unstaged): !`git diff --name-only`

Staged files: !`git diff --cached --name-only`

## Your task

$ARGUMENTS

Use the bug-finder agent to perform a thorough bug hunt and code analysis.

The bug-finder agent will:
- Hunt for logical errors and runtime issues
- Identify race conditions and concurrency problems
- Find unhandled edge cases and error conditions
- Detect potential null pointer dereferences
- Analyze error handling and exception paths
- Look for off-by-one errors and boundary conditions
- Check for resource leaks and memory issues

**Focus Area:**
- If arguments are provided, focus the analysis on the specified files, directories, or functions
- If no arguments provided, analyze recent changes from git diff and staged files
- If no recent changes, perform a broader analysis of critical code paths

**Analysis Scope:**
The agent will go beyond syntax and style to focus on:
- Logic correctness and potential runtime behavior
- Edge cases that could cause failures
- Error handling completeness
- Security vulnerabilities
- Performance bottlenecks that could cause issues

Use the Task tool to launch the bug-finder agent with appropriate context about what code to analyze.