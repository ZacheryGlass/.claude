# Set UTF-8 output encoding for emoji support
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Read JSON from stdin
$jsonInput = $input | Out-String
if (-not $jsonInput) { return }
$data = $jsonInput | ConvertFrom-Json

# Cache settings (Per-session unique cache file)
$cacheFile = "$env:USERPROFILE\.claude\.statusline_cache_$($data.session_id)"
$cacheTTL = 300  # 5 minutes in seconds

function Get-SessionCache {
    if (-not (Test-Path $cacheFile)) { return @{} }
    try {
        $cache = @{}
        Get-Content $cacheFile -Encoding UTF8 | ForEach-Object {
            if ($_ -match '^([^=]+)=(.*)$') {
                $cache[$matches[1]] = $matches[2]
            }
        }
        return $cache
    } catch {
        return @{}
    }
}

function Set-SessionCache {
    param([hashtable]$cache)
    try {
        $tempFile = "$cacheFile.$PID"
        $out = @()
        foreach ($key in $cache.Keys) {
            $out += "$key=$($cache[$key])"
        }
        ($out -join "`n") | Set-Content -Path $tempFile -Encoding UTF8
        Move-Item -Path $tempFile -Destination $cacheFile -Force

        # -----------------------------------------------------------------
        # Garbage Collection: Clean up old session files (older than 2 days),
        # including orphaned temp files (*.PID pattern).
        # Throttled: runs ~1 in 20 writes to avoid a directory scan every tick.
        # -----------------------------------------------------------------
        if ((Get-Random -Maximum 20) -eq 0) {
            Get-ChildItem "$env:USERPROFILE\.claude\.statusline_cache_*" -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-2) } |
                Remove-Item -ErrorAction SilentlyContinue
            Get-ChildItem "$env:USERPROFILE\.claude\.statusline_cache_*.*" -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match '\.\d+$' } |
                Remove-Item -ErrorAction SilentlyContinue
        }
    } catch {}
}

$cache = Get-SessionCache
$cacheUpdated = $false

# Extract values with null coalescing
$modelName = if ($data.model.display_name) { $data.model.display_name } else { "Claude" }
$isHaiku = ($modelName -match "(?i)haiku")

# -----------------------------------------------------------------
# Fast Effort Level Update
# Checks the file modification time instead of parsing JSON every tick
# -----------------------------------------------------------------
$effortLabel = ""
if (-not $isHaiku) {
    $settingsPath = Join-Path $env:USERPROFILE ".claude\settings.json"
    if (Test-Path $settingsPath) {
        # Get file metadata (extremely fast, no disk I/O to read contents)
        $settingsMTime = (Get-Item $settingsPath).LastWriteTimeUtc.Ticks.ToString()
        
        if ($cache['SETTINGS_TIME_V2'] -eq $settingsMTime) {
            # File hasn't changed since we last cached it
            $effortLabel = $cache['EFFORT_LABEL']
        } else {
            # File changed or cache miss! Parse JSON and update cache.
            try {
                $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
                if ($settings.effortLevel) {
                    $effortLabel = " (" + (Get-Culture).TextInfo.ToTitleCase($settings.effortLevel) + ")"
                }
                # Only update cache if the read was successful
                $cache['SETTINGS_TIME_V2'] = $settingsMTime
                $cache['EFFORT_LABEL'] = $effortLabel
                $cacheUpdated = $true
            } catch {
                # File might be locked by Claude writing to it. 
                # Keep the old cached label for this tick and try again next time.
                if ($cache['EFFORT_LABEL']) {
                    $effortLabel = $cache['EFFORT_LABEL']
                }
            }
        }
    }
}

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

$remPct = $data.context_window.remaining_percentage

# -----------------------------------------------------------------
# Detect Context Clear/Compact to expire all timers
# Only reads the transcript when the file has been modified since last check.
# -----------------------------------------------------------------
if ($data.transcript_path -and (Test-Path $data.transcript_path)) {
    $transcriptItem = Get-Item $data.transcript_path -ErrorAction SilentlyContinue
    $transcriptMTime = if ($transcriptItem) { $transcriptItem.LastWriteTimeUtc.Ticks.ToString() } else { $null }
    if ($transcriptMTime -and $cache['TRANSCRIPT_MTIME'] -ne $transcriptMTime) {
        $cache['TRANSCRIPT_MTIME'] = $transcriptMTime
        $cacheUpdated = $true
        $historyLines = Get-Content $data.transcript_path -Tail 5 -ErrorAction SilentlyContinue
        if ($historyLines) {
            foreach ($line in $historyLines) {
                if ($line -match '"display":"/(clear|compact)[^"]*"') {
                    if ($line -match '"timestamp":(\d+)') {
                        $clearTime = $matches[1]
                        $cachedClearTime = if ($cache['LAST_CLEAR_TIME']) { $cache['LAST_CLEAR_TIME'] } else { "0" }
                        if ([long]$clearTime -gt [long]$cachedClearTime) {
                            $keysToClear = @()
                            foreach ($k in $cache.Keys) {
                                if ($k -match '^TIMER_') { $keysToClear += $k }
                            }
                            foreach ($k in $keysToClear) { $cache.Remove($k) }
                            $cache['LAST_CLEAR_TIME'] = $clearTime
                            $cacheUpdated = $true
                        }
                    }
                }
            }
        }
    }
}

# -----------------------------------------------------------------
# Per-Model Cache Timer Logic
# -----------------------------------------------------------------
$apiDuration = if ($data.cost.total_api_duration_ms) { [int64]$data.cost.total_api_duration_ms } else { 0 }
$cachedApiDuration = if ($cache['TOTAL_API_DURATION']) { [int64]$cache['TOTAL_API_DURATION'] } else { 0 }

if ($apiDuration -lt $cachedApiDuration) {
    # API duration decreased (e.g. context was cleared or switched). 
    if ($apiDuration -gt 0) {
        # A new API call also occurred during this reset tick.
        $cache["TIMER_$modelName"] = [datetime]::UtcNow.Ticks.ToString()
    }
    $cache['TOTAL_API_DURATION'] = $apiDuration.ToString()
    $cacheUpdated = $true
} elseif ($apiDuration -gt $cachedApiDuration) {
    # An API call just finished normally! Update the timer for the CURRENT model.
    $cache["TIMER_$modelName"] = [datetime]::UtcNow.Ticks.ToString()
    $cache['TOTAL_API_DURATION'] = $apiDuration.ToString()
    $cacheUpdated = $true
}

$timerStr = ""
$cachedTimerTicks = $cache["TIMER_$modelName"]
$hourglass = [char]0x23F3

if ($cachedTimerTicks) {
    $lastApiTime = [datetime]::new([long]$cachedTimerTicks, 'Utc')
    $ageSeconds = ([datetime]::UtcNow - $lastApiTime).TotalSeconds
    $expiresIn = 3600 - $ageSeconds  # 60 minute countdown
    
    if ($expiresIn -gt 0) {
        $mins = [math]::Floor($expiresIn / 60)
        $secs = [math]::Floor($expiresIn % 60)
        $timerStr = "$hourglass ${mins}m ${secs}s"
    } else {
        $timerStr = "$hourglass Expired"
    }
} else {
    $timerStr = "$hourglass No Cache"
}

$currentDir = $data.workspace.current_dir
$projectDir = $data.workspace.project_dir

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
    $currentTime = [int64](Get-Date -UFormat %s)
    $gitCacheTime = if ($cache['GIT_TIME']) { [int64]$cache['GIT_TIME'] } else { 0 }

    if ($cache['GIT_DIR'] -eq $currentDir -and ($currentTime - $gitCacheTime) -lt $cacheTTL) {
        $gitBranch = $cache['GIT_BRANCH']
        $gitStatus = $cache['GIT_STATUS']
    } else {
        # Cache miss - single git call returns branch, dirty state, and ahead/behind
        $statusLines = git -C $currentDir status --branch --porcelain=v1 2>$null
        if ($statusLines) {
            $header = if ($statusLines -is [array]) { $statusLines[0] } else { $statusLines }
            if ($header -match '^## HEAD') {
                $short = git -C $currentDir rev-parse --short HEAD 2>$null
                if ($short) { $gitBranch = "HEAD@$short" }
            } elseif ($header -match '^## ([^. ]+)') {
                $gitBranch = $matches[1]
            }
            $bodyLines = if ($statusLines -is [array]) { $statusLines.Count - 1 } else { 0 }
            if ($bodyLines -gt 0) { $gitStatus = "*" }
            if ($header -match '\[ahead (\d+)') { $gitStatus += [char]0x2191 + $matches[1] }
            if ($header -match 'behind (\d+)') { $gitStatus += [char]0x2193 + $matches[1] }
        }
        
        $cache['GIT_DIR'] = $currentDir
        $cache['GIT_TIME'] = $currentTime
        $cache['GIT_BRANCH'] = $gitBranch
        $cache['GIT_STATUS'] = $gitStatus
        $cacheUpdated = $true
    }
}

# Save cache to disk only if something changed
if ($cacheUpdated) {
    Set-SessionCache -cache $cache
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
$components += "$robot $modelName$effortLabel"
if ($cacheInfo) { $components += $cacheInfo }
if ($timerStr) { $components += $timerStr }
if ($gitBranch) { $components += "$branch $gitBranch$gitStatus" }
if ($ctxDisplay) { $components += $ctxDisplay }

Write-Output ($components -join " | ")