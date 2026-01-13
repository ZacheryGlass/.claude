#!/usr/bin/env python3
"""
Claude Code Documentation Sync Script
Downloads all documentation from https://code.claude.com/docs/
"""

import os
import sys
import requests
from pathlib import Path
import time
import re

# Configuration
BASE_URL = "https://code.claude.com/docs/en"
LLMS_TXT_URL = "https://code.claude.com/docs/llms.txt"
DOCS_DIR = Path(__file__).parent / "docs"

def ensure_dependencies():
    """Ensure required libraries are available"""
    try:
        import requests
        return True
    except ImportError as e:
        print(f"Error: Required library not found: {e}")
        print("Please install dependencies with: pip install requests")
        return False

def discover_pages():
    """Discover all documentation pages by parsing llms.txt"""
    try:
        print("Discovering documentation pages from llms.txt...")
        response = requests.get(LLMS_TXT_URL, timeout=30)
        response.raise_for_status()

        # Parse llms.txt to extract page names
        # Format: - [Title](https://code.claude.com/docs/en/page-name.md): Description
        pages = []
        pattern = re.compile(r'\[.*?\]\(https://code\.claude\.com/docs/en/([a-z0-9-]+)\.md\)')

        for line in response.text.splitlines():
            match = pattern.search(line)
            if match:
                page_name = match.group(1)
                pages.append(page_name)

        pages = sorted(list(set(pages)))  # Remove duplicates and sort
        print(f"Discovered {len(pages)} documentation pages")
        return pages

    except Exception as e:
        print(f"Error discovering pages: {e}")
        return None

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

def clean_docs_directory():
    """Remove all existing documentation files"""
    if DOCS_DIR.exists():
        for file in DOCS_DIR.glob("*.md"):
            try:
                file.unlink()
                print(f"Removed old file: {file.name}")
            except Exception as e:
                print(f"Warning: Could not remove {file.name}: {e}")

def main():
    """Main sync function"""
    if not ensure_dependencies():
        return 1

    # Parse command line arguments
    if len(sys.argv) > 1:
        # Sync specific pages
        pages_to_sync = sys.argv[1:]
        print(f"Syncing specific pages: {', '.join(pages_to_sync)}")
    else:
        # Discover all pages automatically
        pages_to_sync = discover_pages()
        if not pages_to_sync:
            print("Failed to discover pages automatically")
            return 1

        # Clean old docs before full sync
        print("\nCleaning old documentation files...")
        clean_docs_directory()

    # Create docs directory
    DOCS_DIR.mkdir(exist_ok=True)

    if len(pages_to_sync) == 1:
        print(f"\nSyncing Claude Code documentation page: {pages_to_sync[0]}")
    else:
        print(f"\nSyncing {len(pages_to_sync)} Claude Code documentation pages...")
    print(f"Target directory: {DOCS_DIR}\n")

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