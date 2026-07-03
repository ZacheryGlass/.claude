#!/usr/bin/env python3
"""Check that a /goal prompt fits within the harness limit.

The /goal command caps the argument text (everything AFTER the leading
`/goal `) at 4000 characters. This script measures exactly that slice so a
generated prompt can be verified before it is handed to the user.

Usage:
    python check_goal_length.py path/to/prompt.txt
    python check_goal_length.py -           # read from stdin
    echo "/goal ..." | python check_goal_length.py

Exit code 0 = fits, 1 = over limit. Prints the counted length, the limit,
and remaining headroom (or overage).
"""
import sys

LIMIT = 4000  # hard cap enforced by the /goal command on the argument text


def measure(text: str) -> int:
    # Strip a single leading "/goal" token (with any following whitespace),
    # since the harness counts only what comes after it.
    stripped = text.lstrip()
    if stripped.startswith("/goal"):
        stripped = stripped[len("/goal"):]
    # The command trims surrounding whitespace before counting.
    return len(stripped.strip())


def main() -> int:
    if len(sys.argv) > 1 and sys.argv[1] != "-":
        with open(sys.argv[1], "r", encoding="utf-8") as fh:
            text = fh.read()
    else:
        text = sys.stdin.read()

    n = measure(text)
    if n <= LIMIT:
        print(f"PASS: {n}/{LIMIT} chars ({LIMIT - n} headroom)")
        return 0
    print(f"FAIL: {n}/{LIMIT} chars ({n - LIMIT} over) -- tighten before output")
    return 1


if __name__ == "__main__":
    sys.exit(main())
