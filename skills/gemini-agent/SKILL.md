---
name: gemini-agent
description: >
  Delegate tasks to Gemini CLI as an agent. Use when the user wants to offload token-heavy work to
  Gemini, get a second opinion from a different model, or run Gemini with a custom system prompt.
  Triggers include "use Gemini to review X", "ask Gemini to Y", "run Gemini on Z", "delegate to
  Gemini", "have Gemini check X".
---

# Gemini Agent

Delegates tasks to Gemini CLI in headless mode using `gemini_interface.py` from this skill's `scripts/` folder.

**Prerequisite:** Gemini CLI must be installed and on PATH (`gemini --version` should work).

## Basic usage

```bash
python ~/.claude/skills/gemini-agent/scripts/gemini_interface.py \
  --prompt "<task prompt>" \
  --cwd "$(pwd)"
```

## With a system prompt file

Pass any markdown file as a persona/role for Gemini. YAML frontmatter is stripped automatically.

```bash
python ~/.claude/skills/gemini-agent/scripts/gemini_interface.py \
  --prompt "<task prompt>" \
  --system-md /path/to/persona.md \
  --cwd "$(pwd)"
```

## With a context file

If you need Gemini to read a large existing file, attach it via the `--context-file` argument (which uses Gemini's `@file` syntax under the hood):

```bash
python ~/.claude/skills/gemini-agent/scripts/gemini_interface.py \
  --prompt "Review this file for security vulnerabilities." \
  --context-file src/auth/login.py \
  --cwd "$(pwd)"
```

*Note: For short context or summaries (a few sentences), do not create a temp file. Just include the context directly inside your `--prompt` string!*

## Options

| Flag | Default | Description |
|------|---------|-------------|
| `--prompt` | required | Task prompt |
| `--system-md` | none | Markdown file prepended as system instructions |
| `--context-file` | none | File attached via `@path` in the prompt |
| `--cwd` | current dir | Working directory for Gemini CLI |
| `--model` | `gemini-3.1-pro-preview` | Gemini model ID |
| `--verbose` | off | Stream all output; default is final response only |

## Running in background (parallel with other work)

```bash
# Launch as a background task so Claude can continue working in parallel
Bash("python ~/.claude/skills/gemini-agent/scripts/gemini_interface.py --prompt '...' --cwd $(pwd)", run_in_background=true)
```

## Constructing good prompts

Gemini has no conversation context. Include everything it needs:
- Which files or components to examine
- What specifically to look for
- What format to return (e.g., "list issues with file:line references")
