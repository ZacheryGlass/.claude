#!/usr/bin/env python3
"""
Claude Code Documentation Sync Script
Downloads all documentation from https://docs.anthropic.com/en/docs/claude-code/
"""

import os
import sys
import requests
from pathlib import Path
import time
from urllib.parse import urljoin

# Configuration
BASE_URL = "https://docs.anthropic.com/en/docs/claude-code"
DOCS_DIR = Path(__file__).parent / "docs"

# All Claude Code documentation pages
PAGES = [
    "overview",
    "quickstart", 
    "memory",
    "common-workflows",
    "ide-integrations",
    "mcp",
    "github-actions",
    "sdk",
    "troubleshooting",
    "third-party-integrations",
    "amazon-bedrock",
    "google-vertex-ai",
    "corporate-proxy",
    "llm-gateway",
    "devcontainer",
    "iam",
    "security",
    "monitoring-usage",
    "costs",
    "cli-reference",
    "interactive-mode",
    "slash-commands",
    "settings",
    "hooks",
    "sub-agents",
    "output-styles",
    "hooks-guide",
]

def ensure_requests():
    """Ensure requests library is available"""
    try:
        import requests
        return True
    except ImportError:
        print("Error: requests library not found")
        print("Please install it with: pip install requests")
        return False

def download_page(page_name):
    """Download a single documentation page directly as markdown"""
    url = f"{BASE_URL}/{page_name}.md"  # Direct markdown URL
    output_file = DOCS_DIR / f"{page_name}.md"
    
    try:
        print(f"Downloading: {page_name}")
        response = requests.get(url, timeout=30)
        response.raise_for_status()
        
        # Save the markdown content directly
        content = response.text
        
        # Add a header with metadata
        header = f"""<!-- 
Source: {url}
Downloaded: {time.strftime('%Y-%m-%d %H:%M:%S')}
-->

"""
        
        with open(output_file, 'w', encoding='utf-8') as f:
            f.write(header + content)
            
        print(f"+ Downloaded: {page_name}")
        return True
        
    except requests.RequestException as e:
        print(f"- Failed to download {page_name}: {e}")
        return False
    except Exception as e:
        print(f"- Error processing {page_name}: {e}")
        return False

def main():
    """Main sync function"""
    if not ensure_requests():
        return 1
        
    # Parse command line arguments
    if len(sys.argv) > 1:
        # Sync specific pages
        pages_to_sync = sys.argv[1:]
        # Validate that requested pages exist in our known pages
        invalid_pages = [p for p in pages_to_sync if p not in PAGES]
        if invalid_pages:
            print(f"Unknown pages: {', '.join(invalid_pages)}")
            print(f"Available pages: {', '.join(PAGES)}")
            return 1
    else:
        # Sync all pages
        pages_to_sync = PAGES
        
    # Create docs directory
    DOCS_DIR.mkdir(exist_ok=True)
    
    if len(pages_to_sync) == 1:
        print(f"Syncing Claude Code documentation page: {pages_to_sync[0]}")
    else:
        print("Syncing Claude Code documentation...")
    print(f"Target directory: {DOCS_DIR}")
    
    success_count = 0
    total_count = len(pages_to_sync)
    
    for page in pages_to_sync:
        if download_page(page):
            success_count += 1
        time.sleep(0.5)  # Be respectful to the server
    
    print(f"\nSync complete! {success_count}/{total_count} pages downloaded")
    print(f"Files saved to: {DOCS_DIR}")
    
    return 0 if success_count == total_count else 1

if __name__ == "__main__":
    sys.exit(main())