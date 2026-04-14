# Set UTF-8 output encoding for emoji support
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Read JSON from stdin
$jsonInput = $input | Out-String
if (-not $jsonInput) { return }
$data = $jsonInput | ConvertFrom-Json

# Cache settings
$cacheFile = "$env:USERPROFILE\.claude\.statusline_cache"
$cacheTTL = 300  # 5 minutes in seconds

# Cache functions
function Read-GitCache {
    param([string]$dir)
    if (-not (Test-Path $cacheFile)) { return $null }

    try {
        $cache = @{}
        Get-Content $cacheFile | ForEach-Object {
            if ($_ -match '^([^=]+)=(.*)$') {
                $cache[$matches[1]] = $matches[2]
            }
        }

        if ($cache['DIR'] -ne $dir) { return $null }

        $cacheTime = [int64]$cache['TIME']
        $currentTime = [int64](Get-Date -UFormat %s)
        $age = $currentTime - $cacheTime

        if ($age -gt $cacheTTL) { return $null }

        return @{
            Branch = $cache['BRANCH']
            Status = $cache['STATUS']
        }
    } catch {
        return $null
    }
}

function Write-GitCache {
    param([string]$dir, [string]$branch, [string]$status)
    $currentTime = [int64](Get-Date -UFormat %s)
    $tempFile = "$cacheFile.$$"
    @"
DIR=$dir
TIME=$currentTime
BRANCH=$branch
STATUS=$status
"@ | Set-Content -Path $tempFile -NoNewline
    Move-Item -Path $tempFile -Destination $cacheFile -Force
}

# Extract values with null coalescing
$modelName = if ($data.model.display_name) { $data.model.display_name } else { "Claude" }
$effortLabel = if ($data.model.effort) { "Effort: " + (Get-Culture).TextInfo.ToTitleCase($data.model.effort) } else { "" }

# Cache info
$usage = $data.context_window.current_usage
$cacheInfo = ""
if ($usage) {
    $read = $usage.cache_read_input_tokens
    $write = $usage.cache_creation_input_tokens
    if ($read -gt 0 -or $write -gt 0) {
        $rf = if ($read -ge 1000) { "$([math]::Round($read / 1000, 1))k" } else { "$read" }
        $wf = if ($write -ge 1000) { "$([math]::Round($write / 1000, 1))k" } else { "$write" }
        $bolt = [char]0x26A1
        $cacheInfo = "$bolt $rf/$wf"
    }
}

# Cache Timer Logic
$timerStr = ""
if ($data.transcript_path -and (Test-Path $data.transcript_path)) {
    $lastUpdate = (Get-Item $data.transcript_path).LastWriteTimeUtc
    $currentTime = [datetime]::UtcNow
    $ageSeconds = ($currentTime - $lastUpdate).TotalSeconds
    $expiresIn = 3600 - $ageSeconds
    
    $hourglass = [char]0x23F3
    if ($expiresIn -gt 0) {
        $mins = [math]::Floor($expiresIn / 60)
        $secs = [math]::Floor($expiresIn % 60)
        $timerStr = "$hourglass ${mins}m ${secs}s"
    } else {
        $timerStr = "$hourglass Expired"
    }
}

$currentDir = $data.workspace.current_dir
$projectDir = $data.workspace.project_dir
$remPct = $data.context_window.remaining_percentage

# Get project name from path
$projectName = if ($projectDir) {
    Split-Path $projectDir -Leaf
} elseif ($currentDir) {
    Split-Path $currentDir -Leaf
} else {
    "no-project"
}

# Git info (if in a git repo)
$gitBranch = ""
$gitStatus = ""
if ($currentDir -and (Test-Path (Join-Path $currentDir ".git"))) {
    # Try cache first
    $cached = Read-GitCache -dir $currentDir
    if ($cached) {
        $gitBranch = $cached.Branch
        $gitStatus = $cached.Status
    } else {
        # Cache miss - run git commands
        $gitBranch = git -C $currentDir branch --show-current 2>$null
        if (-not $gitBranch) {
            $short = git -C $currentDir rev-parse --short HEAD 2>$null
            if ($short) { $gitBranch = "HEAD@$short" }
        }
        if ($gitBranch) {
            $porcelain = git -C $currentDir status --porcelain 2>$null
            if ($porcelain) { $gitStatus = "*" }

            # Check ahead/behind
            $upstream = git -C $currentDir rev-parse --abbrev-ref '@{u}' 2>$null
            if ($upstream) {
                $ahead = git -C $currentDir rev-list --count '@{u}..HEAD' 2>$null
                $behind = git -C $currentDir rev-list --count 'HEAD..@{u}' 2>$null
                if ($ahead -gt 0) { $gitStatus += [char]0x2191 + $ahead }
                if ($behind -gt 0) { $gitStatus += [char]0x2193 + $behind }
            }

            # Write to cache
            Write-GitCache -dir $currentDir -branch $gitBranch -status $gitStatus
        }
    }
}

# Context percentage with ANSI color
$ESC = [char]27
$ctxDisplay = ""
if ($null -ne $remPct) {
    $pct = [math]::Max([math]::Round($remPct), 0)
    $color = if ($pct -gt 50) { "32" } elseif ($pct -gt 20) { "33" } else { "31" }
    $ctxDisplay = "$ESC[${color}m$pct% Remaining$ESC[0m"
}

# Build output with emojis (use ConvertFromUtf32 for chars above U+FFFF)
$folder = [char]::ConvertFromUtf32(0x1F4C1)  # folder emoji
$robot = [char]::ConvertFromUtf32(0x1F916)   # robot emoji
$branch = [char]::ConvertFromUtf32(0x1F33F)  # herb/branch emoji

$components = @()
$components += "$folder $projectName"
$components += "$robot $modelName"
if ($effortLabel) { $components += $effortLabel }
if ($cacheInfo) { $components += $cacheInfo }
if ($timerStr) { $components += $timerStr }
if ($gitBranch) { $components += "$branch $gitBranch$gitStatus" }
if ($ctxDisplay) { $components += $ctxDisplay }

Write-Output ($components -join " | ")
