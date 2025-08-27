#!/usr/bin/env python3
"""
SessionStart hook to capture context overhead from Claude Code.
Uses a lock file to prevent infinite recursion.
"""
import json
import os
import sys
import subprocess
import time
import re
from pathlib import Path

# Lock file to prevent recursion (stays in global .claude to prevent conflicts)
LOCK_FILE = Path.home() / ".claude" / ".context_hook_lock"

# Context overhead file goes in local .claude directory
LOCAL_CLAUDE_DIR = Path.cwd() / ".claude"
OVERHEAD_FILE = LOCAL_CLAUDE_DIR / "context_overhead.json"
TIMEOUT = 30  # seconds to wait for context command

def main():
    # Check if lock exists - if so, another instance is running
    if LOCK_FILE.exists():
        print(f"Lock file exists at {LOCK_FILE}, removing stale lock and continuing", file=sys.stderr)
        try:
            LOCK_FILE.unlink()
        except Exception as e:
            print(f"Failed to remove stale lock file: {e}", file=sys.stderr)
            sys.exit(1)
    
    try:
        # Create lock file
        LOCK_FILE.touch()
        
        # Ensure local .claude directory exists
        LOCAL_CLAUDE_DIR.mkdir(parents=True, exist_ok=True)
        
        print(f"Setting up context overhead constants in {LOCAL_CLAUDE_DIR}...", file=sys.stderr)
        
        # For now, use the known overhead values from the latest /context output
        # These can be manually updated by running /context and updating the script
        # Based on the latest /context output:
        # - System prompt: 3.0k tokens
        # - System tools: 12.4k tokens  
        # - MCP tools: 46.2k tokens
        # - Custom agents: 444 tokens
        # - Memory files: 39 tokens
        overhead = {
            "system_prompt": 3000,      # 3.0k
            "system_tools": 12400,      # 12.4k
            "mcp_tools": 46200,         # 46.2k
            "custom_agents": 444,       # 444
            "memory_files": 39,         # 39
            "total_overhead": 0,        # Will be calculated
            "timestamp": time.time(),
            "note": "For reference only - not used in statusline calculation. The transcript's input_tokens already includes this overhead."
        }
        
        # Calculate total overhead (everything except messages)
        overhead["total_overhead"] = sum([
            overhead["system_prompt"],
            overhead["system_tools"],
            overhead["mcp_tools"],
            overhead["custom_agents"],
            overhead["memory_files"]
        ])
        
        # Save to file
        with open(OVERHEAD_FILE, 'w') as f:
            json.dump(overhead, f, indent=2)
        print(f"Context overhead saved: {overhead['total_overhead']} tokens", file=sys.stderr)
            
    except Exception as e:
        print(f"Error setting up context overhead: {e}", file=sys.stderr)
    finally:
        # Always remove lock file
        if LOCK_FILE.exists():
            LOCK_FILE.unlink()

def parse_context_output(output):
    """Parse the /context command output to extract overhead tokens."""
    try:
        overhead = {
            "system_prompt": 0,
            "system_tools": 0,
            "mcp_tools": 0,
            "custom_agents": 0,
            "memory_files": 0,
            "total_overhead": 0,
            "timestamp": time.time()
        }
        
        # Parse lines like: "System prompt: 3.0k tokens (1.5%)"
        patterns = {
            "system_prompt": r"System prompt:\s*([\d.]+)k?\s*tokens",
            "system_tools": r"System tools:\s*([\d.]+)k?\s*tokens", 
            "mcp_tools": r"MCP tools:\s*([\d.]+)k?\s*tokens",
            "custom_agents": r"Custom agents:\s*([\d.]+)\s*tokens",
            "memory_files": r"Memory files:\s*([\d.]+)\s*tokens"
        }
        
        for key, pattern in patterns.items():
            match = re.search(pattern, output, re.IGNORECASE)
            if match:
                value = match.group(1)
                # Convert k notation to actual number
                if 'k' in match.group(0).lower():
                    overhead[key] = int(float(value) * 1000)
                else:
                    overhead[key] = int(float(value))
        
        # Calculate total overhead (everything except messages)
        overhead["total_overhead"] = sum([
            overhead["system_prompt"],
            overhead["system_tools"],
            overhead["mcp_tools"],
            overhead["custom_agents"],
            overhead["memory_files"]
        ])
        
        return overhead
        
    except Exception as e:
        print(f"Error parsing context output: {e}", file=sys.stderr)
        return None

if __name__ == "__main__":
    main()