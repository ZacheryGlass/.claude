#!/bin/bash

# Read Claude Code context from stdin
input=$(cat)

# Simple JSON parsing without jq using sed/grep
extract_json_value() {
    local key="$1"
    echo "$input" | grep -o "\"$key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | sed 's/.*"[^"]*"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' | head -1
}

# Extract relevant information
model_name=$(extract_json_value "display_name")
current_dir=$(extract_json_value "current_dir")
project_dir=$(extract_json_value "project_dir")

# Default to Claude if no model name found
if [[ -z "$model_name" ]]; then
    model_name="Claude"
fi

# Get just the directory name for cleaner display
if [[ -n "$current_dir" ]]; then
    # Convert Windows path to Unix-style for Git Bash
    current_dir=$(echo "$current_dir" | sed 's|\\|/|g')
    dir_name=$(basename "$current_dir")
else
    dir_name="~"
fi

# Check if we're in a git repository and get branch
git_info=""
if [[ -n "$current_dir" ]]; then
    if [[ -d "$current_dir/.git" ]] || git -C "$current_dir" rev-parse --git-dir >/dev/null 2>&1; then
        branch=$(git -C "$current_dir" branch --show-current 2>/dev/null)
        if [[ -n "$branch" ]]; then
            # Get git status indicators
            status_indicators=""
            
            # Check for uncommitted changes
            if [[ -n $(git -C "$current_dir" status --porcelain 2>/dev/null) ]]; then
                status_indicators="*"
            fi
            
            # Check if ahead/behind remote
            if git -C "$current_dir" rev-parse --abbrev-ref @{u} >/dev/null 2>&1; then
                ahead=$(git -C "$current_dir" rev-list --count @{u}..HEAD 2>/dev/null)
                behind=$(git -C "$current_dir" rev-list --count HEAD..@{u} 2>/dev/null)
                
                if [[ "$ahead" -gt 0 ]]; then
                    status_indicators="${status_indicators}↑${ahead}"
                fi
                if [[ "$behind" -gt 0 ]]; then
                    status_indicators="${status_indicators}↓${behind}"
                fi
            fi
            
            git_info="git:${branch}${status_indicators}"
        fi
    fi
fi

# Get project name if available
project_name=""
if [[ -n "$project_dir" ]] && [[ "$project_dir" != "$current_dir" ]]; then
    project_dir=$(echo "$project_dir" | sed 's|\\|/|g')
    project_name="$(basename "$project_dir")"
fi

# Build status line components
components=()

# Add model name
components+=("$model_name")

# Add project name if available
if [[ -n "$project_name" ]]; then
    components+=("$project_name")
else
    components+=("$dir_name")
fi

# Add git info if available
if [[ -n "$git_info" ]]; then
    components+=("$git_info")
fi

# Join components with separator
output=""
for i in "${!components[@]}"; do
    if [[ $i -eq 0 ]]; then
        output="${components[$i]}"
    else
        output="$output | ${components[$i]}"
    fi
done

# Output the status line
echo "$output"