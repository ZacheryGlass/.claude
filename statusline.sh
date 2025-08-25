#!/bin/bash

# Read Claude Code context from stdin
input=$(cat)

# Path to jq executable
JQ="$HOME/.claude/bin/jq.exe"

# Check if jq exists, fallback to system jq or basic parsing
if [[ -f "$JQ" ]]; then
    # Use local jq
    jq_cmd="$JQ"
elif command -v jq >/dev/null 2>&1; then
    # Use system jq
    jq_cmd="jq"
else
    # Fallback to basic parsing
    jq_cmd=""
fi

# Function to extract JSON values
extract_value() {
    local path="$1"
    if [[ -n "$jq_cmd" ]]; then
        echo "$input" | "$jq_cmd" -r "$path // empty" 2>/dev/null
    else
        # Basic fallback parsing
        local key="${path##*.}"
        echo "$input" | grep -o "\"$key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | sed 's/.*"[^"]*"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' | head -1
    fi
}

extract_number() {
    local path="$1"
    if [[ -n "$jq_cmd" ]]; then
        echo "$input" | "$jq_cmd" -r "$path // empty" 2>/dev/null
    else
        # Basic fallback for numbers
        local key="${path##*.}"
        echo "$input" | grep -o "\"$key\"[[:space:]]*:[[:space:]]*[0-9.]*" | sed 's/.*"[^"]*"[[:space:]]*:[[:space:]]*\([0-9.]*\).*/\1/' | head -1
    fi
}

# Extract information from JSON
model_name=$(extract_value ".model.display_name")
model_id=$(extract_value ".model.id")
current_dir=$(extract_value ".workspace.current_dir")
project_dir=$(extract_value ".workspace.project_dir")
transcript_path=$(extract_value ".transcript_path")

# Calculate context percentage from transcript
context_percent=""
if [[ -n "$transcript_path" ]] && [[ -f "$transcript_path" ]] && [[ -n "$jq_cmd" ]]; then
    # Get the latest cumulative token usage from the most recent assistant message
    # Each assistant message has a usage field with the CUMULATIVE total tokens at that point
    total_tokens=$(cat "$transcript_path" | \
        "$jq_cmd" -s '[.[] | select(.message.role == "assistant") | .message.usage | 
            ((.input_tokens // 0) + 
             (.cache_creation_input_tokens // 0) + 
             (.cache_read_input_tokens // 0) + 
             (.output_tokens // 0))] | last // 0' 2>/dev/null)
    
    # All Claude models have 200k context limit
    model_limit=200000
    
    # Calculate percentage if we have token data
    if [[ -n "$total_tokens" ]] && [[ "$total_tokens" != "0" ]] && [[ "$total_tokens" != "null" ]]; then
        context_percent=$((total_tokens * 100 / model_limit))
        # Cap at 100%
        if [[ "$context_percent" -gt 100 ]]; then
            context_percent=100
        fi
    fi
fi

# Try alternative context calculation methods if transcript didn't work
if [[ -z "$context_percent" ]]; then
    # Try direct percentage field
    context_percent=$(extract_number ".context.percentage")
    # If not found, try calculating from used/total
    if [[ -z "$context_percent" ]]; then
        context_used=$(extract_number ".context.used")
        context_total=$(extract_number ".context.total")
        if [[ -n "$context_used" ]] && [[ -n "$context_total" ]] && [[ "$context_total" != "0" ]]; then
            context_percent=$((context_used * 100 / context_total))
        fi
    fi
fi

# Default model name if not found
if [[ -z "$model_name" ]]; then
    model_name="Claude"
fi

# Get project/directory name
if [[ -n "$project_dir" ]]; then
    # Convert Windows path to Unix-style for Git Bash
    project_dir=$(echo "$project_dir" | sed 's|\\|/|g')
    project_name=$(basename "$project_dir")
elif [[ -n "$current_dir" ]]; then
    current_dir=$(echo "$current_dir" | sed 's|\\|/|g')
    project_name=$(basename "$current_dir")
else
    project_name="no-project"
fi

# Get git branch info
git_branch=""
git_status=""
if [[ -n "$current_dir" ]]; then
    # Check if we're in a git repository
    if [[ -d "$current_dir/.git" ]] || git -C "$current_dir" rev-parse --git-dir >/dev/null 2>&1; then
        branch=$(git -C "$current_dir" branch --show-current 2>/dev/null)
        if [[ -n "$branch" ]]; then
            git_branch="$branch"
            
            # Check for uncommitted changes
            if [[ -n $(git -C "$current_dir" status --porcelain 2>/dev/null) ]]; then
                git_status="*"
            fi
            
            # Check if ahead/behind remote
            if git -C "$current_dir" rev-parse --abbrev-ref @{u} >/dev/null 2>&1; then
                ahead=$(git -C "$current_dir" rev-list --count @{u}..HEAD 2>/dev/null)
                behind=$(git -C "$current_dir" rev-list --count HEAD..@{u} 2>/dev/null)
                
                if [[ "$ahead" -gt 0 ]]; then
                    git_status="${git_status}↑${ahead}"
                fi
                if [[ "$behind" -gt 0 ]]; then
                    git_status="${git_status}↓${behind}"
                fi
            fi
        fi
    fi
fi

# Build status line components with emojis
components=()

# Add project folder
components+=("📁 ${project_name}")

# Add model
components+=("🤖 ${model_name}")

# Add context percentage if available with indicators
if [[ -n "$context_percent" ]] && [[ -n "$total_tokens" ]]; then
    # Format tokens in k format
    if [[ "$total_tokens" -ge 1000 ]]; then
        formatted_tokens=$((total_tokens / 1000))k
    else
        formatted_tokens=$total_tokens
    fi
    
    # Add emoji indicator based on percentage
    if [[ "$context_percent" -lt 50 ]]; then
        # Green zone - safe
        components+=("📈 ${formatted_tokens}/200k (${context_percent}%)")
    elif [[ "$context_percent" -lt 80 ]]; then
        # Yellow zone - caution
        components+=("⚠️ ${formatted_tokens}/200k (${context_percent}%)")
    else
        # Red zone - danger (nearing auto-compact at 80%)
        components+=("🔴 ${formatted_tokens}/200k (${context_percent}%)")
    fi
elif [[ -n "$context_percent" ]]; then
    # Fallback if we only have percentage
    if [[ "$context_percent" -lt 50 ]]; then
        components+=("📈 ${context_percent}%")
    elif [[ "$context_percent" -lt 80 ]]; then
        components+=("⚠️ ${context_percent}%")
    else
        components+=("🔴 ${context_percent}%")
    fi
fi

# Add git branch if available
if [[ -n "$git_branch" ]]; then
    components+=("🌿 ${git_branch}${git_status}")
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