# Personal Claude Code Configuration

This repository contains my personal configuration settings for [Claude Code](https://claude.ai/code), Anthropic's official CLI tool for Claude AI assistance.

## What is Claude Code?

Claude Code is an interactive command-line interface that provides AI assistance for software development tasks. It helps with code reviews, debugging, feature implementation, and general programming questions while integrating seamlessly with your development workflow.

## Repository Contents

- **`settings.json`** - Core configuration file containing:
  - Permission settings for various tools and commands
  - Model preferences and environment variables
  - Custom hooks for enhanced functionality
  - Security settings and workflow preferences

- **`statusline.sh`** - Custom status line script that displays:
  - Current project folder
  - Active Claude model
  - Git branch and status information
  - Uncommitted changes and remote sync status

- **`CLAUDE.md`** - Project-specific instructions and guidelines for Claude Code behavior in this repository

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
- Commit message cleaning and validation
- GitHub issue integration guards
- Protection for critical configuration files

### Environment Customization
- Disabled non-essential telemetry for privacy
- Optimized for development workflow efficiency
- Custom status line integration

## Documentation

For more information about Claude Code, see the official documentation:

- [Overview](https://docs.anthropic.com/en/docs/claude-code/overview)
- [Settings](https://docs.anthropic.com/en/docs/claude-code/settings)
- [Slash Commands](https://docs.anthropic.com/en/docs/claude-code/slash-commands)
- [Sub-agents](https://docs.anthropic.com/en/docs/claude-code/sub-agents)
- [Hooks Guide](https://docs.anthropic.com/en/docs/claude-code/hooks-guide)

## Usage

To use this configuration:

1. Clone this repository to your local machine
2. Copy the configuration files to your Claude Code settings directory
3. Adjust permissions and settings as needed for your development environment
4. Restart Claude Code to apply the new configuration

## License

This configuration is provided as-is for personal use and reference.