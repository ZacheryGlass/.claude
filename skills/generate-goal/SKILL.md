---
name: generate-goal
description: Synthesize the current conversation into a single, self-contained `/goal` prompt that Claude Code can run to continue the agreed-upon work autonomously — so the user never has to hand-summarize a long discussion into a goal directive. Use when the user and Claude have converged on what to do next and the user wants to hand it off to the `/goal` command. Triggers include "generate a goal", "make/write a goal prompt", "turn this into a /goal", "hand this off to /goal", "goalify this", or "/generate-goal". Outputs the prompt to chat only; never writes files to disk.
---

# Generate Goal

Turn the accumulated understanding in the current conversation into one ready-to-run `/goal` prompt. The user has been discussing what to work on next and wants that context distilled into a directive they can paste into `/goal` (or that Claude can run) without summarizing it themselves.

## Hard rules

- **Never write files.** Output the prompt to chat in a single fenced code block. No `.goal` file, no scratch file — nothing on disk.
- **The prompt must be self-contained.** A `/goal` run is a fresh autonomous agent that does **not** share this conversation's memory. Bake in every load-bearing fact it needs (paths, commands, knob names, current state, decisions). Assume it starts cold.
- **End with a measurable completion condition.** `/goal` runs turn after turn until a small evaluator model confirms the condition holds. The evaluator reads the transcript; it does not run commands. So the condition must be provable from what the agent *surfaces* (files exist and are committed, a test result is reported, a stated number/verdict appears).

## Process

1. **Identify the objective.** Pin down the one thing the conversation converged on as the next work. If it is genuinely ambiguous, or several distinct goals are in play, ask one focused clarifying question before generating — otherwise proceed.
2. **Mine the conversation for what a cold agent needs.** Pull the specifics, not a vibe: decisions made (and the why when it guides tradeoffs), exact file paths / commands / flags / knob names / URLs surfaced, current state (what is done, in-flight, or blocked), constraints ("don't touch X", "keep pins green"), and gotchas already learned. Prefer concrete references over prose.
3. **Compose the prompt** (start the text with `/goal`), in this order:
   - **Directive** — role + what to accomplish, stated so it stands alone.
   - **Context** — the minimal essential facts from step 2 (paths, commands, current state). Enough to start cold, no conversation color.
   - **Constraints** — what must not change or break on the way there.
   - **COMPLETION** — one measurable end state + how to prove it (an evaluator-checkable clause), then a turn cap: `Stop after N turns and report status if not done.`
4. **Tighten.** Every sentence earns its place. Cut recap and narration; keep decisions and specifics. Succinct but complete.
5. **Output** the final prompt in one fenced code block, then offer to adjust scope, constraints, or the turn cap. Do not save it.

## What makes the completion condition hold up

Weak (unverifiable / open-ended): `improve the backtest realism`, `make the tests better`.

Strong (one end state + stated check + guardrail):
- `COMPLETION: bin/backtest builds, make test reports 4/4 byte-identical pins, and docs/state/BACKTEST_REALISM.md has a new changelog row with the OFF-vs-ON per-market PnL. No change to canonical defaults. Stop after 30 turns and report status if not done.`

Match the turn cap to the scope (a focused change ~15–25; a multi-part build ~40+). The cap is a safety valve so a stuck run halts and reports instead of looping.

## Example

Conversation converged on: add a default-off env knob, prove it is pins-neutral, and measure it.

Generated output:

```
/goal You are an autonomous agent continuing prior work in this repo. Read CLAUDE.md first. TASK: add env flag FILL_MODEL_TAKER_PERLEVEL_FEE (default 0) in src/trading/execution/exchange_sim.c so that, when ON, the taker fee is summed per consumed book level instead of computed once on the VWAP; keep taker_matcher.c pure. CONSTRAINTS: default OFF must be byte-identical — `make test` green and check_bt_pins = OK 4 byte-identical with the flag OFF; if pins break the flag is leaking, STOP and fix. VALIDATION: add tests/test_taker_realism.c::test_perlevel_fee_vs_vwap_fee proving the per-level sum equals the sum of fees_v2_taker(shares_i, px_i). COMPLETION: flag implemented default-OFF, make test green, pins 4/4 byte-identical, the new unit test present and passing per the reported test output, changes committed. Stop after 30 turns and report status if not done.
```

Then offer: adjust the turn cap, tighten the completion check, or add/remove constraints.
