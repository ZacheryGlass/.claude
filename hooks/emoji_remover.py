#!/usr/bin/env python3
"""
Emoji checker hook for Claude Code.
Detects emojis in the text an edit adds and asks Claude to remove them.
Emojis already in the file are left alone, so editing around them is not blocked.
"""
import json
import sys
import re
from collections import Counter

# Emoji pattern to detect any emoji, one character per match
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
    "]",
    flags=re.UNICODE
)


def text_of(value):
    return value if isinstance(value, str) else ''


def written_text(tool_input):
    """(old, new) pairs for the text the tool call wrote; old is what the new text replaced."""
    pairs = []
    if 'new_string' in tool_input:  # Edit
        pairs.append((text_of(tool_input.get('old_string')), text_of(tool_input['new_string'])))
    for edit in tool_input.get('edits') or []:  # MultiEdit
        if isinstance(edit, dict):
            pairs.append((text_of(edit.get('old_string')), text_of(edit.get('new_string'))))
    if 'content' in tool_input:  # Write: the whole file, so there is nothing to subtract
        pairs.append(('', text_of(tool_input['content'])))
    if 'new_source' in tool_input:  # NotebookEdit
        pairs.append(('', text_of(tool_input['new_source'])))
    return pairs


try:
    input_data = json.load(sys.stdin)
    tool_input = input_data.get('tool_input', {})
    file_path = tool_input.get('file_path') or tool_input.get('notebook_path') or 'the edited file'

    # Only emojis beyond those the edit replaced count as added
    emojis_added = []
    for old, new in written_text(tool_input):
        added = Counter(EMOJI_PATTERN.findall(new)) - Counter(EMOJI_PATTERN.findall(old))
        emojis_added.extend(added.elements())

    if emojis_added:
        # Exit with code 2 to block and provide feedback to Claude
        print(f"Emojis are not allowed in files. Please remove or replace the emojis in {file_path} with text equivalents like [X], [OK], [WARNING], etc.", file=sys.stderr)
        sys.exit(2)

    sys.exit(0)

except Exception:
    sys.exit(0)
