# PLAN.md and STATE.md Format

## PLAN.md

```yaml
---
target_branch: <branch name, usually main>
test_command: <shell command for phase gate, e.g. "make clean && make test">
state_dir: <absolute path to ~/.claude/parallel-phases/<project-hash>/>
total_phases: <N>
generated_at: <ISO-8601>
source: <"conversation" | path to plan document>
---
```

### Phase sections

```markdown
## Phase N: <short name>

Rationale: <why these tasks are grouped; what makes them independent; any
conflict mitigations applied (e.g., "Task A owns Makefile for both")>

### Tasks

#### task-NN-<slug>
- agent_type: general-purpose
- model: opus
- isolation: worktree
- scope: <file paths this task modifies -- used for conflict prediction>
- prompt: |
    <self-contained prompt per references/prompt-template.md>
```

### Field defaults

| Field | Default | Override when |
|---|---|---|
| agent_type | general-purpose | Explore for read-only research |
| model | opus | sonnet for mechanical <100 LOC changes. Never haiku. |
| isolation | worktree | Omit only for read-only research tasks |

### Concurrency limits

- Max 8 tasks per phase. If >8, split into waves (Phase 1A, 1B).
- Max 16 in-flight agents globally (tasks + reviewers + fix agents).

## STATE.md

```markdown
# parallel-phases STATE

Last update: <ISO-8601>
Current phase: <N>
Target branch: <from PLAN.md>
Test command: <from PLAN.md>

## Progress

- [ ] Phase 1: <name> (<N> tasks)
- [ ] Phase 2: <name> (<N> tasks)

## Phase 1: <name> -- PENDING

| Task | Status | Branch | Model | Notes |
|---|---|---|---|---|
| task-01-<slug> | PENDING | - | opus | |
| task-02-<slug> | PENDING | - | opus | |

## Log

- <ISO-8601> -- pre-built plan (N tasks, M phases)
```

Status values: PENDING, IN-FLIGHT, DONE, REVIEWING, REVIEWED, FIXING, FIXED, FAILED, FIX-FAILED, RETRY-NEEDED, MERGED.

## State location

State lives at `~/.claude/parallel-phases/<project-hash>/`, outside the repo. No .gitignore entry needed. The `state_dir` field in PLAN.md frontmatter records the absolute path so agents and reviewers can find reports.
