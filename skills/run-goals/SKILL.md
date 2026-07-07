---
name: run-goals
description: Execute multiple goal prompts in parallel by launching non-interactive Claude Code sessions (claude -p "/goal ...") in isolated git worktrees, then collect and report results. Use after /generate-goal has produced goal prompts, or when the user says "run these goals", "run the goals in parallel", or "/run-goals".
argument-hint: [goal ...]
---

# run-goals

Fan out goal prompts to parallel `claude -p "/goal ..."` sessions using the native /goal loop. Each session runs in its own worktree (`worktree-goal-<slug>` branch) so parallel edits never collide.

**Zero-persistence contract:** goal prompts pass as `-g` args (no files). The run dir is a mktemp dir deleted on exit — the script's stdout is the only artifact. Zero-work worktrees are auto-pruned at end of run; work-bearing branches survive only until reviewed, then `cleanup_goals.sh` removes them.

## Workflow

1. **Gather goal prompts.** Take them from the conversation (e.g. /generate-goal output). Pass each as a `-g "..."` argument. Only if a prompt is too awkward to quote: write it to the session scratchpad, pass the path, delete after launch. Never write goal files anywhere persistent.
2. **Do NOT add turn caps.** Per generate-goal's rules, the COMPLETION clause is the only stop signal — never append "stop after N turns". For unattended runs, bound wall-clock instead with `-t <seconds>`.
3. **Preflight.** Confirm the target repo is a trusted git repo (user has run `claude` there interactively — /goal's evaluator is hook-based and needs trust). Warn if goals target overlapping files.
4. **Launch in background** via Bash with `run_in_background: true`:
   ```
   ${CLAUDE_SKILL_DIR}/scripts/run_goals.sh -r <repo> -g "<goal 1>" -g "<goal 2>"
   ```
   Useful flags: `-c N` (concurrency, default 3), `-m <model>`, `-a '<allowedTools rules>'` (for commands beyond edits, e.g. `'Bash(npm test *),Bash(git commit *)'`), `-t <seconds>` (wall-clock kill), `--keep` (retain run dir for debugging), `--dry-run`.
5. **Monitor.** Check task output periodically; each goal logs launch/done lines.
6. **Report from stdout.** The summary contains everything (there are no result files): per goal — status, result text, `session_id` (resume with `claude --resume <id>` from the repo), and branch `worktree-goal-<slug>`.
7. **Cleanup.** End-of-run auto-prune already removed zero-work worktrees. For branches that hold work: after the user reviews/merges, run
   ```
   ${CLAUDE_SKILL_DIR}/scripts/cleanup_goals.sh -r <repo>            # dry-run plan
   ${CLAUDE_SKILL_DIR}/scripts/cleanup_goals.sh -r <repo> --apply    # execute
   ```
   `--force` discards dirty worktrees and unmerged branches. For repo-wide cleanup or subsumed-branch cases, use the /git-worktree-prune skill (full cross-ref reachability safety).

## Caveats

- Children run with `--permission-mode acceptEdits` by default; commands beyond file edits/fs need allow rules (project settings or `-a`).
- N parallel sessions consume ~N x plan usage.
- If a goal fails or stalls, resume its session and steer it manually rather than relaunching.
- Platform exception to zero-persistence: child-session transcripts live under `~/.claude/projects/` with Claude Code's standard retention (`cleanupPeriodDays`, default 30 days). `claude project purge` removes them on demand.
