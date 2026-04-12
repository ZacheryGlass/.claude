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

- **`statusline.ps1`** - Custom PowerShell status line script that displays:
  - Current project folder
  - Active Claude model
  - Git branch and status information
  - Uncommitted changes and remote sync status

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
