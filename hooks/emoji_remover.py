#!/usr/bin/env python3
"""
Emoji remover hook for Claude Code.
Replaces emojis with non-emoji equivalents in edited files.
"""
import json
import sys
import re
import os

# Define emoji replacements
EMOJI_REPLACEMENTS = [
    ('❌', '[X]'),          # Cross mark
    ('✓', '[OK]'),          # Check mark
    ('✅', '[OK]'),         # White check mark
    ('⚠️', '[WARNING]'),    # Warning sign
    ('⚠', '[WARNING]'),     # Warning sign (no variation selector)
    ('ℹ️', '[INFO]'),       # Information
    ('ℹ', '[INFO]'),        # Information (no variation selector)
    ('🔍', '[SEARCH]'),     # Magnifying glass
    ('📝', '[NOTE]'),       # Memo
    ('💡', '[TIP]'),        # Light bulb
    ('🚀', '[ROCKET]'),     # Rocket
    ('🐛', '[BUG]'),        # Bug
    ('🔧', '[TOOL]'),       # Wrench
    ('📦', '[PACKAGE]'),    # Package
    ('🔒', '[LOCKED]'),     # Lock
    ('🔓', '[UNLOCKED]'),   # Unlocked
    ('👍', '[THUMBS_UP]'),  # Thumbs up
    ('👎', '[THUMBS_DOWN]'),# Thumbs down
    ('🎉', '[CELEBRATE]'),  # Party popper
    ('⭐', '[STAR]'),       # Star
    ('🔥', '[FIRE]'),       # Fire
    ('💻', '[COMPUTER]'),   # Computer
    ('📁', '[FOLDER]'),     # Folder
    ('📄', '[FILE]'),       # File
]

def remove_emojis(content):
    """Replace emojis with their non-emoji equivalents."""
    modified = content
    replacements_made = []

    for emoji, replacement in EMOJI_REPLACEMENTS:
        if emoji in modified:
            count = modified.count(emoji)
            modified = modified.replace(emoji, replacement)
            replacements_made.append(f"{emoji} -> {replacement} ({count}x)")

    return modified, replacements_made

try:
    # Read input from stdin
    input_data = json.load(sys.stdin)

    # Extract file path from tool input
    tool_input = input_data.get('tool_input', {})
    file_path = tool_input.get('file_path', '')

    # Only process if we have a valid file path
    if not file_path or not os.path.exists(file_path):
        sys.exit(0)

    # Read the file
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()

    # Remove emojis
    modified_content, replacements = remove_emojis(content)

    # Only write if changes were made
    if replacements:
        with open(file_path, 'w', encoding='utf-8') as f:
            f.write(modified_content)

        # Report what was changed
        print(f"Replaced emojis in {file_path}:")
        for replacement in replacements:
            print(f"  {replacement}")

    sys.exit(0)

except Exception as e:
    print(f"Error in emoji remover hook: {e}", file=sys.stderr)
    sys.exit(1)