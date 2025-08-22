#!/bin/bash

# Get JSON input from stdin
input=$(cat)

# Extract current directory from JSON input
current_dir=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')

# Use current directory or fallback to pwd
if [ -n "$current_dir" ]; then
    dir_name=$(basename "$current_dir")
    cd "$current_dir" 2>/dev/null
else
    dir_name=$(basename "$(pwd)")
fi

# Get git branch, suppress errors
git_branch=$(git branch --show-current 2>/dev/null || echo "no-git")

# Output the status line
printf "Claude | %s | %s" "$dir_name" "$git_branch"