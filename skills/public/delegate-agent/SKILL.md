---
name: delegate-agent
description: >
  Launch one or more sub-agents (Claude agents or Gemini CLI agents) in parallel for any task.
  Use when the user wants to delegate work to specialized agents, run multiple agents simultaneously
  for comparison, or offload token-heavy tasks to Gemini. Triggers include "launch X agent to do Y",
  "run bug-finder agent on component Z", "use Gemini to review X", "run both Claude and Gemini
  agents on Y", "launch a Gemini doc-reviewer and a Claude bug-finder in parallel".
---

# Delegate Agent

Two agent backends are available: **Claude** (via Agent tool) and **Gemini** (via CLI). Run them in parallel whenever multiple agents are requested.

## Claude Agent

Use the built-in `Agent` tool. Select the appropriate `subagent_type` from the available agents listed in the system prompt.

Key parameters:
- `subagent_type`: the agent type (e.g., `bug-finder`, `doc-reviewer`, `architecture-reviewer`)
- `prompt`: a self-contained brief — the agent has no conversation context, so include file paths, what to look for, and what format to return results in
- `run_in_background: true` when launching in parallel with other agents

## Gemini Agent

Use `gemini_interface.py` to delegate to Gemini CLI with a specific agent's system prompt.

```bash
python ~/.claude/skills/arewedone-g/scripts/gemini_interface.py \
  --prompt "<task prompt>" \
  --system-md ~/.claude/agents/<agent-name>.md \
  --cwd "$(pwd)" \
  --model gemini-3.1-pro-preview
```

By default, only the final model response is emitted (no tool call logs or IDE noise). Pass `--verbose` to stream all output — useful for debugging.

Available agent definitions: `~/.claude/agents/*.md`

To attach context (e.g., git diff, file list):
```bash
echo "Context..." > /tmp/agent-context.txt
python ~/.claude/skills/arewedone-g/scripts/gemini_interface.py \
  --prompt "Review the attached context. @/tmp/agent-context.txt" \
  --system-md ~/.claude/agents/bug-finder.md \
  --cwd "$(pwd)"
```

## Running in Parallel

When both Claude and Gemini agents are requested, or multiple agents of either type:

1. Launch all Claude agents in a single message with `run_in_background: true`
2. Launch all Gemini agents as background Bash commands (`run_in_background: true`)
3. Wait for results, then synthesize findings

Example for "run Claude bug-finder on src/auth and Gemini bug-finder on src/payments":

```
# Message 1: launch both simultaneously
Agent(subagent_type="bug-finder", prompt="Find bugs in src/auth/...", run_in_background=true)
Bash("python ~/.claude/skills/arewedone-g/scripts/gemini_interface.py --prompt '...' --system-md ~/.claude/agents/bug-finder.md --cwd $(pwd)", run_in_background=true)
```

## Constructing Good Prompts

Claude agents have no conversation context — include everything they need:
- What files or components to examine
- What specifically to look for
- What format to return (e.g., "list bugs with file:line references")

For Gemini, the `--system-md` file provides role/persona; `--prompt` provides the specific task.
