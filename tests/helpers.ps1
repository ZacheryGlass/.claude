# Test helpers for statusline regression suite.
# Provides Invoke-Statusline which spawns the implementation under test
# with an isolated USERPROFILE so the real ~/.claude is never touched.

$ErrorActionPreference = 'Stop'

function New-StatuslineSandbox {
    # Creates an isolated USERPROFILE directory with .claude/.statusline_cache subtree.
    # Returns the absolute path. Caller is responsible for Remove-StatuslineSandbox.
    $sandbox = Join-Path ([IO.Path]::GetTempPath()) ("statusline-test-" + [guid]::NewGuid().ToString('N'))
    $cacheDir = Join-Path $sandbox '.claude\.statusline_cache'
    New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
    return $sandbox
}

function Remove-StatuslineSandbox {
    param([string]$Sandbox)
    if ($Sandbox -and (Test-Path $Sandbox)) {
        Remove-Item -Recurse -Force -LiteralPath $Sandbox -ErrorAction SilentlyContinue
    }
}

function Set-SandboxSettings {
    param(
        [string]$Sandbox,
        [hashtable]$Settings
    )
    $path = Join-Path $Sandbox '.claude\settings.json'
    $json = $Settings | ConvertTo-Json -Depth 10
    Set-Content -LiteralPath $path -Value $json -Encoding UTF8
    return $path
}

function Set-SandboxCache {
    param(
        [string]$Sandbox,
        [string]$SessionId,
        [hashtable]$Entries
    )
    $cacheDir = Join-Path $Sandbox '.claude\.statusline_cache'
    $file = Join-Path $cacheDir $SessionId
    $lines = $Entries.Keys | ForEach-Object { "$_=$($Entries[$_])" }
    Set-Content -LiteralPath $file -Value ($lines -join "`n") -Encoding UTF8
    return $file
}

function Get-SandboxCache {
    param(
        [string]$Sandbox,
        [string]$SessionId
    )
    $file = Join-Path $Sandbox ".claude\.statusline_cache\$SessionId"
    if (-not (Test-Path -LiteralPath $file)) { return @{} }
    $hash = @{}
    Get-Content -LiteralPath $file -Encoding UTF8 | ForEach-Object {
        if ($_ -match '^([^=]+)=(.*)$') {
            $hash[$matches[1]] = $matches[2]
        }
    }
    return $hash
}

function Invoke-Statusline {
    <#
    .SYNOPSIS
      Runs the statusline implementation under test with isolated env.

    .PARAMETER Executable
      Path to the executable (e.g., "powershell.exe" or ".\statusline.exe").

    .PARAMETER Arguments
      Argument array for the executable.

    .PARAMETER InputData
      Hashtable that will be JSON-serialized and piped to stdin.

    .PARAMETER Sandbox
      Path returned from New-StatuslineSandbox. USERPROFILE is set to this for the child process.

    .OUTPUTS
      Hashtable with: Stdout (string), Stderr (string), ExitCode (int),
      Cache (hashtable from the per-session cache file), DurationMs (double).
    #>
    param(
        [Parameter(Mandatory=$true)][string]$Executable,
        [string[]]$Arguments = @(),
        [Parameter(Mandatory=$true)][hashtable]$InputData,
        [Parameter(Mandatory=$true)][string]$Sandbox
    )

    $json = $InputData | ConvertTo-Json -Depth 10 -Compress

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Executable
    # Use the Arguments string form for broad .NET compatibility (ArgumentList requires .NET Core).
    if ($Arguments.Count -gt 0) {
        $psi.Arguments = ($Arguments | ForEach-Object {
            if ($_ -match '\s' -or $_ -match '"') { '"' + $_.Replace('"','\"') + '"' } else { $_ }
        }) -join ' '
    }
    $psi.RedirectStandardInput  = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute = $false
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding  = [System.Text.Encoding]::UTF8

    # Override USERPROFILE so the script's $cacheDir / settings path point at our sandbox.
    $psi.EnvironmentVariables['USERPROFILE'] = $Sandbox
    # On Windows, PowerShell also reads HOME / HOMEPATH in some scenarios. Pin them too.
    $psi.EnvironmentVariables['HOME'] = $Sandbox

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $proc = [System.Diagnostics.Process]::Start($psi)
    # Write stdin as UTF-8 (no BOM)
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $bytes = $utf8.GetBytes($json)
    $proc.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
    $proc.StandardInput.BaseStream.Flush()
    $proc.StandardInput.Close()

    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    $sw.Stop()

    $cache = Get-SandboxCache -Sandbox $Sandbox -SessionId $InputData.session_id

    return @{
        Stdout     = $stdout
        Stderr     = $stderr
        ExitCode   = $proc.ExitCode
        Cache      = $cache
        DurationMs = $sw.Elapsed.TotalMilliseconds
    }
}

function New-FixtureInput {
    <#
    .SYNOPSIS
      Returns a baseline statusline input hashtable. Override fields as needed.
    #>
    param(
        [string]$SessionId = ([guid]::NewGuid().ToString()),
        [string]$ModelName = 'Opus',
        [int64]$ApiDurationMs = 0,
        [int]$RemainingPct = 91,
        [int]$CacheRead = 0,
        [int]$CacheWrite = 0,
        [string]$CurrentDir = $null,
        [string]$ProjectDir = $null,
        [string]$TranscriptPath = $null
    )
    $h = @{
        session_id = $SessionId
        model = @{ display_name = $ModelName }
        context_window = @{
            remaining_percentage = $RemainingPct
            current_usage = @{
                cache_read_input_tokens     = $CacheRead
                cache_creation_input_tokens = $CacheWrite
            }
        }
        cost = @{ total_api_duration_ms = $ApiDurationMs }
        workspace = @{}
    }
    if ($CurrentDir)     { $h.workspace.current_dir = $CurrentDir }
    if ($ProjectDir)     { $h.workspace.project_dir = $ProjectDir }
    if ($TranscriptPath) { $h.transcript_path = $TranscriptPath }
    return $h
}

function Write-FixtureTranscript {
    <#
    .SYNOPSIS
      Writes a minimal JSONL transcript to the sandbox and returns its path.

    .PARAMETER Lines
      Array of hashtables; each is JSON-encoded as one line.
    #>
    param(
        [string]$Sandbox,
        [string]$Name = 'transcript.jsonl',
        [hashtable[]]$Lines = @()
    )
    $path = Join-Path $Sandbox $Name
    $sb = New-Object System.Text.StringBuilder
    foreach ($l in $Lines) {
        # PS 5.1's ConvertTo-Json escapes <, >, ' as \u003c, \u003e, \u0027.
        # Real Claude Code transcripts do NOT escape these. Undo it so fixtures match prod format.
        $line = ($l | ConvertTo-Json -Depth 10 -Compress) `
            -replace '\\u003c', '<' -replace '\\u003e', '>' -replace '\\u0027', "'"
        [void]$sb.AppendLine($line)
    }
    Set-Content -LiteralPath $path -Value $sb.ToString() -Encoding UTF8 -NoNewline
    return $path
}
