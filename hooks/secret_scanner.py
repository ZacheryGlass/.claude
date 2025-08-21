#!/usr/bin/env python3
"""
Secret Scanner Hook for Claude Code

Scans git commits for potential secrets (API keys, passwords, tokens) before they're committed.
Blocks commits containing sensitive data and provides feedback to Claude.
"""
import json
import sys
import re
import subprocess
import os
from typing import List, Tuple, Dict, Any

# Common secret patterns with descriptions
SECRET_PATTERNS = [
    # API Keys
    (r'\b[A-Za-z0-9]{20,}\b', 'Generic API key pattern (20+ chars)'),
    (r'sk-[A-Za-z0-9]{48,}', 'OpenAI API key'),
    (r'xoxb-[A-Za-z0-9-]{50,}', 'Slack bot token'),
    (r'xoxp-[A-Za-z0-9-]{50,}', 'Slack user token'),
    (r'ghp_[A-Za-z0-9]{36}', 'GitHub personal access token'),
    (r'ghs_[A-Za-z0-9]{36}', 'GitHub app token'),
    (r'AKIA[0-9A-Z]{16}', 'AWS access key'),
    (r'AIza[0-9A-Za-z-_]{35}', 'Google API key'),
    
    # Passwords and secrets in various formats
    (r'(?i)(password|passwd|pwd|secret|key|token|auth)\s*[:=]\s*["\']?[A-Za-z0-9!@#$%^&*()_+\-=\[\]{};\':"\\|,.<>\/?]{8,}["\']?', 'Password/secret assignment'),
    (r'(?i)(api_key|apikey|access_key|secret_key)\s*[:=]\s*["\']?[A-Za-z0-9!@#$%^&*()_+\-=\[\]{};\':"\\|,.<>\/?]{16,}["\']?', 'API key assignment'),
    
    # Database connection strings
    (r'(?i)(mongodb|mysql|postgresql|postgres)://[^\s\'"]*:[^\s\'"]*@', 'Database connection string with credentials'),
    
    # JWT tokens
    (r'eyJ[A-Za-z0-9-_=]+\.eyJ[A-Za-z0-9-_=]+\.[A-Za-z0-9-_.+/=]*', 'JWT token'),
    
    # Private keys
    (r'-----BEGIN\s+(RSA\s+)?PRIVATE KEY-----', 'Private key'),
    (r'-----BEGIN\s+OPENSSH\s+PRIVATE KEY-----', 'OpenSSH private key'),
    
    # Common cloud tokens
    (r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', 'UUID (possible token)'),
]

# Files to always check regardless of git status
ALWAYS_CHECK_EXTENSIONS = {'.env', '.json', '.yaml', '.yml', '.toml', '.ini', '.conf', '.config'}

# Files/paths to skip scanning
SKIP_PATTERNS = [
    r'\.git/',
    r'node_modules/',
    r'__pycache__/',
    r'\.venv/',
    r'venv/',
    r'\.pytest_cache/',
    r'\.coverage',
    r'coverage\.xml',
    r'\.nyc_output/',
    r'dist/',
    r'build/',
    r'target/',
    r'\.DS_Store',
    r'Thumbs\.db',
    r'\.lock$',
    r'package-lock\.json$',
    r'yarn\.lock$',
    r'Pipfile\.lock$',
    r'poetry\.lock$',
]

def should_skip_file(file_path: str) -> bool:
    """Check if file should be skipped based on patterns."""
    for pattern in SKIP_PATTERNS:
        if re.search(pattern, file_path):
            return True
    return False

def get_staged_files() -> List[str]:
    """Get list of staged files from git."""
    try:
        result = subprocess.run(
            ['git', 'diff', '--cached', '--name-only'],
            capture_output=True,
            text=True,
            cwd=os.getcwd()
        )
        if result.returncode == 0:
            return [f.strip() for f in result.stdout.split('\n') if f.strip()]
    except Exception:
        pass
    return []

def get_file_content(file_path: str) -> str:
    """Get file content, handling various encodings."""
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            return f.read()
    except UnicodeDecodeError:
        try:
            with open(file_path, 'r', encoding='latin1') as f:
                return f.read()
        except Exception:
            return ""
    except Exception:
        return ""

def scan_content_for_secrets(content: str, file_path: str) -> List[Tuple[str, str, int]]:
    """Scan content for secret patterns. Returns list of (pattern_description, matched_text, line_number)."""
    secrets_found = []
    lines = content.split('\n')
    
    for line_num, line in enumerate(lines, 1):
        for pattern, description in SECRET_PATTERNS:
            matches = re.finditer(pattern, line)
            for match in matches:
                # Skip if it looks like a placeholder or example
                matched_text = match.group()
                if is_likely_placeholder(matched_text):
                    continue
                    
                secrets_found.append((description, matched_text, line_num))
    
    return secrets_found

def is_likely_placeholder(text: str) -> bool:
    """Check if text is likely a placeholder rather than real secret."""
    placeholders = [
        'example', 'sample', 'test', 'demo', 'placeholder', 'your_key_here',
        'insert_key', 'replace_with', 'xxxx', 'yyyy', '****', '....',
        'fake', 'dummy', 'mock', 'template'
    ]
    
    text_lower = text.lower()
    
    # Check for common placeholder patterns
    if any(placeholder in text_lower for placeholder in placeholders):
        return True
    
    # Check for repeated characters (like 'aaaaaaaaaa' or '1111111111')
    if len(set(text)) <= 2 and len(text) > 8:
        return True
    
    # Check for sequential patterns
    if re.match(r'^(abc|123|qwe|asd)', text_lower):
        return True
    
    return False

def is_git_commit_command(command: str) -> bool:
    """Check if the command is a git commit."""
    # Match various git commit patterns
    patterns = [
        r'\bgit\s+commit\b',
        r'\bgit.*-m\s+',
        r'\bgit.*--message\s+'
    ]
    
    for pattern in patterns:
        if re.search(pattern, command, re.IGNORECASE):
            return True
    
    return False

def main():
    try:
        # Read hook input
        input_data = json.load(sys.stdin)
        
        tool_name = input_data.get("tool_name", "")
        tool_input = input_data.get("tool_input", {})
        command = tool_input.get("command", "")
        
        # Only process git commit commands
        if tool_name != "Bash" or not is_git_commit_command(command):
            sys.exit(0)  # Allow non-git-commit commands to proceed
        
        print(f"🔍 Scanning for secrets before commit...", file=sys.stderr)
        
        # Get staged files
        staged_files = get_staged_files()
        
        if not staged_files:
            print("ℹ️  No staged files to scan", file=sys.stderr)
            sys.exit(0)
        
        secrets_found = []
        files_scanned = 0
        
        for file_path in staged_files:
            if should_skip_file(file_path):
                continue
                
            if not os.path.exists(file_path):
                continue  # File might have been deleted
            
            content = get_file_content(file_path)
            if not content:
                continue
                
            file_secrets = scan_content_for_secrets(content, file_path)
            if file_secrets:
                secrets_found.extend([(file_path, desc, text, line) for desc, text, line in file_secrets])
            
            files_scanned += 1
        
        print(f"📁 Scanned {files_scanned} files", file=sys.stderr)
        
        if secrets_found:
            print(f"\n🚨 COMMIT BLOCKED: Found {len(secrets_found)} potential secret(s):", file=sys.stderr)
            print("", file=sys.stderr)
            
            # Group by file for better output
            by_file = {}
            for file_path, desc, text, line in secrets_found:
                if file_path not in by_file:
                    by_file[file_path] = []
                by_file[file_path].append((desc, text, line))
            
            for file_path, file_secrets in by_file.items():
                print(f"📄 {file_path}:", file=sys.stderr)
                for desc, text, line in file_secrets:
                    # Truncate long secrets for display
                    display_text = text if len(text) <= 50 else text[:47] + "..."
                    print(f"   Line {line}: {desc}", file=sys.stderr)
                    print(f"   Found: {display_text}", file=sys.stderr)
                print("", file=sys.stderr)
            
            print("🛠️  Please remove or replace these secrets with:", file=sys.stderr)
            print("   • Environment variables", file=sys.stderr)
            print("   • Configuration files (not committed)", file=sys.stderr)
            print("   • Secret management services", file=sys.stderr)
            print("   • Placeholders for documentation", file=sys.stderr)
            print("", file=sys.stderr)
            print("🔧 Then stage your changes and commit again.", file=sys.stderr)
            
            # Exit code 2 blocks the tool call and shows stderr to Claude
            sys.exit(2)
        
        print("✅ No secrets detected in staged files", file=sys.stderr)
        sys.exit(0)  # Allow commit to proceed
        
    except json.JSONDecodeError as e:
        print(f"❌ Error: Invalid JSON input: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"❌ Error during secret scan: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()