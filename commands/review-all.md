---
description: Run comprehensive code review (structure, performance, bugs) in parallel
argument-hint: [path/to/file]... (optional)
allowed-tools: Bash(git:diff)
---

# Comprehensive Parallel Code Review

Run three specialized review agents simultaneously to analyze code for structural completeness, performance issues, and potential bugs.

## Analysis Target

Determine what to review based on priority:
1. **Arguments provided**: Review specified files/directories
2. **Staged changes exist**: Review staged changes using `!git diff --staged`
3. **Unstaged changes exist**: Review unstaged changes using `!git diff HEAD`
4. **No changes**: Inform user no changes found to review

Inject git context into agents using the appropriate diff command from above.

## Execution

**CRITICAL**: Launch all three agents simultaneously in parallel using a single message with multiple Task tool calls:

1. **structural-completeness-reviewer** - Check implementation completeness, missing edge cases, incomplete error handling
2. **performance-profiler** - Analyze performance bottlenecks, memory usage, optimization opportunities
3. **bug-finder** - Hunt for logical errors, race conditions, unhandled edge cases

Pass the analysis target (file paths or git diff output) to each agent with clear instructions to perform report-only analysis without making changes.

## Synthesis

After all three agents complete, organize findings by severity (NOT by agent):

### Critical Issues
- [Structural] Finding description (file:line)
- [Bugs] Finding description (file:line)
- [Performance] Finding description (file:line)

### Warnings
- [Agent] Finding description (file:line)

### Suggestions
- [Agent] Finding description (file:line)

## Summary

Provide concise actionable recommendations:
- Most critical issues to address first
- Quick wins for performance/stability
- Recommended next steps

Keep synthesis focused on issues requiring human decision or action. Omit low-priority style suggestions unless no substantive issues found.
