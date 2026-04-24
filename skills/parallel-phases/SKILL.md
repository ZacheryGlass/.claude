---
name: parallel-phases
description: Idempotent orchestrator that executes a list of tasks in parallel phases with a per-task 3-reviewer gauntlet and auto-fix commits. First invocation reads the current conversation, drafts a phased parallel PLAN.md grouping tasks by dependency, asks approval, then dispatches Opus agents in git worktrees. Each completed task gets bug-finder + structural-completeness-reviewer + architecture-reviewer run in parallel, with findings auto-addressed as a follow-up commit before the phase merges. Advances phase-by-phase until all work is complete. Resilient to /clear -- all state lives in the project's .parallel-phases/ directory on disk. Triggers on /parallel-phases, "parallelize these tasks", "run these in parallel phases", "plan parallel phases", or when the user asks to execute multiple tasks concurrently with review gates. Also compatible with /loop wrapping for unattended progression.
---

# Parallel Phases Orchestrator

Idempotent driver that runs a user-approved list of tasks in parallel phases. Each invocation: read state, decide ONE next action, dispatch or wait, optionally loop. Designed to survive `/clear` and to be safely wrapped by `/loop`.

## Scope

- **Target project**: current working directory (`<cwd>`). All paths below are relative to it unless absolute.
- **State directory**: `<cwd>/.parallel-phases/`. Created on first planning run.
- **Read `<cwd>/CLAUDE.md` once at session start** if not already in context -- it holds project-specific conventions.

## Source-of-truth files (read at the TOP of every invocation)

| File | Purpose |
|---|---|
| `.parallel-phases/PLAN.md` | Phase definitions, tasks, target branch, test command. Immutable after user approval. See `references/plan-template.md`. |
| `.parallel-phases/STATE.md` | Dashboard. Updated every invocation. See `references/state-template.md`. |
| `.parallel-phases/COMPLETE.md` | Exists ONLY when all phases are merged. Hard-exit marker. |
| `.parallel-phases/phase-N/*` | Per-phase artifacts: dispatch logs, agent outputs, reviewer reports, fix summaries, marker files. |

## Hard exit conditions (check FIRST, before the decision tree)

If any of these are true, print the reason and exit immediately. Do NOT dispatch anything.

1. `.parallel-phases/COMPLETE.md` exists -> print `PARALLEL-PHASES COMPLETE at <commit hash from COMPLETE.md>` and exit.
2. `.parallel-phases/STATE.md` contains an unresolved `BLOCKED:` line -> print that line and exit.
3. Any `.parallel-phases/phase-*/task-*-review-*.md` report has `Status: BLOCKED` -> print task id + reviewer + exit.
4. Last test command on the current phase's integration branch shows failures not yet documented in STATE.md -> exit.
5. `<cwd>` is not a git working tree (`git rev-parse --git-dir` fails) -> print `parallel-phases requires a git repo` and exit. (Worktree isolation is mandatory.)

When exiting on a stop condition that isn't `COMPLETE`, append `BLOCKED: <one-line reason>` to STATE.md so the next invocation also exits cleanly until a human resolves it.

## Standard 3-line status header (print every invocation)

```
PHASE: <N> of <TOTAL> (<phase-name>) | <planning|in-flight|reviewing|fixing|merging|advancing>
IN-FLIGHT: <count> | DONE: <tasks-done>/<tasks-total> | GATE: <PASS|PENDING|FAIL>
NEXT: <one-line description of the action this invocation will take>
```

## First-run planning (when `.parallel-phases/` does NOT exist)

1. Verify `<cwd>` is a git repo (hard exit #5 above).
2. Capture starting branch: `git rev-parse --abbrev-ref HEAD` -- this is the default `target_branch` in PLAN.md.
3. Read the current conversation context and extract candidate tasks. A "task" is a discrete unit of work the user has discussed (bug fix, feature, refactor, cleanup, investigation, paper smoke, backtest run, etc.).
4. Analyze dependencies using `references/dependency-analysis.md`. Group tasks into **phases** where all tasks within a phase can run concurrently.
5. Draft PLAN.md at `.parallel-phases/PLAN.md` following `references/plan-template.md`. Each task gets an id, slug, model (default `opus`), isolation (`worktree` by default), agent type (default `general-purpose`), scope notes, and a compact prompt.
6. Present a plan summary to the user via `AskUserQuestion` with 3 options: **Approve and execute**, **Edit PLAN.md first**, **Cancel**.
7. **On approve**:
   - Write `.parallel-phases/STATE.md` from `references/state-template.md` with `current_phase: 1` and all tasks `PENDING`.
   - Append `.parallel-phases/` to `<cwd>/.gitignore` (create if needed) UNLESS PLAN.md sets `gitignore_state: false`.
   - Commit: `git add .gitignore && git commit -m "chore(parallel-phases): initialize plan"` (only the gitignore entry, nothing in `.parallel-phases/` is tracked).
   - Fall through to the decision tree. Do NOT exit.
8. **On edit**: Leave PLAN.md in place. Print `PLAN.md drafted at .parallel-phases/PLAN.md -- edit and re-run /parallel-phases to approve.` Exit.
9. **On cancel**: Delete `.parallel-phases/` entirely. Exit.

## Decision tree (run after the status header, every invocation)

Evaluate in order. Act on the first match. After acting, in **run-to-completion mode**, loop back to "read state + decision tree" locally within the same invocation. In **/loop mode** (when the user wraps with `/loop`), always exit after one action.

1. **No `.parallel-phases/`** -> run First-run planning (above).
2. **In-flight background agents for current phase**: if background Agent notifications for current-phase task/reviewer/fix agents are still pending, print `IN-FLIGHT: N agents; waiting` and exit. Do not dispatch new work.
3. **Current phase has tasks with status `PENDING`** (not yet dispatched): dispatch them. See "Task dispatch" below.
4. **Current phase has tasks with status `DONE` but missing reviewer reports**: dispatch the 3-reviewer gauntlet for those tasks. See "Reviewer gauntlet" below.
5. **Current phase has tasks with status `REVIEWED` but no fix commit**: dispatch a fix agent per such task. See "Fix agent" below.
6. **All current-phase tasks are `FIXED` and no `phase-complete` marker**: write marker, then merge. See `references/worktree-protocol.md`.
7. **`phase-complete` marker exists but `merged` does not**: run the merge + test protocol. On green: write `merged` marker, commit. On red: append `BLOCKED: phase N test gate failed -- <log path>` to STATE.md and exit.
8. **`merged` marker exists and `current_phase < total_phases`**: update STATE.md to `current_phase += 1`, commit `chore(parallel-phases): advance to phase N+1`, loop.
9. **`merged` marker exists and `current_phase == total_phases`**: write `.parallel-phases/COMPLETE.md` with the final commit hash and ISO timestamp, print `PARALLEL-PHASES COMPLETE at <hash>`, exit.

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
- Write `.parallel-phases/phase-N/dispatch.md` listing the task id -> worktree path + branch name (`phase-N/task-NN-<slug>`) returned by each Agent call when `isolation="worktree"` is used.
- Update STATE.md: set each dispatched task's status to `IN-FLIGHT`.
- Commit: `git add .parallel-phases/phase-N/dispatch.md && git commit -m "chore(parallel-phases): dispatch phase N tasks"` (if state dir is tracked; otherwise skip).

## Reviewer gauntlet (3 parallel per task)

When a task completes (status `DONE`), dispatch exactly 3 reviewer agents in parallel for it. **All 3 go in a single message**:

- `Agent(subagent_type: "bug-finder", model: "opus", run_in_background: true, prompt: ...)` — output to `phase-N/task-NN-review-bugs.md`
- `Agent(subagent_type: "structural-completeness-reviewer", model: "opus", run_in_background: true, prompt: ...)` — output to `phase-N/task-NN-review-structural.md`
- `Agent(subagent_type: "architecture-reviewer", model: "opus", run_in_background: true, prompt: ...)` — output to `phase-N/task-NN-review-architecture.md`

See `references/review-gauntlet.md` for the exact prompt template each reviewer receives. Reviewers analyze the diff on the task's branch (`git diff <target_branch>...phase-N/task-NN-<slug>`), NOT the main working copy.

Update STATE.md: set task status to `REVIEWING`. When all 3 reports exist, set to `REVIEWED`.

## Fix agent (one per task)

When a task reaches status `REVIEWED`, dispatch a fix agent that:
- Runs **inside the same worktree** as the task (do NOT create a new worktree; pass the existing worktree path in the prompt).
- Reads all 3 reviewer reports.
- Classifies each finding: `accept` / `defer` / `reject` (false positive).
- Implements all `accept` findings.
- Commits as a follow-up on the same branch: `fix(review): address <N> findings on <task-slug>` (NEVER `--amend`).
- Writes `phase-N/task-NN-fix.md` with the classification table and fix commit hash.

Parameters:
- `subagent_type`: `"general-purpose"`
- `model`: `"opus"`
- `isolation`: omit (runs in-place; fix agents inside existing worktree, not a new one)
- `run_in_background`: `true`

See `references/fix-agent-prompt.md` for the full prompt template.

Update STATE.md: status -> `FIXING` on dispatch, `FIXED` when fix commit lands (or the fix agent reports no actionable findings and writes an empty-fix summary).

## Concurrency caps

Enforce BEFORE every dispatch:

- **Task dispatch**: max 8 parallel Agent calls per phase. If a phase has >8 tasks, split into waves 1A/1B/... per `references/plan-template.md`.
- **Reviewer gauntlet**: exactly 3 agents per task (bug-finder, structural-completeness-reviewer, architecture-reviewer). Dispatch all three in one message for parallelism.
- **Fix agents**: one per task, all fix agents for a phase go out in one message.
- **Global**: if combined in-flight agents across all three kinds would exceed 16 on this run, split across invocations.

## Model selection

- Default model: `"opus"` per the user's preference.
- PLAN.md may override per-task to `"sonnet"` for mechanical work (simple renames, delete-dead-code, etc.).
- Never `"haiku"` for orchestrated work.
- Always pass `model=` explicitly to every `Agent` call.

## Phase merge protocol (summary; see `references/worktree-protocol.md` for steps)

After all tasks in a phase are `FIXED`:

1. Create / reset `phase-N/integration` branch from `target_branch` (from PLAN.md).
2. For each task in phase, `git merge --no-ff phase-N/task-NN-<slug>` into `phase-N/integration`.
3. On merge conflict: abort the merge, mark that task `RETRY-NEEDED` in STATE.md, write `phase-N/task-NN-merge-conflict.md` with conflict summary, append `BLOCKED: phase N merge conflict on task NN` to STATE.md, exit.
4. Run test command from PLAN.md on `phase-N/integration`. If none configured and no tests auto-detected, skip with a `GATE: SKIPPED (no test command)` note.
5. On tests green: fast-forward `target_branch` to `phase-N/integration`. On tests red: `BLOCKED: phase N tests red -- <log path>`.
6. Write `phase-N/merged` marker. Commit `chore(parallel-phases): phase N merged`. Run `git worktree prune`.

## Commit policy

Follows global CLAUDE.md:
- Default git author only. **Never add Claude as a commit author or co-author.**
- Never `--amend`; always new commits.
- Never `--no-verify`.
- Never force-push.
- Commit messages:
  - Setup: `chore(parallel-phases): initialize plan`
  - Dispatch (optional): `chore(parallel-phases): dispatch phase N tasks`
  - Phase merge: `chore(parallel-phases): phase N merged`
  - Phase advance: `chore(parallel-phases): advance to phase N+1`
  - Fix agent: `fix(review): address <N> findings on <task-slug>`
  - Final: `chore(parallel-phases): complete` (optional -- COMPLETE.md alone is the signal)

## Run modes

- **Interactive / run-to-completion**: default. After each dispatch or state change, loop locally (re-read state, re-run decision tree). Exit only when reaching in-flight-wait, a hard exit, or completion.
- **/loop mode**: when wrapped with `/loop INTERVAL /parallel-phases`, always exit after one decision-tree action. Each tick is a fresh chance. Rely on `/loop`'s idempotency — the file-backed state and hard-exit checks prevent duplicate dispatches.

No mode flag is needed. The skill behaves the same either way; the only difference is whether the orchestrator keeps looping within one turn.

## Failure modes and escape hatches

- **Task agent crashed / produced nothing useful**: mark status `FAILED` in STATE.md. Reviewers still run against the diff (which may be empty). If a task produced no commits, the fix agent reports "nothing to fix." The phase still advances provided reviews don't `BLOCK`. Re-dispatch by manually setting status back to `PENDING`.
- **Reviewer agent timed out / failed**: mark that reviewer `RETRY-NEEDED` in the task's row. Next invocation re-dispatches only the missing reviewer(s).
- **Fix agent failed**: status `FIX-FAILED`. Append `BLOCKED: fix agent failed on task <id>` to STATE.md.
- **Merge conflict**: abort, `BLOCKED: merge conflict`. User resolves manually (edit in the worktree, commit, re-run skill).
- **Test gate red**: `BLOCKED: tests red`. User triages.
- **Manual reset**: delete `.parallel-phases/` entirely, `git worktree prune`, remove `phase-*` branches.
- **Resume-from-clear**: just re-run `/parallel-phases`. The skill re-reads STATE.md and picks up from the correct decision-tree branch.

## Operational notes

- Background `Agent` calls notify the main session on completion -- do not poll with sleep.
- Use `Read` + `Glob` on `.parallel-phases/**/*` to inventory state. Don't shell out to `ls` or `find`.
- Reviewer reports live alongside task outputs under the phase directory so the diff range is obvious.
- If `.parallel-phases/` is gitignored (default), the state itself isn't tracked, but `COMPLETE.md`'s commit-hash field points to the head commit when the final phase merged.
- This skill has no `scripts/` or `assets/`. All orchestration is pure `Agent` tool dispatch. References hold the long-form prompt templates and protocols.

## Reference files

Load as needed (all live at `C:\Users\zache\.claude\skills\parallel-phases\references\`):

- `plan-template.md` — structure of PLAN.md (phases, tasks, fields, example).
- `state-template.md` — structure of STATE.md (dashboard, per-task rows, status values).
- `review-gauntlet.md` — exact reviewer dispatch snippet and prompt templates.
- `fix-agent-prompt.md` — fix-agent prompt template (classify → fix → commit → report).
- `worktree-protocol.md` — phase merge steps, conflict handling, test gate, rollback.
- `dependency-analysis.md` — heuristics for grouping tasks into parallel phases.
