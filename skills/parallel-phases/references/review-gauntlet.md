# Reviewer gauntlet

For each task with status `DONE`, dispatch exactly three reviewer agents **in a single message with three parallel tool uses**. All three run in background.

## Diff range

Reviewers analyze the diff between the phase's target branch (from PLAN.md) and the task's worktree branch, **including** the task-agent commit(s). For a typical setup:

```
git diff <target_branch>...phase-N/task-NN-<slug>
```

Pass the exact diff range string in the prompt so the reviewer runs its own git command.

## Dispatch snippet (shape)

All 3 in one message, parallel:

```
Agent(
  description: "bug-finder review of task-NN",
  subagent_type: "bug-finder",
  model: "opus",
  run_in_background: true,
  prompt: <see prompt below, with reviewer=bug-finder>
)

Agent(
  description: "structural review of task-NN",
  subagent_type: "structural-completeness-reviewer",
  model: "opus",
  run_in_background: true,
  prompt: <see prompt below, with reviewer=structural-completeness-reviewer>
)

Agent(
  description: "architecture review of task-NN",
  subagent_type: "architecture-reviewer",
  model: "opus",
  run_in_background: true,
  prompt: <see prompt below, with reviewer=architecture-reviewer>
)
```

Do NOT pass `isolation` -- reviewers are read-only and run in the main working copy.

## Prompt template (common shell for all 3 reviewers)

The reviewer subagent has zero conversation context. Brief it fully.

```
Review the diff for phase-N task <TASK-ID> (<task-slug>).

Repo:       <absolute path to cwd>
Target:     <target_branch>
Task branch: phase-N/task-NN-<slug>
Diff range: git diff <target_branch>...phase-N/task-NN-<slug>

The task's goal (for context; do NOT re-implement):
<one-paragraph summary copied from the task's prompt in PLAN.md>

Task completion commits on the task branch:
<paste `git log <target_branch>..phase-N/task-NN-<slug> --oneline` output>

Your job is a pure review. Do NOT modify files. Do NOT commit. Do NOT spawn subagents.

Write your full report to this exact path (create the file):
  <absolute path to><state-dir>/phase-N/task-NN-review-<REVIEWER_SLUG>.md

Report format:

  # <REVIEWER_TITLE> review: phase-N task-NN (<task-slug>)

  Status: PASS | PASS-WITH-FINDINGS | BLOCKED

  ## Summary
  <1-3 sentences overall verdict>

  ## Findings
  (omit the section if none)

  ### Finding 1
  - Severity: CRITICAL | HIGH | MEDIUM | LOW
  - File:line: <path>:<line> (or "diff-wide")
  - Description: <what is wrong>
  - Recommendation: <concrete fix>

  ### Finding 2
  ...

  ## Notes (optional)
  <anything else the fix agent should know>

Severity guide:
- CRITICAL: correctness bug that will cause data loss / crash / security hole.
- HIGH: correctness bug in a likely-hit path OR a serious structural issue.
- MEDIUM: real issue but narrow impact or easy workaround exists.
- LOW: nice-to-have; style; minor duplication.

Set Status: BLOCKED only if you believe the task should not proceed (actively harmful).
All other cases: PASS-WITH-FINDINGS if any findings, otherwise PASS.

When done, output ONLY a one-line confirmation that the report was written.
```

## Reviewer-specific framing

Prepend each reviewer's prompt with a short framing that matches its specialty. Insert this BEFORE "Your job is a pure review":

### bug-finder
> Focus on logical errors, race conditions, incorrect assumptions, unhandled edge cases,
> off-by-one errors, null/undefined paths, error swallowing, concurrency bugs, and resource
> leaks. Include the path of execution that triggers each bug.

### structural-completeness-reviewer
> Focus on structural integrity of the change: is the change fully integrated, or are there
> dangling references, dead code left from the old state, half-migrated call sites, orphan
> tests, or broken imports? Are there obvious places that SHOULD have been updated but
> weren't? Do NOT review correctness or test quality -- only structural hygiene.

### architecture-reviewer
> Focus on long-term maintainability: does the change respect existing boundaries, introduce
> inappropriate coupling, violate layering, duplicate abstractions, or create new surface
> area that will be hard to evolve? Is the chosen approach proportionate to the problem?

## State updates after dispatch

1. Set task status to `REVIEWING` in STATE.md.
2. Set the `Notes` cell to `bug-finder: IN-FLIGHT | structural: IN-FLIGHT | architecture: IN-FLIGHT`.
3. As each background Agent completes, update the corresponding slot to `DONE`.
4. When all 3 are `DONE` and all 3 files exist on disk, set task status to `REVIEWED`.
5. If any reviewer reports `Status: BLOCKED` in its report header, append `BLOCKED: reviewer <reviewer> on task <task-id> reports BLOCKED` to STATE.md.
