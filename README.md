# Personal Claude Code Configuration

This repository contains my personal configuration settings for [Claude Code](https://claude.ai/code).

## What is Claude Code?

Claude Code is an interactive command-line interface that provides AI assistance for software development tasks.

## Repository Contents

- **`settings.json`** - Core configuration file containing:
  - Permission settings for various tools and commands
  - Model preferences (default: `sonnet`) and environment variables
  - Custom hooks for enhanced functionality
  - Security settings like `skipDangerousModePermissionPrompt`: `true`

- **`statusline.exe` / `statusline.go`** - Custom status line binary (see [Statusline](#statusline) below). The PowerShell version (`statusline.ps1`) is kept as a reference implementation.

- **`CLAUDE.md`** - Project-specific instructions

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

For comparison, the PowerShell reference implementation runs at ~840ms warm — slow enough that ticks could pile up faster than `powershell.exe` could start, which is what caused the original countdown-freeze symptom.

Full example:
```
📁 myproject | 🤖 Sonnet 4.6 (Medium) | ⚡ 12.3k/4.1k | ⏳ 47m 12s | 🌿 main*↑2 | 87% Remaining
```

### Segments

**Project** — leaf name of `workspace.project_dir` (falls back to `current_dir`):
```
📁 myproject
```

**Model + Effort** — display name of the active model, plus effort level in parentheses (hidden for Haiku, which has no effort setting):
```
🤖 Sonnet 4.6 (Medium)
🤖 Haiku 4.5
```
Effort level is read from `settings.json` and cached by file mtime, so the label updates immediately when you change it without re-parsing JSON on every tick.

**Prompt Cache** — cumulative cache read / cache write tokens for the session (hidden when both are zero):
```
⚡ 12.3k/4.1k     ← read 12 300 tokens, wrote 4 100 tokens from cache
⚡ 850/200         ← small numbers shown without suffix
```

**Cache Timer** — counts down 60 minutes from the last API call. Resets per model when you switch models. Counts down to zero then shows `Expired`. Shows `No Cache` before the first API call:
```
⏳ 47m 12s    ← 47 minutes left before prompt cache expires
⏳ Expired    ← cache window has passed
⏳ No Cache   ← no API call yet this session
```
A `/clear` or `/compact` command resets all model timers.

**Git** — branch name with dirty/sync indicators (only shown when `current_dir/.git` exists):
```
🌿 main           ← clean, no remote tracking
🌿 main*          ← uncommitted changes
🌿 main*↑2        ← dirty + 2 commits ahead of remote
🌿 main↓3         ← 3 commits behind remote
🌿 HEAD@a1b2c3d   ← detached HEAD state
```
Git state is cached for 10 minutes per directory.

**Context remaining** — percentage of the context window still available, color-coded:
```
87% Remaining   ← green  (> 50%)
34% Remaining   ← yellow (20–50%)
11% Remaining   ← red    (< 20%)
```

### Caching

Each session gets its own cache file at `~/.claude/.statusline_cache/<session_id>`. Cache files older than 2 days and any orphaned temp files are deleted automatically on each write.

### Rebuilding

The `statusline.exe` Windows binary is checked in so clones work out of the box. To rebuild from `statusline.go` (requires Go):

```
./build_statusline.ps1   # Windows
./build_statusline.sh    # macOS / Linux
```

Regression tests live in `tests/` and run against both implementations:

```
Invoke-Pester -Script @{ Path='tests/statusline.Tests.ps1'; Parameters = @{ Command='go' } }
Invoke-Pester -Script @{ Path='tests/statusline.Tests.ps1'; Parameters = @{ Command='ps' } }
```

## Key Features

### Permission Management
The configuration includes carefully tuned permissions that allow Claude Code to:
- Perform file operations safely
- Execute git commands for version control
- Run development tools and package managers
- Access web resources when needed

### Custom Hooks
Pre-tool-use hooks provide additional safety and functionality:
- GitHub issue integration guards
- Protection for critical configuration files
- Automatic emoji removal post-edit

### Environment Customization
- Disabled non-essential telemetry for privacy
- Optimized for development workflow efficiency
- Custom PowerShell status line integration
- `clangd-lsp` plugin enabled

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
