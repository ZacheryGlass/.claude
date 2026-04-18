# Regression tests for statusline.exe (Go binary).
#
# Usage:
#   Invoke-Pester -Script @{ Path = '.\tests\statusline.Tests.ps1' }

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here 'helpers.ps1')

$repo = Split-Path -Parent $here

$script:Exe  = Join-Path $repo 'statusline.exe'
$script:Args = @()
$script:PerfCeilingMs = 200    # Target: <50ms warm, well under 200ms cold

# Convenience wrapper that seeds a fresh sandbox per call unless one is provided.
function RunStatusline {
    param(
        [hashtable]$InputData,
        [string]$Sandbox,
        [switch]$KeepSandbox
    )
    $ownSandbox = $false
    if (-not $Sandbox) {
        $Sandbox = New-StatuslineSandbox
        $ownSandbox = $true
    }
    $r = Invoke-Statusline -Executable $script:Exe -Arguments $script:Args -InputData $InputData -Sandbox $Sandbox
    if ($ownSandbox -and -not $KeepSandbox) {
        Remove-StatuslineSandbox -Sandbox $Sandbox
    }
    $r | Add-Member -NotePropertyName Sandbox -NotePropertyValue $Sandbox -Force
    return $r
}

# ESC (0x1B) â€” `e escape only works in PS 6+; use [char] in PS 5.1.
$script:Esc = [char]27
function StripAnsi { param([string]$s) return ($s -replace "$script:Esc\[[0-9;]*m",'') }

# Emoji literals via code points so the test file is encoding-agnostic.
$script:EmFolder    = [char]::ConvertFromUtf32(0x1F4C1)  # folder
$script:EmRobot     = [char]::ConvertFromUtf32(0x1F916)  # robot
$script:EmHerb      = [char]::ConvertFromUtf32(0x1F33F)  # herb
$script:EmBolt      = [string][char]0x26A1               # bolt
$script:EmHourglass = [string][char]0x23F3               # hourglass

Describe "statusline :: output components" {

    It "emits a non-empty line for a happy-path input" {
        $r = RunStatusline (New-FixtureInput -ModelName 'Opus' -RemainingPct 91 -CacheRead 2000 -CacheWrite 5000)
        $r.ExitCode | Should Be 0
        $r.Stdout.Trim() | Should Not BeNullOrEmpty
    }

    It "includes the model display name" {
        $r = RunStatusline (New-FixtureInput -ModelName 'Sonnet')
        StripAnsi $r.Stdout | Should Match '\bSonnet\b'
    }

    It "falls back to 'Claude' when model.display_name is missing" {
        $input = New-FixtureInput
        $input.model = @{}
        $r = RunStatusline $input
        StripAnsi $r.Stdout | Should Match 'Claude'
    }

    It "does NOT append effort label for Haiku" {
        $r = RunStatusline (New-FixtureInput -ModelName 'Haiku 4.5')
        StripAnsi $r.Stdout | Should Not Match '\(Medium\)|\(High\)|\(Xhigh\)'
    }

    It "appends effort label (TitleCase) for non-Haiku when settings.json has one" {
        $sb = New-StatuslineSandbox
        try {
            Set-SandboxSettings -Sandbox $sb -Settings @{ effortLevel = 'xhigh' } | Out-Null
            $r = RunStatusline -InputData (New-FixtureInput -ModelName 'Opus') -Sandbox $sb -KeepSandbox
            StripAnsi $r.Stdout | Should Match '\(Xhigh\)'
        } finally { Remove-StatuslineSandbox -Sandbox $sb }
    }

    It "omits cache segment when read and write are both zero" {
        $r = RunStatusline (New-FixtureInput -CacheRead 0 -CacheWrite 0)
        $r.Stdout | Should Not Match ([regex]::Escape($script:EmBolt))
    }

    It "shows cache segment with k-suffix when values >= 1000" {
        $r = RunStatusline (New-FixtureInput -CacheRead 12345 -CacheWrite 678)
        StripAnsi $r.Stdout | Should Match ([regex]::Escape($script:EmBolt) + ' 12\.3k/678')
    }

    It "shows 'No Cache' when no timer has been stamped yet" {
        $r = RunStatusline (New-FixtureInput -ApiDurationMs 0)
        StripAnsi $r.Stdout | Should Match ([regex]::Escape($script:EmHourglass) + ' No Cache')
    }

    It "omits ANSI color and remaining% when remaining_percentage is null" {
        $input = New-FixtureInput
        $input.context_window.Remove('remaining_percentage')
        $r = RunStatusline $input
        StripAnsi $r.Stdout | Should Not Match 'Remaining'
    }

    It "uses green color when remaining > 50%" {
        $r = RunStatusline (New-FixtureInput -RemainingPct 75)
        $r.Stdout | Should Match ([regex]::Escape("$script:Esc[32m") + '75% Remaining')
    }

    It "uses yellow color when 20 < remaining <= 50" {
        $r = RunStatusline (New-FixtureInput -RemainingPct 30)
        $r.Stdout | Should Match ([regex]::Escape("$script:Esc[33m") + '30% Remaining')
    }

    It "uses red color when remaining <= 20" {
        $r = RunStatusline (New-FixtureInput -RemainingPct 10)
        $r.Stdout | Should Match ([regex]::Escape("$script:Esc[31m") + '10% Remaining')
    }

    It "project name prefers project_dir leaf over current_dir" {
        $r = RunStatusline (New-FixtureInput -ProjectDir 'C:\work\alpha' -CurrentDir 'C:\work\alpha\src')
        StripAnsi $r.Stdout | Should Match ([regex]::Escape($script:EmFolder) + ' alpha ')
    }

    It "project name falls back to current_dir leaf when project_dir missing" {
        $r = RunStatusline (New-FixtureInput -CurrentDir 'C:\work\beta')
        StripAnsi $r.Stdout | Should Match ([regex]::Escape($script:EmFolder) + ' beta ')
    }

    It "project name is 'no-project' when neither dir is set" {
        $r = RunStatusline (New-FixtureInput)
        StripAnsi $r.Stdout | Should Match ([regex]::Escape($script:EmFolder) + ' no-project ')
    }

    It "omits git segment when not in a git repo" {
        $sb = New-StatuslineSandbox
        try {
            $nonGit = Join-Path $sb 'not-a-repo'
            New-Item -ItemType Directory -Path $nonGit -Force | Out-Null
            $r = RunStatusline -InputData (New-FixtureInput -CurrentDir $nonGit) -Sandbox $sb -KeepSandbox
            $r.Stdout | Should Not Match ([regex]::Escape($script:EmHerb))
        } finally { Remove-StatuslineSandbox -Sandbox $sb }
    }

    It "shows git branch when in a repo" {
        # Use the repo root itself (it's a git repo)
        $r = RunStatusline (New-FixtureInput -CurrentDir $repo)
        StripAnsi $r.Stdout | Should Match ([regex]::Escape($script:EmHerb) + ' ')
    }
}

Describe "statusline :: cache state machine" {

    It "first invocation with api>0 records baseline but does NOT stamp timer" {
        $sb = New-StatuslineSandbox
        try {
            $sid = [guid]::NewGuid().ToString()
            $r = RunStatusline -InputData (New-FixtureInput -SessionId $sid -ApiDurationMs 100) -Sandbox $sb -KeepSandbox
            $r.Cache['TOTAL_API_DURATION'] | Should Be '100'
            $r.Cache.ContainsKey('TIMER_Opus') | Should Be $false
        } finally { Remove-StatuslineSandbox -Sandbox $sb }
    }

    It "second invocation with increased api stamps TIMER_<model>" {
        $sb = New-StatuslineSandbox
        try {
            $sid = [guid]::NewGuid().ToString()
            RunStatusline -InputData (New-FixtureInput -SessionId $sid -ApiDurationMs 100) -Sandbox $sb -KeepSandbox | Out-Null
            $r = RunStatusline -InputData (New-FixtureInput -SessionId $sid -ApiDurationMs 200) -Sandbox $sb -KeepSandbox
            $r.Cache['TOTAL_API_DURATION'] | Should Be '200'
            $r.Cache.ContainsKey('TIMER_Opus') | Should Be $true
            [long]$r.Cache['TIMER_Opus'] | Should BeGreaterThan 0
        } finally { Remove-StatuslineSandbox -Sandbox $sb }
    }

    It "invocation with equal api does NOT re-stamp timer" {
        $sb = New-StatuslineSandbox
        try {
            $sid = [guid]::NewGuid().ToString()
            RunStatusline -InputData (New-FixtureInput -SessionId $sid -ApiDurationMs 100) -Sandbox $sb -KeepSandbox | Out-Null
            RunStatusline -InputData (New-FixtureInput -SessionId $sid -ApiDurationMs 200) -Sandbox $sb -KeepSandbox | Out-Null
            $cacheBefore = Get-SandboxCache -Sandbox $sb -SessionId $sid
            $r = RunStatusline -InputData (New-FixtureInput -SessionId $sid -ApiDurationMs 200) -Sandbox $sb -KeepSandbox
            $r.Cache['TIMER_Opus'] | Should Be $cacheBefore['TIMER_Opus']
        } finally { Remove-StatuslineSandbox -Sandbox $sb }
    }

    It "api decrease resets baseline and only stamps if new api > 0" {
        $sb = New-StatuslineSandbox
        try {
            $sid = [guid]::NewGuid().ToString()
            RunStatusline -InputData (New-FixtureInput -SessionId $sid -ApiDurationMs 500) -Sandbox $sb -KeepSandbox | Out-Null
            RunStatusline -InputData (New-FixtureInput -SessionId $sid -ApiDurationMs 600) -Sandbox $sb -KeepSandbox | Out-Null
            $stampBefore = (Get-SandboxCache -Sandbox $sb -SessionId $sid)['TIMER_Opus']
            Start-Sleep -Milliseconds 50
            # Now simulate reset: api drops but is still >0
            $r = RunStatusline -InputData (New-FixtureInput -SessionId $sid -ApiDurationMs 10) -Sandbox $sb -KeepSandbox
            $r.Cache['TOTAL_API_DURATION'] | Should Be '10'
            $r.Cache['TIMER_Opus'] | Should Not Be $stampBefore
        } finally { Remove-StatuslineSandbox -Sandbox $sb }
    }

    It "per-model timers are independent" {
        $sb = New-StatuslineSandbox
        try {
            $sid = [guid]::NewGuid().ToString()
            RunStatusline -InputData (New-FixtureInput -SessionId $sid -ModelName 'Opus' -ApiDurationMs 100) -Sandbox $sb -KeepSandbox | Out-Null
            RunStatusline -InputData (New-FixtureInput -SessionId $sid -ModelName 'Opus' -ApiDurationMs 200) -Sandbox $sb -KeepSandbox | Out-Null
            RunStatusline -InputData (New-FixtureInput -SessionId $sid -ModelName 'Sonnet' -ApiDurationMs 300) -Sandbox $sb -KeepSandbox | Out-Null
            $r = RunStatusline -InputData (New-FixtureInput -SessionId $sid -ModelName 'Sonnet' -ApiDurationMs 400) -Sandbox $sb -KeepSandbox
            $r.Cache.ContainsKey('TIMER_Opus')   | Should Be $true
            $r.Cache.ContainsKey('TIMER_Sonnet') | Should Be $true
            $r.Cache['TIMER_Opus'] | Should Not Be $r.Cache['TIMER_Sonnet']
        } finally { Remove-StatuslineSandbox -Sandbox $sb }
    }

    It "unicode git status chars survive cache round-trip" {
        $sb = New-StatuslineSandbox
        try {
            $sid = [guid]::NewGuid().ToString()
            Set-SandboxCache -Sandbox $sb -SessionId $sid -Entries @{
                GIT_DIR    = $repo
                GIT_TIME   = [string]([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
                GIT_BRANCH = 'wip'
                GIT_STATUS = [string]([char]0x2191 + '3' + [char]0x2193 + '1')
            } | Out-Null
            $r = RunStatusline -InputData (New-FixtureInput -SessionId $sid -CurrentDir $repo) -Sandbox $sb -KeepSandbox
            StripAnsi $r.Stdout | Should Match ([char]0x2191 + '3' + [char]0x2193 + '1')
        } finally { Remove-StatuslineSandbox -Sandbox $sb }
    }

    It "effort label is served from cache when settings mtime unchanged" {
        $sb = New-StatuslineSandbox
        try {
            $sid = [guid]::NewGuid().ToString()
            $settingsPath = Set-SandboxSettings -Sandbox $sb -Settings @{ effortLevel = 'high' }
            $mtime = ([DateTimeOffset](Get-Item $settingsPath).LastWriteTimeUtc).ToUnixTimeMilliseconds().ToString()
            Set-SandboxCache -Sandbox $sb -SessionId $sid -Entries @{
                SETTINGS_TIME_V2 = $mtime
                EFFORT_LABEL     = ' (Cached)'
            } | Out-Null
            $r = RunStatusline -InputData (New-FixtureInput -SessionId $sid) -Sandbox $sb -KeepSandbox
            # Should use cached label (Cached), not re-parse settings (High)
            StripAnsi $r.Stdout | Should Match '\(Cached\)'
            StripAnsi $r.Stdout | Should Not Match '\(High\)'
        } finally { Remove-StatuslineSandbox -Sandbox $sb }
    }

    It "effort label is re-parsed when settings mtime has changed" {
        $sb = New-StatuslineSandbox
        try {
            $sid = [guid]::NewGuid().ToString()
            Set-SandboxSettings -Sandbox $sb -Settings @{ effortLevel = 'medium' } | Out-Null
            Set-SandboxCache -Sandbox $sb -SessionId $sid -Entries @{
                SETTINGS_TIME_V2 = '0'   # guaranteed stale
                EFFORT_LABEL     = ' (Stale)'
            } | Out-Null
            $r = RunStatusline -InputData (New-FixtureInput -SessionId $sid) -Sandbox $sb -KeepSandbox
            StripAnsi $r.Stdout | Should Match '\(Medium\)'
            StripAnsi $r.Stdout | Should Not Match '\(Stale\)'
        } finally { Remove-StatuslineSandbox -Sandbox $sb }
    }
}

Describe "statusline :: /clear and /compact detection" {

    # Real transcript format: <command-name>/clear</command-name> in message.content,
    # with ISO 8601 "timestamp" at the top level. See plan: this is the FIXED behavior.

    It "no /clear in transcript -> TIMER_* keys preserved" {
        $sb = New-StatuslineSandbox
        try {
            $sid = [guid]::NewGuid().ToString()
            $tpath = Write-FixtureTranscript -Sandbox $sb -Name 'no-clear.jsonl' -Lines @(
                @{ type = 'user'; message = @{ role='user'; content='hello' }; timestamp = '2026-04-17T10:00:00.000Z' }
                @{ type = 'assistant'; message = @{ role='assistant'; content='hi' }; timestamp = '2026-04-17T10:00:01.000Z' }
            )
            Set-SandboxCache -Sandbox $sb -SessionId $sid -Entries @{
                TIMER_Opus        = [string]([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())
                TOTAL_API_DURATION = '500'
            } | Out-Null
            $r = RunStatusline -InputData (New-FixtureInput -SessionId $sid -ApiDurationMs 500 -TranscriptPath $tpath) -Sandbox $sb -KeepSandbox
            $r.Cache.ContainsKey('TIMER_Opus') | Should Be $true
        } finally { Remove-StatuslineSandbox -Sandbox $sb }
    }

    It "/clear in transcript (new command-name format) removes all TIMER_* keys" {
        $sb = New-StatuslineSandbox
        try {
            $sid = [guid]::NewGuid().ToString()
            $tpath = Write-FixtureTranscript -Sandbox $sb -Name 'with-clear.jsonl' -Lines @(
                @{ type='assistant'; message=@{ role='assistant'; content='ok' }; timestamp='2026-04-17T09:59:00.000Z' }
                @{ type='user'; message=@{ role='user'; content='<command-name>/clear</command-name>' }; timestamp='2026-04-17T10:00:00.000Z' }
            )
            Set-SandboxCache -Sandbox $sb -SessionId $sid -Entries @{
                TIMER_Opus         = [string]([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())
                TIMER_Sonnet       = [string]([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())
                TOTAL_API_DURATION = '500'
            } | Out-Null
            $r = RunStatusline -InputData (New-FixtureInput -SessionId $sid -ApiDurationMs 500 -TranscriptPath $tpath) -Sandbox $sb -KeepSandbox
            $r.Cache.ContainsKey('TIMER_Opus')   | Should Be $false
            $r.Cache.ContainsKey('TIMER_Sonnet') | Should Be $false
            $r.Cache.ContainsKey('LAST_CLEAR_TIME') | Should Be $true
        } finally { Remove-StatuslineSandbox -Sandbox $sb }
    }

    It "/compact in transcript (new format) removes all TIMER_* keys" {
        $sb = New-StatuslineSandbox
        try {
            $sid = [guid]::NewGuid().ToString()
            $tpath = Write-FixtureTranscript -Sandbox $sb -Name 'with-compact.jsonl' -Lines @(
                @{ type='user'; message=@{ role='user'; content='<command-name>/compact</command-name>' }; timestamp='2026-04-17T10:00:00.000Z' }
            )
            Set-SandboxCache -Sandbox $sb -SessionId $sid -Entries @{
                TIMER_Opus         = [string]([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())
                TOTAL_API_DURATION = '500'
            } | Out-Null
            $r = RunStatusline -InputData (New-FixtureInput -SessionId $sid -ApiDurationMs 500 -TranscriptPath $tpath) -Sandbox $sb -KeepSandbox
            $r.Cache.ContainsKey('TIMER_Opus') | Should Be $false
        } finally { Remove-StatuslineSandbox -Sandbox $sb }
    }

    It "same /clear line does not double-clear on second invocation" {
        $sb = New-StatuslineSandbox
        try {
            $sid = [guid]::NewGuid().ToString()
            $tpath = Write-FixtureTranscript -Sandbox $sb -Name 'clear.jsonl' -Lines @(
                @{ type='user'; message=@{ role='user'; content='<command-name>/clear</command-name>' }; timestamp='2026-04-17T10:00:00.000Z' }
            )
            Set-SandboxCache -Sandbox $sb -SessionId $sid -Entries @{
                TIMER_Opus         = [string]([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())
                TOTAL_API_DURATION = '500'
            } | Out-Null
            RunStatusline -InputData (New-FixtureInput -SessionId $sid -ApiDurationMs 500 -TranscriptPath $tpath) -Sandbox $sb -KeepSandbox | Out-Null
            # Stamp a NEW timer AFTER the clear â€” simulate a fresh API call.
            $cache = Get-SandboxCache -Sandbox $sb -SessionId $sid
            $cache['TIMER_Opus'] = [string]([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())
            Set-SandboxCache -Sandbox $sb -SessionId $sid -Entries $cache | Out-Null
            # Re-invoke â€” the same clear line should NOT wipe the fresh timer.
            $r = RunStatusline -InputData (New-FixtureInput -SessionId $sid -ApiDurationMs 500 -TranscriptPath $tpath) -Sandbox $sb -KeepSandbox
            $r.Cache.ContainsKey('TIMER_Opus') | Should Be $true
        } finally { Remove-StatuslineSandbox -Sandbox $sb }
    }

    It "missing transcript_path does not crash" {
        $input = New-FixtureInput
        $input.transcript_path = 'C:\nope\does\not\exist.jsonl'
        $r = RunStatusline $input
        $r.ExitCode | Should Be 0
    }
}

Describe "statusline :: input edge cases" {

    It "empty stdin -> exit 0, no output" {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $script:Exe
        if ($script:Args.Count -gt 0) {
            $psi.Arguments = ($script:Args | ForEach-Object {
                if ($_ -match '\s') { '"' + $_.Replace('"','\"') + '"' } else { $_ }
            }) -join ' '
        }
        $psi.RedirectStandardInput = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $p = [System.Diagnostics.Process]::Start($psi)
        $p.StandardInput.Close()
        $out = $p.StandardOutput.ReadToEnd()
        $p.WaitForExit()
        $p.ExitCode | Should Be 0
        $out.Trim() | Should BeNullOrEmpty
    }

    It "missing current_usage does not crash" {
        $input = New-FixtureInput
        $input.context_window.Remove('current_usage')
        $r = RunStatusline $input
        $r.ExitCode | Should Be 0
    }

    It "long current_dir path does not crash" {
        $longPath = 'C:\' + ('a' * 300)
        $r = RunStatusline (New-FixtureInput -CurrentDir $longPath)
        $r.ExitCode | Should Be 0
    }

    It "model display_name with spaces and parens survives cache key round-trip" {
        $sb = New-StatuslineSandbox
        try {
            $sid = [guid]::NewGuid().ToString()
            RunStatusline -InputData (New-FixtureInput -SessionId $sid -ModelName 'Opus 4.7 (1M context)' -ApiDurationMs 100) -Sandbox $sb -KeepSandbox | Out-Null
            $r = RunStatusline -InputData (New-FixtureInput -SessionId $sid -ModelName 'Opus 4.7 (1M context)' -ApiDurationMs 200) -Sandbox $sb -KeepSandbox
            $r.Cache.ContainsKey('TIMER_Opus 4.7 (1M context)') | Should Be $true
        } finally { Remove-StatuslineSandbox -Sandbox $sb }
    }
}

Describe "statusline :: performance" {

    It "single invocation completes within perf ceiling ($($script:PerfCeilingMs)ms)" {
        $sb = New-StatuslineSandbox
        try {
            $sid = [guid]::NewGuid().ToString()
            # Warm the cache first
            RunStatusline -InputData (New-FixtureInput -SessionId $sid -ApiDurationMs 100) -Sandbox $sb -KeepSandbox | Out-Null
            $r = RunStatusline -InputData (New-FixtureInput -SessionId $sid -ApiDurationMs 100) -Sandbox $sb -KeepSandbox
            Write-Host ("  [perf] warm duration: " + [math]::Round($r.DurationMs) + "ms")
            $r.DurationMs | Should BeLessThan $script:PerfCeilingMs
        } finally { Remove-StatuslineSandbox -Sandbox $sb }
    }

    It "no-op re-invocation does not rewrite the cache file" {
        $sb = New-StatuslineSandbox
        try {
            $sid = [guid]::NewGuid().ToString()
            RunStatusline -InputData (New-FixtureInput -SessionId $sid -ApiDurationMs 100) -Sandbox $sb -KeepSandbox | Out-Null
            $cachePath = Join-Path $sb ".claude\.statusline_cache\$sid"
            $mtimeBefore = (Get-Item $cachePath).LastWriteTimeUtc.Ticks
            Start-Sleep -Milliseconds 50
            RunStatusline -InputData (New-FixtureInput -SessionId $sid -ApiDurationMs 100) -Sandbox $sb -KeepSandbox | Out-Null
            $mtimeAfter = (Get-Item $cachePath).LastWriteTimeUtc.Ticks
            $mtimeAfter | Should Be $mtimeBefore
        } finally { Remove-StatuslineSandbox -Sandbox $sb }
    }
}

