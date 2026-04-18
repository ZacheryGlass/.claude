# Microbench for statusline.exe across warm/cold cache states.
. $PSScriptRoot\helpers.ps1

$repo = Split-Path -Parent $PSScriptRoot
$exe = Join-Path $repo 'statusline.exe'

function Bench {
    param([string]$Label, [int]$N, [scriptblock]$Setup)
    $durations = @()
    for ($i = 0; $i -lt $N; $i++) {
        $ctx = & $Setup
        $r = Invoke-Statusline -Executable $exe -Arguments @() -InputData $ctx.Input -Sandbox $ctx.Sandbox
        $durations += $r.DurationMs
        Remove-StatuslineSandbox -Sandbox $ctx.Sandbox
    }
    $sorted = $durations | Sort-Object
    $min = $sorted[0]; $max = $sorted[-1]
    $med = $sorted[[int]($sorted.Count / 2)]
    $avg = [math]::Round(($durations | Measure-Object -Average).Average, 1)
    Write-Host ("{0,-32} n={1}  min={2}ms  med={3}ms  avg={4}ms  max={5}ms" -f $Label, $N, $min, $med, $avg, $max)
}

# Scenario 1: fully warm (all cached, no git call, no transcript scan)
Bench '1) fully warm cache' 20 {
    $sb = New-StatuslineSandbox
    $sid = [guid]::NewGuid().ToString()
    Set-SandboxSettings -Sandbox $sb -Settings @{ effortLevel = 'high' } | Out-Null
    $settingsFile = Join-Path $sb '.claude\settings.json'
    $settingsMTime = ([DateTimeOffset](Get-Item $settingsFile).LastWriteTimeUtc).ToUnixTimeMilliseconds().ToString()
    Set-SandboxCache -Sandbox $sb -SessionId $sid -Entries @{
        SETTINGS_TIME_V2 = $settingsMTime
        EFFORT_LABEL     = ' (High)'
        GIT_DIR          = $repo
        GIT_TIME         = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds().ToString()
        GIT_BRANCH       = 'wip'
        GIT_STATUS       = ''
        TIMER_Opus       = [DateTimeOffset]::UtcNow.AddMinutes(-10).ToUnixTimeMilliseconds().ToString()
        TOTAL_API_DURATION = '5000'
    } | Out-Null
    $inp = New-FixtureInput -SessionId $sid -CurrentDir $repo -Model 'Opus' -InputTokens 1000 -OutputTokens 500 -Remaining 91 -ApiDurationMS 5000
    @{ Sandbox = $sb; Input = $inp }
}

# Scenario 2: git cache miss (forces git exec)
Bench '2) git cache miss' 20 {
    $sb = New-StatuslineSandbox
    $sid = [guid]::NewGuid().ToString()
    Set-SandboxSettings -Sandbox $sb -Settings @{ effortLevel = 'high' } | Out-Null
    $inp = New-FixtureInput -SessionId $sid -CurrentDir $repo -Model 'Opus' -InputTokens 1000 -OutputTokens 500 -Remaining 91 -ApiDurationMS 5000
    @{ Sandbox = $sb; Input = $inp }
}

# Scenario 3: no git repo
Bench '3) no git repo' 20 {
    $sb = New-StatuslineSandbox
    $sid = [guid]::NewGuid().ToString()
    Set-SandboxSettings -Sandbox $sb -Settings @{ effortLevel = 'high' } | Out-Null
    $inp = New-FixtureInput -SessionId $sid -CurrentDir $sb -Model 'Opus' -Remaining 50
    @{ Sandbox = $sb; Input = $inp }
}

# Scenario 4: cold (no cache at all, not in repo - pure binary startup)
Bench '4) cold no-op (no repo)' 20 {
    $sb = New-StatuslineSandbox
    $inp = New-FixtureInput -SessionId ([guid]::NewGuid()) -CurrentDir $sb -Model 'Opus'
    @{ Sandbox = $sb; Input = $inp }
}
