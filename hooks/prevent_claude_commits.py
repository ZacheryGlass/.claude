#!/usr/bin/env python3
"""
Hook to prevent commits containing "Claude" or "Anthropic" in any form.
Blocks commits with these terms in:
- Commit messages
- Author fields
- Co-author fields
"""
import json
import sys
import re

def check_git_commit_command(command):
    """Check if a git commit command contains prohibited terms."""
    prohibited_terms = ['claude', 'anthropic']
    command_lower = command.lower()
    
    # Check for prohibited terms in the entire command
    for term in prohibited_terms:
        if term in command_lower:
            return True, f"Command contains '{term}' - removing all Claude/Anthropic references"
    
    # Specific checks for git commit patterns
    if 'git commit' in command:
        # Check for co-author patterns
        if re.search(r'co-authored-by:.*claude', command_lower):
            return True, "Removing Claude as co-author from commit"
        
        # Check for author override attempts
        if '--author' in command and any(term in command_lower for term in prohibited_terms):
            return True, "Cannot set Claude/Anthropic as commit author"
            
    return False, None

def suggest_cleaned_command(command):
    """Suggest a cleaned version of the command."""
    # Remove co-author lines with Claude/Anthropic
    cleaned = re.sub(r'(?i)co-authored-by:.*(?:claude|anthropic).*\n?', '', command)
    
    # Remove Claude emoji and related text
    cleaned = re.sub(r'🤖.*(?:claude|anthropic).*\n?', '', cleaned, flags=re.IGNORECASE)
    
    # Remove any lines mentioning generated with Claude
    cleaned = re.sub(r'(?i).*generated with.*claude.*\n?', '', cleaned)
    
    # Clean up author fields
    if '--author' in cleaned:
        cleaned = re.sub(r'--author[= ]["\']?[^"\']*(?:claude|anthropic)[^"\']*["\']?', '', cleaned, flags=re.IGNORECASE)
    
    # Remove extra whitespace and newlines
    cleaned = re.sub(r'\n{3,}', '\n\n', cleaned)
    cleaned = cleaned.strip()
    
    return cleaned

def main():
    try:
        input_data = json.load(sys.stdin)
        tool_name = input_data.get('tool_name', '')
        
        # Only check Bash commands
        if tool_name != 'Bash':
            sys.exit(0)
            
        command = input_data.get('tool_input', {}).get('command', '')
        
        # Check if this is a git commit command
        if 'git commit' not in command and 'git config' not in command:
            sys.exit(0)
        
        # Block git config commands that try to set Claude as author
        if 'git config' in command:
            command_lower = command.lower()
            if 'user.name' in command and ('claude' in command_lower or 'anthropic' in command_lower):
                print("❌ BLOCKED: Cannot set git user.name to Claude or Anthropic")
                print("Use the default git settings for commits")
                sys.exit(2)  # Exit code 2 blocks the command
            if 'user.email' in command and ('claude' in command_lower or 'anthropic' in command_lower):
                print("❌ BLOCKED: Cannot set git user.email with Claude/Anthropic")
                print("Use the default git settings for commits")
                sys.exit(2)
                
        # Check git commit commands
        has_issue, message = check_git_commit_command(command)
        
        if has_issue:
            print(f"❌ BLOCKED: {message}")
            print("\nYour CLAUDE.md configuration specifies:")
            print("- Never add Claude as a commit author")
            print("- Always commit using the default git settings")
            
            # Suggest cleaned command if it's a commit
            if 'git commit' in command:
                cleaned = suggest_cleaned_command(command)
                if cleaned and 'git commit' in cleaned:
                    print("\n✅ Suggested cleaned command:")
                    print(cleaned)
                    print("\nThe commit will use your default git author settings.")
            
            sys.exit(2)  # Exit code 2 blocks the command
            
    except Exception as e:
        # Silent fail - don't break Claude's workflow
        sys.exit(0)

if __name__ == '__main__':
    main()