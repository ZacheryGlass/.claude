# Personal Claude Code Configuration

This repository contains my personal configuration settings for [Claude Code](https://claude.ai/code).

## What is Claude Code?

Claude Code is an interactive command-line interface that provides AI assistance for software development tasks.

## Repository Contents

- **`settings.json`** - Core configuration file containing:
  - Permission settings for various tools and commands
  - Custom hooks for enhanced functionality
  - etc.

- **`statusline.exe` / `statusline.go`** - Custom status line binary (see [Statusline](#statusline) below)

- **`CLAUDE.md`** - Minimal agent instructions

- **`hooks/`** - Pre/Post-tool-use scripts:
  - `emoji_remover.py` - Post-edit hook to ensure no emojis are used
  - `github_issue_guard.py` - Guard for GitHub issue interactions
  - `protect_claude_md.py` - Protection for critical configuration files

- **`skills/`** - Reusable agent skills:
  - `arewedone-g` - Completion verification
  - `gemini-agent` - Gemini-specific logic
  - `root-cause-tracing` - Bug investigation
  - `skill-creator` - Framework for building new skills

- **`commands/`** - Custom slash commands:
  - `/arch-review`, `/arewedone`, `/bugs`, `/commit`, `/docs`, `/perf-check`, `/ui-review`

- **`sync-docs.py`** - Documentation synchronization utility

## Statusline

`statusline.exe` is a small Go binary that runs every second and renders a status bar. All data is cached to disk so git and file reads only happen when something actually changes.

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
