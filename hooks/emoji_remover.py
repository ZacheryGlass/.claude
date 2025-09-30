#!/usr/bin/env python3
"""
Emoji checker hook for Claude Code.
Detects emojis in edited files and asks Claude to remove them.
"""
import json
import sys
import os
import re

# Emoji pattern to detect any emoji
EMOJI_PATTERN = re.compile(
    "["
    "\U0001F600-\U0001F64F"  # emoticons
    "\U0001F300-\U0001F5FF"  # symbols & pictographs
    "\U0001F680-\U0001F6FF"  # transport & map symbols
    "\U0001F1E0-\U0001F1FF"  # flags
    "\U00002700-\U000027BF"  # dingbats
    "\U0001F900-\U0001F9FF"  # supplemental symbols
    "\U00002600-\U000026FF"  # misc symbols
    "\U0001FA70-\U0001FAFF"  # symbols and pictographs extended-A
    "\U00002300-\U000023FF"  # misc technical
    "]+",
    flags=re.UNICODE
)

try:
    input_data = json.load(sys.stdin)
    tool_input = input_data.get('tool_input', {})
    file_path = tool_input.get('file_path', '')

    if not file_path or not os.path.exists(file_path):
        sys.exit(0)

    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()

    # Check for emojis
    emojis_found = EMOJI_PATTERN.findall(content)

    if emojis_found:
        # Exit with code 2 to block and provide feedback to Claude
        print(f"Emojis are not allowed in files. Please remove or replace the emojis in {file_path} with text equivalents like [X], [OK], [WARNING], etc.", file=sys.stderr)
        sys.exit(2)

    sys.exit(0)

except:
    sys.exit(0)
