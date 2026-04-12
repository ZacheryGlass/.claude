---
name: arewedone-g
description: Run structural completeness review via Gemini CLI. Use this skill to check if recent changes are fully integrated and no technical debt was introduced. This offloads the token-heavy review process to Gemini, saving Claude tokens while maintaining the exact same behavioral standards.
---

# Arewedone-g (Gemini Structural Completeness Review)

## Step 1 — Write context summary

Before running the script, write a 2-4 sentence summary of what we've been working on to `/tmp/arewedone-g-context.txt`. Include:
- What was changed and why
- Which files or modules were touched
- Any known rough edges or areas of concern to look at closely

Example write command:
```bash
echo "We refactored the fill model in src/trading/execution/fill_model.c to fix a timestamp domain mismatch. Changed placed_ns to use clock_realtime_ns for epoch comparisons. Also updated main.c to set use_realtime_placed=true for paper trading." > /tmp/arewedone-g-context.txt
```

## Step 2 — Run the review

```bash
python ~/.claude/skills/arewedone-g/scripts/arewedone_task.py --extra-context /tmp/arewedone-g-context.txt
```

To use a specific Gemini model, pass `--model`:

```bash
python ~/.claude/skills/arewedone-g/scripts/arewedone_task.py --extra-context /tmp/arewedone-g-context.txt --model gemini-3-flash-preview
```

Default model: `gemini-3.1-pro-preview`

The script will combine your summary, the current git worktree changes (file names + last few commits), and the structural-completeness-reviewer instructions, then hand everything to Gemini.

## Step 3 — Address review comments

After the script returns findings, immediately make any recommended updates to the codebase.

## Step 4 — Commit

Use the committer skill to create a conventional commit for all completed changes.
