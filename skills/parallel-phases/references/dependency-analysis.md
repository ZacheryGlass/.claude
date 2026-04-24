# Dependency analysis: grouping tasks into parallel phases

During first-run planning, the orchestrator must decide: which tasks can run together (same phase) and which must wait for another task to complete (later phase).

## Core rule

Two tasks can go in the same phase if and only if they are **independent** by all of these dimensions:

1. **File overlap** — neither modifies files the other modifies.
2. **Resource overlap** — neither consumes an external resource the other does (EC2 instance, CI runner slot, live broker session, shared database, etc.).
3. **Output dependency** — neither needs the output of the other as input.
4. **Semantic dependency** — neither assumes the other has landed (e.g., "run BT on refreshed archive" depends on "refresh the archive").

If any of those fail, serialize them across phases.

## Practical heuristic

Given a candidate task list, build phases greedily:

```
phases = []
remaining = [tasks in user-mentioned order]
while remaining:
    this_phase = []
    for task in remaining:
        if task is independent of every task in this_phase
           AND task has no output dependency on tasks in later remaining:
            this_phase.append(task)
    phases.append(this_phase)
    remaining = remaining - this_phase
```

Tie-break: when two tasks conflict, put the **longer-running** one first (less wasted wall-clock waiting).

## File-scope overlap check

Each task in PLAN.md has a `scope` field. Two tasks conflict if:

- Any scope entry of task A is a prefix of any scope entry of task B, or vice versa.
- Both task scopes include a glob like `src/*.c` that could cover the same file.

When scope is ambiguous, **serialize**. Worktree merges fail on file-level overlap, and fixing the phase mid-run costs more than splitting it upfront.

## External-resource conflicts

Tasks that contend for the same resource must serialize, even if their file scopes don't overlap:

- Live paper trading / EC2 smoke runs — only one at a time on the same host.
- Backtester runs that share an input archive — fine if read-only; serialize if any task mutates the archive.
- Database migrations — serialize all of them.
- Network-expensive scrapes — check quota.
- GPU jobs — match to available GPUs.

If in doubt, annotate the task with a `resource: <name>` hint and serialize tasks that share a resource name.

## Task granularity guidance

When extracting tasks from conversation, aim for:

- **Large enough** that per-task overhead (worktree + 3 reviewers + fix agent + merge) pays back. Aim for ≥30 minutes of agent work per task.
- **Small enough** that a single task has a clear, committable outcome. Split "refactor module X" into multiple tasks if they span unrelated concerns.
- **Self-contained** — the task prompt must be actionable without conversation context.

If a task is small (<10 LOC, <5 minute change), consider bundling it into a larger sibling task rather than running it through the full gauntlet.

## Minimum useful phase size

A phase with 1 task is legal but wastes the parallelism benefit. If the dependency graph forces a 1-task phase, consider whether:

- That task can be merged with another task in an adjacent phase, or
- Another task the user didn't mention should be added as a sibling.

However, DO NOT invent tasks the user didn't ask for just to fill phases. A 1-task phase is fine if that's what the user's work requires.

## Example decisions

| User mentioned | Phase assignment | Reason |
|---|---|---|
| "delete dead strategy" + "optimize tick reader" | Phase 1 parallel | Different files (strategy/ vs io/), no semantic overlap |
| "optimize tick reader" + "re-run BT with optimized reader" | 2 phases | BT run depends on tick reader being on target_branch |
| "paper smoke on EC2" + "BT re-run locally" | Phase 1 parallel | Different resources (EC2 vs local) |
| "paper smoke on EC2" + "live smoke on EC2" | 2 phases | Same resource (EC2) |
| "v4 post-mortem log analysis" + "delete dead code" | Phase 1 parallel | One is read-only analysis, one is code edit; no overlap |
| "refactor auth middleware" + "fix unrelated UI bug" | Phase 1 parallel | Disjoint scope (backend/auth vs frontend/) |
| "fix bug in parser" + "refactor parser" | 2 phases | Same file; conflict likely |

## When the dependency graph is unclear

If extraction from conversation leaves ambiguous dependencies:

1. Ask the user (via AskUserQuestion during planning) to clarify: "Is task X independent of task Y?"
2. Or: default to serializing. The cost of a too-serial plan is slower wall-clock; the cost of a too-parallel plan is merge conflicts that block the phase.
