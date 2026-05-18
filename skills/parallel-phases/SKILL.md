---
name: parallel-phases
description: End-to-end orchestrator for multi-task parallel work. Phase 1 (setup) gathers code intelligence, analyzes merge-conflict risks, groups tasks into maximally-parallel phases, writes enriched self-contained agent prompts, and generates PLAN.md + STATE.md. Phase 2 (execution) dispatches Opus agents in worktrees with a per-task review-gauntlet sub-skill pass and auto-fix commits, then a doc-update agent at completion. Asks explicit permission before starting autonomous execution. Resilient to /clear via file-backed state. Triggers on /parallel-phases, "parallelize these tasks", "run these in parallel phases".
---

# Parallel Phases Orchestrator

End-to-end orchestrator for multi-task parallel work. Two phases in a single skill invocation:

1. **Setup** (interactive): identify tasks, gather code intelligence, analyze conflicts, group into parallel phases, write enriched prompts, generate PLAN.md + STATE.md, present for approval.
2. **Execution** (autonomous): dispatch agents, run `/review-gauntlet` sub-skill per task, apply fixes, merge phases, update docs. Runs unattended until complete or blocked.

An explicit permission gate separates setup from execution.

## Scope

- **Target project**: current working directory (`<cwd>`). All paths below are relative to it unless absolute.
- **State directory**: `~/.claude/parallel-phases/<project-hash>/`. Computed on first invocation. Does NOT live in the repo -- no .gitignore needed.
- **Read `<cwd>/CLAUDE.md` once at session start** if not already in context -- it holds project-specific conventions.

### Computing the state directory

On first invocation, derive the state directory path:

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
PROJECT_HASH=$(echo -n "$REPO_ROOT" | md5sum | head -c 12)
STATE_DIR="$HOME/.claude/parallel-phases/$PROJECT_HASH"
```

Write a `project.json` into the state dir on creation:
```json
{"repo": "<absolute repo root>", "created": "<ISO-8601>"}
```

This allows multiple projects to use parallel-phases without collision, and lets the user find which state dir belongs to which project.

Throughout this document, `<state-dir>` refers to this computed path.

## Entry point

On every invocation, compute the state directory, then check which mode applies:

1. **`<state-dir>/COMPLETE.md` exists** -> print `PARALLEL-PHASES COMPLETE at <hash>` and exit.
2. **`<state-dir>/STATE.md` exists with tasks** -> skip to "Execution phase" (decision tree).
3. **`<state-dir>` does not exist or has no STATE.md** -> run "Setup phase" below.

This means: first invocation runs setup. Subsequent invocations (after approval) run execution. Resume after `/clear` picks up from file-backed state.

---

## Setup phase

Run when `<state-dir>/PLAN.md` does not exist (or needs to be rebuilt).

### 1. Identify tasks

Extract discrete work items from:
- The user's message / skill arguments
- Recent conversation context
- A referenced plan document (if the user points to one)

If the task list is ambiguous or incomplete, use `AskUserQuestion` to clarify. Ask about:
- Scope boundaries (what's in, what's out)
- Priority ordering (if more tasks than can reasonably run overnight)
- Constraints (files that must not change, features that must not break)

Each task needs: a clear goal, expected file scope, and acceptance criteria.

### 2. Gather code intelligence

For each task, spawn an `Explore` agent (or read directly for small scopes) to collect:
- Exact file paths and line numbers for code that will be read or modified
- Current function signatures and short code excerpts at modification points
- Existing test patterns (how tests are structured, helper functions available)
- Build system structure (how source/test files are registered -- e.g., Makefile variables, package.json scripts)

This is the critical step that makes prompts self-contained. Without it, agents waste time rediscovering the codebase or make incorrect assumptions.

### 3. Analyze merge-conflict risk

Read `references/conflict-analysis.md` for the full protocol.

Key checks:
- Identify shared files that multiple tasks would modify (build config, type definitions, shared headers)
- For each conflict, choose a mitigation: combine tasks, serialize into separate phases, or designate one task as the Makefile/config owner
- Prefer preserving parallelism over serializing. Only serialize when file-level overlap is unavoidable.

### 4. Group tasks into phases

Read `references/dependency-analysis.md` for grouping heuristics.

Rules:
- Tasks with no file overlap and no semantic dependency go in the same phase (parallel).
- Tasks that produce outputs consumed by later tasks go in earlier phases.
- When conflict mitigation allows parallel execution (e.g., one task owns the build config), keep tasks parallel.
- Aim for fewer, larger phases. Each phase has fixed overhead (review + fix + merge + test).

### 5. Write enriched task prompts

Read `references/prompt-template.md` for the full template.

Each task prompt must be completely self-contained -- the agent has zero conversation context. Include:
- Project location and build instructions (reference CLAUDE.md)
- Hard restrictions (no network, no credentials, no deployment -- as appropriate)
- Exact files to read first, with line numbers
- Step-by-step implementation instructions with code excerpts
- Acceptance criteria
- Verification commands (build, test, backtest if applicable)
- Explicit commit instructions with exact `git add` + `git commit -m` recipes

### 6. Generate PLAN.md and STATE.md

Read `references/plan-format.md` for the exact file format.

- If `<state-dir>` exists and has no COMPLETE.md, confirm with user before deleting (an incomplete run may have salvageable work)
- Create `<state-dir>/` with `project.json`, `PLAN.md`, and `STATE.md`
- PLAN.md frontmatter must include `state_dir: <absolute state-dir path>` so agents and reviewers can find the state

### 7. Present plan and request execution permission

Show the user:
- Phase count and task count
- Phase grouping with parallelism rationale
- Identified merge-conflict risks and mitigations
- Estimated completion time (rough: ~70 min/task for agent + review + fix + merge)
- Any deferred concerns or known risks

Then use `AskUserQuestion` with these options:

- **Begin autonomous execution** -- "The setup is complete and PLAN.md has been written. Starting execution will dispatch multiple Opus agents in parallel across worktrees, each followed by the /review-gauntlet sub-skill (5 reviewers) and auto-fix cycle. This may run continuously for many hours. Approve to begin."
- **Edit PLAN.md first** -- "Leave PLAN.md at <state-dir>/PLAN.md for manual editing. Re-run /parallel-phases after editing to resume."
- **Cancel** -- "Delete <state-dir> entirely and abort."

On **Begin autonomous execution**: fall through to the execution phase decision tree. Do NOT exit.
On **Edit PLAN.md first**: print the path and exit.
On **Cancel**: delete `<state-dir>` and exit.

## Setup key principles

- **Maximize parallelism.** Only serialize when file-level conflicts or semantic dependencies force it. Document why each serialization is necessary.
- **Prompts are the product.** A vague prompt produces a failed agent. Every prompt should have enough detail that a competent engineer could complete the task without asking questions.
- **Gather, don't guess.** Read the actual code to get line numbers and excerpts. Don't assume line numbers from memory or conversation context -- they drift.
- **Commit instructions are mandatory.** Every task prompt must end with explicit `git add` + `git commit -m` commands.

---

## Execution phase

Idempotent driver. Each invocation: read state, decide ONE next action, dispatch or wait, loop. Designed to survive `/clear`.

## Source-of-truth files (read at the TOP of every invocation)

| File | Purpose |
|---|---|
| `<state-dir>/PLAN.md` | Phase definitions, tasks, target branch, test command. Immutable after approval. See `references/plan-template.md`. |
| `<state-dir>/STATE.md` | Dashboard. Updated every invocation. See `references/state-template.md`. |
| `<state-dir>/COMPLETE.md` | Exists ONLY when all phases are merged. Hard-exit marker. |
| `<state-dir>/phase-N/*` | Per-phase artifacts: dispatch logs, agent outputs, reviewer reports, fix summaries, marker files. |

## Hard exit conditions (check FIRST, before the decision tree)

If any of these are true, print the reason and exit immediately. Do NOT dispatch anything.

1. `<state-dir>/COMPLETE.md` exists -> print `PARALLEL-PHASES COMPLETE at <commit hash from COMPLETE.md>` and exit.
2. `<state-dir>/STATE.md` contains an unresolved `BLOCKED:` line -> print that line and exit.
3. Any `<state-dir>/phase-*/task-*-review-gauntlet.md` report has `Status: BLOCKED` -> print task id + reason + exit.
4. Last test command on the current phase's integration branch shows failures not yet documented in STATE.md -> exit.
5. `<cwd>` is not a git working tree (`git rev-parse --git-dir` fails) -> print `parallel-phases requires a git repo` and exit. (Worktree isolation is mandatory.)

When exiting on a stop condition that isn't `COMPLETE`, append `BLOCKED: <one-line reason>` to STATE.md so the next invocation also exits cleanly until a human resolves it.

## Standard 3-line status header (print every invocation)

```
PHASE: <N> of <TOTAL> (<phase-name>) | <planning|in-flight|reviewing|merging|advancing>
IN-FLIGHT: <count> | DONE: <tasks-done>/<tasks-total> | GATE: <PASS|PENDING|FAIL>
NEXT: <one-line description of the action this invocation will take>
```

## Decision tree (run after the status header, every invocation)

Evaluate in order. Act on the first match. After acting, in **run-to-completion mode**, loop back to "read state + decision tree" locally within the same invocation.

1. **No `<state-dir>`** -> run Setup phase (above).
2. **In-flight background agents for current phase**: if background Agent notifications for current-phase task/reviewer/fix agents are still pending, print `IN-FLIGHT: N agents; waiting` and exit. Do not dispatch new work.
3. **Current phase has tasks with status `PENDING`** (not yet dispatched): dispatch them. See "Task dispatch" below.
4. **Current phase has tasks with status `DONE` but not yet reviewed**: dispatch the `/review-gauntlet` sub-skill for those tasks. See "Reviewer gauntlet" below.
5. **Current phase has tasks with status `REVIEWED`**: the review-gauntlet sub-skill already applied fixes; transition to `FIXED` per the "Fix handling" section above.
6. **All current-phase tasks are `FIXED` and no `phase-complete` marker**: write marker, then merge. See `references/worktree-protocol.md`.
7. **`phase-complete` marker exists but `merged` does not**: run the merge + test protocol. On green: write `merged` marker, commit. On red: append `BLOCKED: phase N test gate failed -- <log path>` to STATE.md and exit.
8. **`merged` marker exists and `current_phase < total_phases`**: update STATE.md to `current_phase += 1`, commit `chore(parallel-phases): advance to phase N+1`, loop.
9. **`merged` marker exists and `current_phase == total_phases`**: dispatch the documentation-update agent (see "Documentation update" below), then write `<state-dir>/COMPLETE.md` with the final commit hash and ISO timestamp, print `PARALLEL-PHASES COMPLETE at <hash>`, exit.

## Task dispatch

For every PENDING task in the current phase (respecting the concurrency cap below), dispatch one `Agent` call. **Send all dispatches for the same phase in a single message with multiple tool uses so they run in parallel.**

Required parameters:
- `description`: short task slug
- `subagent_type`: from PLAN.md (default `general-purpose`)
- `model`: from PLAN.md (default `opus`)
- `isolation`: `"worktree"` (always, for parallel code-modifying tasks)
- `run_in_background`: `true`
- `prompt`: task prompt from PLAN.md (self-contained, the subagent has no conversation context)

After dispatching:
- Write `<state-dir>/phase-N/dispatch.md` listing the task id -> worktree path + branch name (`phase-N/task-NN-<slug>`) returned by each Agent call when `isolation="worktree"` is used.
- Update STATE.md: set each dispatched task's status to `IN-FLIGHT`.

## Reviewer gauntlet (sub-skill, per task)

When a task completes (status `DONE`), dispatch a single `general-purpose` agent per task that invokes the `/review-gauntlet` skill as a sub-skill. The review-gauntlet skill internally launches 5 parallel reviewer agents (structural-completeness, bug-finder, silent-failure-hunter, c-safety-reviewer, compatibility-reviewer), synthesizes their findings, and fixes Critical/Should-Fix items in place.

Dispatch one agent per DONE task. **All go in a single message for parallelism**:

```
Agent(
  description: "review-gauntlet for task-NN",
  subagent_type: "general-purpose",
  model: "opus",
  run_in_background: true,
  prompt: |
    You are running the review-gauntlet sub-skill on behalf of the
    parallel-phases orchestrator.

    Working directory: <task worktree path>
    Branch: phase-N/task-NN-<slug>
    Target branch: <target_branch>

    The diff to review is: git diff <target_branch>...phase-N/task-NN-<slug>

    First, check out the task branch in the worktree. Then invoke the
    /review-gauntlet skill, passing the diff range above as its target.

    The review-gauntlet will:
    1. Launch 5 reviewer agents in parallel (structural-completeness,
       bug-finder, silent-failure-hunter, c-safety-reviewer,
       compatibility-reviewer).
    2. Synthesize findings into Critical / Should-Fix / Advisory tiers.
    3. Fix all Critical and Should-Fix items in place.
    4. Re-verify the build.

    After the skill completes, write the synthesized report to:
      <state-dir>/phase-N/task-NN-review-gauntlet.md

    Include the full tiered findings and what was fixed. If the skill
    committed fixes, record the fix commit hash in the report.
)
```

Update STATE.md: set task status to `REVIEWING` on dispatch. When the review-gauntlet report exists, set to `REVIEWED`.

## Fix handling (integrated into review-gauntlet)

The `/review-gauntlet` sub-skill already fixes Critical and Should-Fix items as its Step 3, committing directly on the task branch. There is no separate fix agent dispatch.

When the review-gauntlet agent completes and `<state-dir>/phase-N/task-NN-review-gauntlet.md` exists:
- If the report contains a fix commit hash: task status -> `FIXED`.
- If the report shows no Critical or Should-Fix findings (all Advisory or clean): task status -> `FIXED` (no fix needed).
- If the report shows `Status: BLOCKED` (e.g., unfixable issue): append `BLOCKED: review-gauntlet blocked on task NN -- <reason>` to STATE.md and exit.

There is no intermediate `FIXING` status. The transition is `REVIEWING` -> `FIXED` (or `BLOCKED`).

## Documentation update (after final phase merges)

After the last phase merges successfully (decision tree step 9, before writing COMPLETE.md), dispatch a single `doc-implementer` agent to sync documentation with the code changes:

```
Agent(
  description: "update docs after parallel-phases",
  subagent_type: "doc-implementer",
  model: "opus",
  run_in_background: true,
  prompt: |
    The parallel-phases orchestrator just completed all phases of work
    on the project at <cwd>. Read CLAUDE.md and the project's docs/
    directory to understand the documentation structure.

    Review all commits since <starting commit hash> (the target_branch
    HEAD when the plan was created) by running:
      git log <starting hash>..HEAD --oneline

    For each commit, check whether the changes affect any documented
    behavior, configuration, parameters, CLI flags, architecture, or
    file layout. Update the relevant documentation files to reflect the
    current state of the code. Do NOT create new documentation files
    unless the changes introduce entirely new subsystems.

    Focus on: CLAUDE.md project sections, README if present, docs/ files
    that reference modified modules, and any inline doc comments that
    are now stale.

    Commit documentation updates as:
      git commit -m "docs: update documentation after parallel-phases run"
)
```

Wait for the doc agent to complete before writing COMPLETE.md.

## Concurrency caps

Enforce BEFORE every dispatch:

- **Task dispatch**: max 8 parallel Agent calls per phase. If a phase has >8 tasks, split into waves 1A/1B/... per `references/plan-template.md`.
- **Review-gauntlet**: one agent per task (the sub-skill internally fans out to 5 reviewers and handles fixes). Dispatch all review-gauntlet agents for the phase in one message.
- **Global**: if combined in-flight agents (task + review-gauntlet) would exceed 16 on this run, split across invocations.

## Model selection

- Default model: `"opus"` per the user's preference.
- PLAN.md may override per-task to `"sonnet"` for mechanical work (simple renames, delete-dead-code, etc.).
- Never `"haiku"` for orchestrated work.
- Always pass `model=` explicitly to every `Agent` call.

## Phase merge protocol (summary; see `references/worktree-protocol.md` for steps)

After all tasks in a phase are `FIXED`:

1. Create / reset `phase-N/integration` branch from `target_branch` (from PLAN.md).
2. For each task in phase, `git merge --no-ff phase-N/task-NN-<slug>` into `phase-N/integration`.
3. On merge conflict: abort the merge, mark that task `RETRY-NEEDED` in STATE.md, write `<state-dir>/phase-N/task-NN-merge-conflict.md` with conflict summary, append `BLOCKED: phase N merge conflict on task NN` to STATE.md, exit.
4. Run test command from PLAN.md on `phase-N/integration`. If none configured and no tests auto-detected, skip with a `GATE: SKIPPED (no test command)` note.
5. On tests green: fast-forward `target_branch` to `phase-N/integration`. On tests red: `BLOCKED: phase N tests red -- <log path>`.
6. Write `<state-dir>/phase-N/merged` marker. Commit `chore(parallel-phases): phase N merged`. Run `git worktree prune`.

## Commit policy

Follows global CLAUDE.md:
- Default git author only. **Never add Claude as a commit author or co-author.**
- Never `--amend`; always new commits.
- Never `--no-verify`.
- Never force-push.
- Commit messages:
  - Setup: `chore(parallel-phases): initialize plan`
  - Phase merge: `chore(parallel-phases): phase N merged`
  - Phase advance: `chore(parallel-phases): advance to phase N+1`
  - Review-gauntlet fixes: committed by the sub-skill on the task branch (message format per `/review-gauntlet`)
  - Final: `chore(parallel-phases): complete` (optional -- COMPLETE.md alone is the signal)

## Run modes

- **Interactive / run-to-completion**: default. After each dispatch or state change, loop locally (re-read state, re-run decision tree). Exit only when reaching in-flight-wait, a hard exit, or completion.
- **/loop mode**: when wrapped with `/loop INTERVAL /parallel-phases`, always exit after one decision-tree action. Each tick is a fresh chance. Rely on `/loop`'s idempotency -- the file-backed state and hard-exit checks prevent duplicate dispatches.

No mode flag is needed. The skill behaves the same either way; the only difference is whether the orchestrator keeps looping within one turn.

## Failure modes and escape hatches

- **Task agent crashed / produced nothing useful**: mark status `FAILED` in STATE.md. Reviewers still run against the diff (which may be empty). If a task produced no commits, the fix agent reports "nothing to fix." The phase still advances provided reviews don't `BLOCK`. Re-dispatch by manually setting status back to `PENDING`.
- **Review-gauntlet agent timed out / failed**: mark task `RETRY-NEEDED` in STATE.md. Next invocation re-dispatches the review-gauntlet for that task.
- **Merge conflict**: abort, `BLOCKED: merge conflict`. User resolves manually (edit in the worktree, commit, re-run skill).
- **Test gate red**: `BLOCKED: tests red`. User triages.
- **Manual reset**: delete `<state-dir>` entirely, `git worktree prune`, remove `phase-*` branches.
- **Resume-from-clear**: just re-run `/parallel-phases`. The skill re-computes the state dir from repo root and picks up from STATE.md.

## Operational notes

- Background `Agent` calls notify the main session on completion -- do not poll with sleep.
- Use `Read` + `Glob` on `<state-dir>/**/*` to inventory state.
- Review-gauntlet reports (`task-NN-review-gauntlet.md`) live under the phase directory alongside task outputs.
- COMPLETE.md's commit-hash field points to the head commit when the final phase merged.
- State lives outside the repo at `~/.claude/parallel-phases/`. No .gitignore entry needed.
- This skill has no `scripts/` or `assets/`. All orchestration is pure `Agent` tool dispatch. References hold the long-form prompt templates and protocols.

## Reference files

Load as needed (all live alongside this SKILL.md in the `references/` directory):

- `plan-template.md` -- structure of PLAN.md (phases, tasks, fields, example).
- `plan-format.md` -- exact PLAN.md/STATE.md file format spec.
- `state-template.md` -- structure of STATE.md (dashboard, per-task rows, status values).
- (Review and fix are handled by the `/review-gauntlet` sub-skill -- no local reference files needed.)
- `worktree-protocol.md` -- phase merge steps, conflict handling, test gate, rollback.
- `dependency-analysis.md` -- heuristics for grouping tasks into parallel phases.
- `conflict-analysis.md` -- merge-conflict risk protocol and mitigation strategies.
- `prompt-template.md` -- self-contained task prompt template and anti-patterns.
