# Personal Claude Code Configuration

This repository contains my personal configuration settings for [Claude Code](https://claude.ai/code).

## What is Claude Code?

Claude Code is an interactive command-line interface that provides AI assistance for software development tasks.

## Repository Contents

- **`settings.json`** - Core configuration file containing:
  - Permission settings for various tools and commands
  - Custom hooks for enhanced functionality
  - etc.

- **`statusline.go`** - Custom status line (see [Statusline](#statusline) below). `build_statusline.sh` and `build_statusline.ps1` build it for Windows and macOS, and `statusline.cmd` runs the right binary on each.

- **`CLAUDE.md`** - Minimal agent instructions

- **`hooks/`** - Pre/Post-tool-use scripts:
  - `emoji_remover.py` - Post-edit hook that tells Claude to remove any emojis an edit adds
  - `emoji_remover.cmd` - Cross-platform wrapper that `settings.json` calls to run `emoji_remover.py` on Windows or macOS
  - `github_issue_guard.py` - Guard for GitHub issue interactions (not enabled in `settings.json`)
  - `protect_claude_md.py` - Protection for critical configuration files (not enabled in `settings.json`)

- **`skills/`** - Reusable agent skills:
  - `gemini-agent` - Delegates arbitrary tasks to Gemini CLI for a second opinion or token savings.
  - `generate-goal` - Turns the current conversation into one self-contained `/goal` prompt, so a long discussion doesn't need summarizing by hand.
  - `git-worktree-prune` - Deletes stale git worktrees and local branches, keeping any that hold work found nowhere else.
  - `root-cause-tracing` - Traces a bug backward through the call stack, adding instrumentation as needed, to find the original trigger.
  - `run-goals` - Runs several `/goal` prompts in parallel as non-interactive Claude Code sessions, each in its own git worktree, and reports the results.
  - `skill-creator` - Scaffolds and refines new skills following the official skill authoring guidelines.

- **`commands/`** - Custom slash commands:
  - `/arch-review` - Review architecture of specified paths or staged/unstaged git changes.
  - `/arewedone` - Run a structural completeness review on recent changes.
  - `/bugs` - Invoke the `bug-finder` agent to hunt for logical errors and runtime issues.
  - `/commit` - Draft a conventional commit from the current staged/unstaged diff.
  - `/docs` - Run the documentation review and implementation workflow.
  - `/perf-check` - Invoke the `performance-profiler` agent to analyze code for performance issues.
  - `/review-gauntlet` - Run all the standard review agents in parallel on current changes, then address their findings.
  - `/ui-review` - Invoke the `ui-ux-consultant` agent for a UI/UX and accessibility review.

- **`agents/`** - Specialized sub-agents invoked via the Agent tool:
  - `architecture-reviewer` - Senior architect review of structural integrity, scalability, and long-term maintainability.
  - `bug-finder` - Hunts for logical errors, race conditions, and unhandled edge cases in a specific function or module.
  - `c-safety-reviewer` - Reviews changed C code for leaked memory, file descriptors and sockets, and for security vulnerabilities.
  - `compatibility-reviewer` - After a change to an interface, file format or config, finds the scripts, docs and other consumers that still expect the old one.
  - `doc-implementer` - Implements documentation changes based on review findings.
  - `doc-reviewer` - Analyzes documentation state and reports gaps, outdated content, and quality issues without making changes.
  - `git-cherry-pick-orchestrator` - Orchestrates cherry-pick operations across repositories with submodules via a plan-then-execute workflow.
  - `github-issue-creator` - Creates GitHub issues to track bugs, follow-ups, and future work identified mid-conversation.
  - `performance-profiler` - Diagnoses and fixes performance issues in desktop apps (slow UI, high memory, long startup).
  - `structural-completeness-reviewer` - Verifies that recent changes are fully integrated, old code is removed, and no technical debt was introduced.
  - `test-runner` - Runs the project's test suite and reports results.
  - `ui-ux-consultant` - Reviews desktop UI/UX and accessibility against platform standards.

- **`sync-docs.py`** - Documentation synchronization utility

## Statusline

`statusline.go` builds to a small binary that runs every second and renders a status bar. All data is cached to disk so git and file reads only happen when something actually changes.

### Performance

Measured over 20 runs each on Windows 11 (see `tests/bench.ps1`):

| Scenario                    | Median | Notes                       |
| --------------------------- | ------ | --------------------------- |
| Fully warm (all caches hit) | 16ms   | typical tick                |
| Git cache miss (exec git)   | 62ms   | once per 10 min per cwd     |
| No git repo                 | 13ms   |                             |
| Pure binary startup         | 11ms   | floor: process + JSON parse |

Full example:
```
📁 myproject | 🤖 Sonnet 4.6 (Medium) | ⚡ 12.3k/4.1k | ⏳ 47m 12s | 🌿 main*↑2 | 87% Remaining
```

### Segments

| Segment | Example | Description |
| --- | --- | --- |
| Project | `📁 myproject` | Leaf name of `workspace.project_dir` (falls back to `current_dir`). |
| Model + Effort | `🤖 Sonnet 4.6 (Medium)` | Display name of the active model, plus effort level in parentheses (hidden for Haiku). Effort is read from `settings.json` and cached by file mtime. |
| Prompt Cache | `⚡ 12.3k/4.1k` | Cumulative cache read / write tokens for the session (read 12,300, wrote 4,100). Hidden when both are zero; small numbers shown without suffix. |
| Cache Timer | `⏳ 47m 12s` | Counts down 60 minutes from the last API call. Shows `Expired` once the window passes and `No Cache` before the first call. Resets per model when you switch models. `/clear` or `/compact` resets all model timers. |
| Git | `🌿 main*↑2` | Branch name with dirty/sync indicators: `*` for uncommitted changes, `↑N`/`↓N` for ahead/behind remote, `HEAD@<sha>` when detached. Only shown when `current_dir/.git` exists. Cached for 10 minutes per directory. |
| Context remaining | `87% Remaining` | Percentage of context window still available, color-coded: green above 50%, yellow 20–50%, red below 20%. |

## Documentation

For more information about Claude Code, see the official documentation:

- [Overview](https://docs.anthropic.com/en/docs/claude-code/overview)
- [Settings](https://docs.anthropic.com/en/docs/claude-code/settings)
- [Agent Skills](https://code.claude.com/docs/en/skills)
- [Slash Commands](https://docs.anthropic.com/en/docs/claude-code/slash-commands)
- [Sub-agents](https://docs.anthropic.com/en/docs/claude-code/sub-agents)
- [Hooks Guide](https://docs.anthropic.com/en/docs/claude-code/hooks-guide)

## Usage

To use this configuration:

1. Clone this repository to your local machine
2. Copy the configuration files to your Claude Code settings directory (`~/.claude/`)
3. Adjust permissions and settings as needed for your development environment
4. Restart Claude Code to apply the new configuration
