#!/usr/bin/env python3
"""
Hook to prevent any modifications to files named CLAUDE.md
Protects both user-level and project-level CLAUDE.md files from being edited.
"""
import json
import sys
import os

def main():
    try:
        input_data = json.load(sys.stdin)
        tool_name = input_data.get('tool_name', '')
        
        # Check only file modification tools
        if tool_name not in ['Edit', 'MultiEdit', 'Write', 'NotebookEdit']:
            sys.exit(0)
            
        file_path = input_data.get('tool_input', {}).get('file_path', '')
        
        # Check if the file being modified is named CLAUDE.md
        if os.path.basename(file_path).upper() == 'CLAUDE.MD':
            print("❌ BLOCKED: Cannot modify CLAUDE.md files")
            print("\nCLAUDE.md files contain user instructions that should only be modified by the user directly.")
            print("These files are protected from automated modifications.")
            
            # Provide context about which CLAUDE.md was attempted
            if '.claude' in file_path:
                if os.path.expanduser('~') in file_path:
                    print("\nAttempted to modify: User-level CLAUDE.md (~/.claude/CLAUDE.md)")
                else:
                    print("\nAttempted to modify: Project-level CLAUDE.md (.claude/CLAUDE.md)")
            
            print("\nIf you need to update your instructions, please edit CLAUDE.md manually.")
            
            sys.exit(2)  # Exit code 2 blocks the command
            
    except Exception as e:
        # Silent fail - don't break Claude's workflow
        sys.exit(0)

if __name__ == '__main__':
    main()