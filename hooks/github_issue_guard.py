#!/usr/bin/env python3
"""
GitHub Issue Content Guard Hook

WHAT THIS SCRIPT DOES:
- Prevents GitHub issues created through Claude Code from containing "Claude" or "Anthropic" references
- Blocks both MCP GitHub tools (mcp__github__create_issue, etc.) and gh CLI commands
- Allows emojis in GitHub issues (unlike the commit guard hook)
- Provides helpful error messages and suggests cleaned commands when blocking

SPECIFIC BEHAVIORS:
1. For MCP GitHub tools: Scans title, body, comment, and content fields for prohibited terms
2. For gh CLI commands: Scans the entire command line for prohibited terms  
3. Case-insensitive matching for "claude" and "anthropic"
4. Suggests cleaned versions of gh commands when possible
5. Exits with code 2 to block the operation when prohibited content is found

TRIGGERED BY:
- MCP tools: mcp__github__create_issue, mcp__github__add_issue_comment, mcp__github__update_issue
- Bash commands: gh issue create, gh issue edit, gh issue comment

This prevents issues like "Generated with Claude Code" from appearing in GitHub issues.
"""
import json
import sys
import re

def check_github_issue_content(text):
    """Check if text contains prohibited terms for GitHub issues."""
    if not text:
        return False, None
        
    prohibited_terms = ['claude', 'anthropic']
    text_lower = text.lower()
    
    # Check for prohibited terms
    for term in prohibited_terms:
        if term in text_lower:
            return True, f"Content contains '{term}' - removing all Claude/Anthropic references"
    
    return False, None

def check_mcp_github_tool(tool_name, tool_input):
    """Check MCP GitHub tools for prohibited content."""
    github_tools = [
        'mcp__github__create_issue',
        'mcp__github__add_issue_comment', 
        'mcp__github__update_issue'
    ]
    
    if tool_name not in github_tools:
        return False, None
    
    # Check various content fields
    fields_to_check = ['title', 'body', 'comment', 'content']
    
    for field in fields_to_check:
        if field in tool_input:
            has_issue, message = check_github_issue_content(tool_input[field])
            if has_issue:
                return True, f"Issue {field} {message}"
    
    return False, None

def check_gh_command(command):
    """Check gh CLI commands for prohibited content."""
    if not any(gh_cmd in command for gh_cmd in ['gh issue create', 'gh issue edit', 'gh issue comment']):
        return False, None
    
    command_lower = command.lower()
    prohibited_terms = ['claude', 'anthropic']
    
    # Check for prohibited terms in the entire command
    for term in prohibited_terms:
        if term in command_lower:
            return True, f"GitHub issue command contains '{term}' - removing all Claude/Anthropic references"
    
    return False, None

def suggest_cleaned_gh_command(command):
    """Suggest a cleaned version of the gh command."""
    # Remove any references to Claude or Anthropic
    cleaned = re.sub(r'(?i)\b(?:claude|anthropic)\b[^\s]*\s*', '', command)
    
    # Remove lines mentioning "Generated with Claude"
    cleaned = re.sub(r'(?i).*generated with.*claude.*', '', cleaned)
    
    # Remove "Co-Authored-By" lines with Claude/Anthropic
    cleaned = re.sub(r'(?i)co-authored-by:.*(?:claude|anthropic).*', '', cleaned)
    
    # Clean up extra whitespace
    cleaned = re.sub(r'\s+', ' ', cleaned)
    cleaned = cleaned.strip()
    
    return cleaned

def main():
    try:
        input_data = json.load(sys.stdin)
        tool_name = input_data.get('tool_name', '')
        tool_input = input_data.get('tool_input', {})
        
        # Check MCP GitHub tools
        if tool_name.startswith('mcp__github__'):
            has_issue, message = check_mcp_github_tool(tool_name, tool_input)
            if has_issue:
                print(f"BLOCKED: {message}", file=sys.stderr)
                print("GitHub issues cannot contain Claude or Anthropic references", file=sys.stderr)
                sys.exit(2)  # Exit code 2 blocks the command
        
        # Check Bash commands (for gh CLI)
        elif tool_name == 'Bash':
            command = tool_input.get('command', '')
            has_issue, message = check_gh_command(command)
            if has_issue:
                print(f"BLOCKED: {message}", file=sys.stderr)
                print("GitHub issues cannot contain Claude or Anthropic references", file=sys.stderr)
                
                # Suggest cleaned command
                cleaned = suggest_cleaned_gh_command(command)
                if cleaned and cleaned != command:
                    print("\nSuggested cleaned command:", file=sys.stderr)
                    print(cleaned, file=sys.stderr)
                
                sys.exit(2)  # Exit code 2 blocks the command
            
    except Exception as e:
        # Silent fail - don't break Claude's workflow
        sys.exit(0)

if __name__ == '__main__':
    main()