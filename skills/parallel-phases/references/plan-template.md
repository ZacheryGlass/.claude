# PLAN.md template

PLAN.md is written once during first-run planning, reviewed by the user, and treated as immutable during execution. Re-planning means deleting `.parallel-phases/` and starting over.

## Top-level fields

```yaml
---
target_branch: <branch the user was on when /parallel-phases was invoked>
test_command: <shell command to run after each phase merge; or "none">
gitignore_state: true                  # default true; false leaves .parallel-phases/ untracked via .gitignore
total_phases: <N>
generated_at: <ISO-8601 timestamp>
source: conversation                    # how the plan was derived
---
```

## Phase section

Each phase has a heading, a one-line purpose, and a list of tasks. All tasks in a phase run in parallel.

```markdown
## Phase 1: <short descriptive name>

Rationale: <one-line why these tasks are grouped; what makes them independent of each other>

### Tasks

#### task-01-<slug>
- agent_type: general-purpose
- model: opus
- isolation: worktree
- scope: <files / modules expected to be touched; used for dependency analysis and merge prediction>
- prompt: |
    <self-contained prompt for the task agent. This is what gets passed to Agent's `prompt` param. The subagent has zero conversation context, so the prompt must brief it fully: what to do, why, relevant file paths, constraints, success criteria, how to report completion.>

#### task-02-<slug>
- agent_type: general-purpose
- model: opus
- isolation: worktree
- scope: ...
- prompt: |
    ...
```

## Field reference

| Field | Required | Default | Notes |
|---|---|---|---|
| `agent_type` | no | `general-purpose` | Any valid subagent_type. For investigation-heavy tasks consider `Explore`. |
| `model` | no | `opus` | Use `sonnet` for mechanical/low-risk work to save cost. Never `haiku`. |
| `isolation` | no | `worktree` | Always `worktree` for code-modifying tasks. Only set `none` for read-only research tasks. |
| `scope` | recommended | - | File-path prefixes or module names. Used by the orchestrator to predict merge conflicts. |
| `prompt` | yes | - | Self-contained task brief. Must produce a commit on the task's branch to be considered DONE. |

## Phase >8 tasks: split into waves

If dependency analysis places more than 8 tasks in a single phase, break into sub-waves:

```markdown
## Phase 1: <name>

### Wave 1A (tasks 1-5)
#### task-01-<slug>
...

### Wave 1B (tasks 6-10)
#### task-06-<slug>
...
```

The orchestrator dispatches one wave at a time. A wave completes (all tasks FIXED) before the next wave's tasks start, but reviewers and fix agents still run parallel within each wave.

## Example: small real plan

```markdown
---
target_branch: wip
test_command: make test
gitignore_state: true
total_phases: 2
generated_at: 2026-04-23T18:30:00Z
source: conversation
---

## Phase 1: Cleanup + perf (independent, safe in parallel)

Rationale: Both tasks touch distinct files and have no runtime interaction.

### Tasks

#### task-01-delete-dead-feature
- agent_type: general-purpose
- model: sonnet
- isolation: worktree
- scope: src/features/legacy_export.*, src/features/registry.ts, tests/features/
- prompt: |
    Delete the LEGACY_EXPORT feature end-to-end. Remove the enum value, the
    source files, any references in the feature registry, and the tests
    that target it. Verify `npm test` passes. Commit as
    `refactor(features): remove unused LEGACY_EXPORT feature`.

#### task-02-optimize-csv-parser
- agent_type: general-purpose
- model: opus
- isolation: worktree
- scope: src/io/csv_parser.ts, src/io/csv_parser.test.ts, bench/
- prompt: |
    Optimize the csv_parser parse hot path. Current throughput is ~X; target
    2-4x. Profile with the existing bench harness in bench/csv_parser_bench.ts.
    Preserve exact semantics -- add a regression test capturing current output
    on the first 1000 rows of the sample fixture. Commit as
    `perf(io): speed up csv_parser parse path`.

## Phase 2: Post-cleanup validation (depends on Phase 1)

Rationale: The integration re-run consumes output of Phase 1's cleaned
codebase and faster parser. Must wait for Phase 1 integration.

### Tasks

#### task-03-rerun-integration-suite
- agent_type: general-purpose
- model: opus
- isolation: worktree
- scope: integration/, analysis/
- prompt: |
    Re-run the full integration suite against the refreshed fixtures in
    `integration/fixtures/`. Write results to
    `integration/results/post-cleanup-rerun.md` with per-suite pass/fail
    and any regressions vs. the previous baseline. Commit.
```

## Generating PLAN.md from conversation context (for the orchestrator, on first run)

When drafting PLAN.md from conversation context:

1. Extract every discrete work item the user has mentioned. Prefer items the user has explicitly flagged as "to do" or "want to run" over speculative ideas.
2. For each item, write a self-contained prompt. The subagent will not see the conversation, so include: the goal, relevant file paths, constraints mentioned in conversation, how to report completion.
3. Use `references/dependency-analysis.md` to group items into phases.
4. Favor fewer, larger phases over many tiny ones -- each phase-end merge has fixed overhead (review + fix + merge + test).
5. Favor safe-in-parallel over aggressive parallelism -- if unsure, serialize.
6. Mark each task's expected file `scope` explicitly; the orchestrator uses it to predict merge risk.
7. Pick model per task: `sonnet` for mechanical (<100 LOC change, no new logic), `opus` for design/logic changes.
