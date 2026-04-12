# Gemini Agent Skill

This skill allows Claude to delegate tasks to the Gemini CLI as an autonomous agent. It is particularly useful for offloading token-heavy work, getting a second opinion from a different model, or running tasks with custom system prompts.

## Overview

The Gemini Agent skill leverages the `gemini-cli` to perform tasks in a headless mode. It uses a bridge script (`gemini_interface.py`) to communicate with the Gemini CLI and return the results to Claude.

## Prerequisites

- **Gemini CLI**: Must be installed and available in your PATH. Verify with `gemini --version`.
- **Python 3.x**: Required to run the bridge script.

## Features

- **Delegation**: Offload complex or large-scale tasks to Gemini.
- **Custom Personas**: Use Markdown files to define custom system instructions for Gemini.
- **Context Injection**: Attach external files or context to the Gemini prompt.
- **Background Execution**: Run Gemini tasks in the background while continuing work in the current session.

## Comparison: Claude vs. Gemini Agent

The following table summarizes what is returned to the main session when delegating a task. By default, the Gemini Agent provides only the final response (unless the `--verbose` flag is used).

```text
┌────────────────────┬───────────────────┬─────────────────────────────┐
│                    │   Claude Agent    │        Gemini Agent         │
├────────────────────┼───────────────────┼─────────────────────────────┤
│ What you receive   │ Final answer only │ Final answer only           │
├────────────────────┼───────────────────┼─────────────────────────────┤
│ Intermediate steps │ Hidden            │ Hidden                      │
├────────────────────┼───────────────────┼─────────────────────────────┤
│ Tool call logs     │ Hidden            │ Hidden                      │
├────────────────────┼───────────────────┼─────────────────────────────┤
│ Format             │ Tool result text  │ Stdout text                 │
└────────────────────┴───────────────────┴─────────────────────────────┘
```

## Usage

### Basic Task Delegation

```bash
python scripts/gemini_interface.py --prompt "Review the architecture of the src/ folder" --cwd "."
```

### Using a Custom System Prompt

You can provide a Markdown file to act as the system instructions for Gemini:

```bash
python scripts/gemini_interface.py --prompt "Audit these logs" --system-md personas/security-expert.md --cwd "."
```

### Attaching Context Files

```bash
python scripts/gemini_interface.py --prompt "Explain this error" --context-file error.log --cwd "."
```

## Command Line Options

| Option | Description |
|--------|-------------|
| `--prompt` | The task or question for Gemini (Required). |
| `--system-md` | Path to a Markdown file to use as system instructions. |
| `--context-file` | Path to a file to be attached as context. |
| `--cwd` | The working directory for the Gemini CLI execution. |
| `--model` | The Gemini model to use (default: `gemini-3.1-pro-preview`). |
| `--verbose` | If set, streams all output; otherwise, only the final response is shown. |

## File Structure

- `SKILL.md`: Skill definition and metadata for Claude.
- `README.md`: This file.
- `scripts/gemini_interface.py`: The bridge script that invokes the Gemini CLI.
