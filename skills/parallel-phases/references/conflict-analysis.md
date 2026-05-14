# Merge-Conflict Analysis Protocol

Parallel worktree agents produce independent branches that merge into a phase integration branch. File-level overlap between branches in the same phase causes merge conflicts that BLOCK the phase overnight.

## High-risk conflict sources

### Build configuration files
Single-line variable lists are the #1 conflict source:
- **Makefile**: `SRCS = ...`, `TEST_SRCS = ...`, `BT_SHARED_SRCS = ...` on single lines
- **package.json**: `dependencies`, `scripts` objects
- **CMakeLists.txt**: `add_executable()`, `target_sources()` calls
- **Cargo.toml**: `[dependencies]` section

Two tasks appending to the same variable/section will always conflict.

### Shared type definitions
Header files with enums, structs, or type aliases modified by multiple tasks.

### Test infrastructure
Shared test helpers, fixtures, or setup/teardown functions.

## Mitigation strategies (prefer parallelism)

### Strategy 1: Designate a config owner
One task in the phase owns ALL build-config changes. Other tasks write their source/test files but do NOT touch the Makefile/package.json. The config-owner task's prompt includes entries for all tasks' files.

Tradeoff: config-owner task must know sibling tasks' output filenames in advance. Use when filenames are predictable.

### Strategy 2: Multi-line refactor
If the build config uses a single-line list, add a preliminary task (or include in the first phase) that refactors it to multi-line format. Multi-line additions to different line ranges merge cleanly.

Tradeoff: adds a setup phase. Use when the project will have multiple future parallel-phases runs.

### Strategy 3: Combine tasks
Merge two conflicting tasks into one larger task. Eliminates the conflict entirely.

Tradeoff: larger tasks are harder for agents and produce bigger diffs for reviewers. Use when the tasks are naturally related (e.g., "add enum value" + "add tests for that enum value").

### Strategy 4: Serialize into separate phases
Move conflicting tasks to consecutive phases.

Tradeoff: loses parallelism. Use ONLY as last resort when the above strategies don't apply.

## Analysis checklist

For each pair of tasks in the same candidate phase:

1. List every file each task will modify (not just read)
2. Check for path-prefix overlap (e.g., both touch `src/types/`)
3. Check for build-config overlap (both add to SRCS/TEST_SRCS)
4. Check for shared header overlap (both modify same .h)
5. For each overlap: choose mitigation (1-4 above)
6. Document the choice in the PLAN.md rationale

## Output

Record conflict analysis results in the phase's `Rationale:` line in PLAN.md:

```
Rationale: Tasks A and B both add test files; Task A owns Makefile TEST_SRCS
for both. Task C touches disjoint files. No serialization needed.
```
