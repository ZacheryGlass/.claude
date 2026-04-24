# STATE.md template

STATE.md is the dashboard the orchestrator reads and writes on every invocation. It must be regenerated (or edited in place) whenever task/phase status changes. Keep it concise enough to scan in seconds.

## Structure

```markdown
# parallel-phases STATE

Last update: <ISO-8601 timestamp>
Current phase: <N>
Target branch: <from PLAN.md>
Test command: <from PLAN.md>

## Phase 1: <name> -- <PLANNING|DISPATCHING|IN-FLIGHT|REVIEWING|FIXING|MERGING|COMPLETE>

| Task | Status | Branch | Model | Notes |
|---|---|---|---|---|
| task-01-<slug> | FIXED | phase-1/task-01-<slug> | opus | 2 findings addressed |
| task-02-<slug> | REVIEWING | phase-1/task-02-<slug> | sonnet | bug-finder DONE, structural RETRY-NEEDED, architecture IN-FLIGHT |

## Phase 2: <name> -- PENDING

| Task | Status | Branch | Model | Notes |
|---|---|---|---|---|
| task-03-<slug> | PENDING | - | opus | |

## Log

- 2026-04-23T18:30:00Z -- initialize plan (3 tasks, 2 phases)
- 2026-04-23T18:32:10Z -- phase 1 dispatched: task-01, task-02
- 2026-04-23T19:05:00Z -- task-01 DONE (commit abc123)
- 2026-04-23T19:05:00Z -- reviewers dispatched for task-01
- ...
```

## Status values

Applied per-task. Transitions are monotonic unless explicitly reset by a human.

| Status | Meaning | Next action |
|---|---|---|
| `PENDING` | Not yet dispatched | Dispatch task agent |
| `IN-FLIGHT` | Task agent running | Wait for Agent completion notification |
| `DONE` | Task agent reported success; commit on task branch | Dispatch 3 reviewers |
| `FAILED` | Task agent failed / produced no commit | Note in log; reviewers still run on (empty) diff. User may reset to PENDING. |
| `REVIEWING` | 1-3 reviewers in flight | Wait for all 3 reports |
| `REVIEWED` | All 3 reviewer reports exist | Dispatch fix agent |
| `FIXING` | Fix agent running | Wait for fix commit + fix summary |
| `FIXED` | Fix commit landed (or no-op fix) | Phase can progress to merge once all tasks in phase are FIXED |
| `FIX-FAILED` | Fix agent failed | BLOCK phase; requires user intervention |
| `RETRY-NEEDED` | Transient failure; re-dispatch next invocation | Orchestrator re-dispatches on next run |
| `MERGED` | Task branch successfully merged into phase integration | Per-phase final state |

## Reviewer sub-status

Within a task row's `Notes` column during REVIEWING, use a compact form:

```
bug-finder: DONE | structural: RETRY-NEEDED | architecture: IN-FLIGHT
```

When all three show `DONE`, flip the task status to `REVIEWED`.

## BLOCKED line

When any hard-exit condition fires, append a line at the top of STATE.md (immediately under the header) like:

```markdown
**BLOCKED:** phase 1 test gate failed -- see .parallel-phases/phase-1/test-log.txt
```

The orchestrator checks for this literal prefix `BLOCKED:` in its hard-exit check. User removes the line manually after resolving.

## Log discipline

Append one line per significant state change. Keep the log append-only (never rewrite past entries). Use ISO-8601 timestamps. Trim logs older than the previous completed phase if the file grows beyond ~200 lines -- but preserve the most recent phase's log in full.

## Gate status summary (optional block near top)

For at-a-glance status when STATE.md is viewed by a human:

```markdown
## Progress

- [x] Phase 1: Cleanup + perf (2 tasks, merged at abc123)
- [ ] Phase 2: Post-cleanup validation (1 task, in progress)
```

Use checkboxes per phase. The orchestrator does not parse this block; it's for the human reader.
