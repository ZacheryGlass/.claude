#!/bin/bash

# Read Claude Code context from stdin
input=$(cat)

# Path to jq executable
JQ="$HOME/.claude/bin/jq.exe"

# Cache settings
CACHE_FILE="$HOME/.claude/.statusline_cache"
CACHE_TTL=300  # 5 minutes in seconds

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

# Cache functions
read_cache() {
    local dir="$1"
    if [[ ! -f "$CACHE_FILE" ]]; then
        return 1
    fi

    # Read cache and check if it matches current directory
    local cache_content=$(cat "$CACHE_FILE" 2>/dev/null)
    local cache_dir=$(echo "$cache_content" | grep "^DIR=" | cut -d'=' -f2-)
    local cache_time=$(echo "$cache_content" | grep "^TIME=" | cut -d'=' -f2)

    if [[ "$cache_dir" != "$dir" ]]; then
        return 1
    fi

    # Check if cache is still valid
    local current_time=$(date +%s)
    local age=$((current_time - cache_time))

    if [[ $age -gt $CACHE_TTL ]]; then
        return 1
    fi

    # Return cached values
    echo "$cache_content"
    return 0
}

write_cache() {
    local dir="$1"
    local branch="$2"
    local status="$3"
    local current_time=$(date +%s)

    cat > "$CACHE_FILE" <<EOF
DIR=$dir
TIME=$current_time
BRANCH=$branch
STATUS=$status
EOF
}

# Extract information from JSON
model_name=$(extract_value ".model.display_name")
model_id=$(extract_value ".model.id")
current_dir=$(extract_value ".workspace.current_dir")
project_dir=$(extract_value ".workspace.project_dir")
transcript_path=$(extract_value ".transcript_path")


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

# Get git branch info with caching
git_branch=""
git_status=""
if [[ -n "$current_dir" ]]; then
    # Try to read from cache first
    cache_data=$(read_cache "$current_dir")
    if [[ $? -eq 0 ]]; then
        # Use cached data
        git_branch=$(echo "$cache_data" | grep "^BRANCH=" | cut -d'=' -f2-)
        git_status=$(echo "$cache_data" | grep "^STATUS=" | cut -d'=' -f2-)
    else
        # Cache miss or stale - run git commands
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

                # Write to cache
                write_cache "$current_dir" "$git_branch" "$git_status"
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