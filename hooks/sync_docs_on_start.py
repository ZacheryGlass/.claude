#!/usr/bin/env python3
"""
Session start hook to sync Claude Code documentation
Runs the documentation sync script when a new Claude Code session starts
"""

import subprocess
import sys
import os
from pathlib import Path

def main():
    """Run the documentation sync script"""
    try:
        # Get the directory containing this hook
        hook_dir = Path(__file__).parent
        claude_dir = hook_dir.parent
        
        # Path to the sync script
        sync_script = claude_dir / "sync-docs.py"
        
        if not sync_script.exists():
            print("Documentation sync script not found, skipping sync")
            return 0
        
        print("Syncing Claude Code documentation...")
        
        # Run the sync script
        result = subprocess.run([
            sys.executable, str(sync_script)
        ], capture_output=True, text=True, cwd=str(claude_dir))
        
        if result.returncode == 0:
            print("+ Documentation sync completed successfully")
        else:
            print("! Documentation sync completed with warnings")
            if result.stderr:
                print(f"Errors: {result.stderr.strip()}")
        
        return 0
        
    except Exception as e:
        print(f"- Documentation sync failed: {e}")
        return 0  # Don't block the session if sync fails

if __name__ == '__main__':
    sys.exit(main())