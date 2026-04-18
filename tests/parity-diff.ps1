# Side-by-side parity diff across varied fixture inputs.
# Runs each fixture through both impls and compares stdout + cache.

. $PSScriptRoot\helpers.ps1

$repo = Split-Path -Parent $PSScriptRoot
$psExe = 'powershell'
$psArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $repo 'statusline.ps1'))
$goExe = Join-Path $repo 'statusline.exe'
$goArgs = @()

function Run-Both {
    param([hashtable]$Fixture)
    $results = @{}
    foreach ($impl in @('ps','go')) {
        $sb = New-StatuslineSandbox
        try {
            if ($Fixture.Settings) { Set-SandboxSettings -Sandbox $sb -Settings $Fixture.Settings | Out-Null }
            if ($Fixture.CacheSeed) { Set-SandboxCache -Sandbox $sb -SessionId $Fixture.Input.session_id -Entries $Fixture.CacheSeed | Out-Null }
            if ($impl -eq 'ps') { $exe = $psExe; $argv = $psArgs } else { $exe = $goExe; $argv = $goArgs }
            $r = Invoke-Statusline -Executable $exe -Arguments $argv -InputData $Fixture.Input -Sandbox $sb
            $results[$impl] = @{ Stdout = $r.Stdout; Cache = $r.Cache }
        } finally {
            Remove-StatuslineSandbox -Sandbox $sb
        }
    }
    return $results
}

$fixtures = @(
    @{ Name = 'happy-path-opus';
       Input = (New-FixtureInput -SessionId ([guid]::NewGuid()) -CurrentDir $repo -Model 'Opus' -InputTokens 1000 -OutputTokens 1000 -Remaining 91 -ApiDurationMS 5000);
       Settings = @{ effortLevel = 'high' } },
    @{ Name = 'haiku-no-effort';
       Input = (New-FixtureInput -SessionId ([guid]::NewGuid()) -CurrentDir $repo -Model 'Haiku' -InputTokens 200 -OutputTokens 300 -Remaining 50 -ApiDurationMS 1000);
       Settings = @{ effortLevel = 'high' } },
    @{ Name = 'no-usage';
       Input = (New-FixtureInput -SessionId ([guid]::NewGuid()) -CurrentDir $repo -Model 'Opus' -Remaining 80);
       Settings = @{ effortLevel = 'xhigh' } },
    @{ Name = 'zero-usage';
       Input = (New-FixtureInput -SessionId ([guid]::NewGuid()) -CurrentDir $repo -Model 'Opus' -InputTokens 0 -OutputTokens 0 -Remaining 80) },
    @{ Name = 'red-threshold';
       Input = (New-FixtureInput -SessionId ([guid]::NewGuid()) -CurrentDir $repo -Model 'Opus' -Remaining 10) },
    @{ Name = 'yellow-threshold';
       Input = (New-FixtureInput -SessionId ([guid]::NewGuid()) -CurrentDir $repo -Model 'Opus' -Remaining 30) },
    @{ Name = 'green-threshold';
       Input = (New-FixtureInput -SessionId ([guid]::NewGuid()) -CurrentDir $repo -Model 'Opus' -Remaining 60) },
    @{ Name = 'no-remaining';
       Input = (New-FixtureInput -SessionId ([guid]::NewGuid()) -CurrentDir $repo -Model 'Opus') },
    @{ Name = 'project-dir-fallback';
       Input = (New-FixtureInput -SessionId ([guid]::NewGuid()) -ProjectDir 'C:\my\cool-proj' -Model 'Opus' -Remaining 50) },
    @{ Name = 'no-project';
       Input = (New-FixtureInput -SessionId ([guid]::NewGuid()) -Model 'Opus' -Remaining 50) },
    @{ Name = 'unicode-model-name';
       Input = (New-FixtureInput -SessionId ([guid]::NewGuid()) -CurrentDir $repo -Model 'Opus 4.7 (1M context)' -InputTokens 500 -OutputTokens 500 -Remaining 70 -ApiDurationMS 2000) },
    @{ Name = 'long-dir-path';
       Input = (New-FixtureInput -SessionId ([guid]::NewGuid()) -CurrentDir ('C:\' + ('x' * 260)) -Model 'Opus' -Remaining 50) },
    @{ Name = 'sonnet-high';
       Input = (New-FixtureInput -SessionId ([guid]::NewGuid()) -CurrentDir $repo -Model 'Sonnet' -InputTokens 1500 -OutputTokens 500 -Remaining 75);
       Settings = @{ effortLevel = 'high' } },
    @{ Name = 'xhigh-effort-title-case';
       Input = (New-FixtureInput -SessionId ([guid]::NewGuid()) -CurrentDir $repo -Model 'Opus' -Remaining 60);
       Settings = @{ effortLevel = 'xhigh' } },
    @{ Name = 'expired-timer';
       Input = (New-FixtureInput -SessionId ([guid]::NewGuid()) -CurrentDir $repo -Model 'Opus' -Remaining 50);
       CacheSeed = @{ ('TIMER_Opus') = '1000000000000' } },
    @{ Name = 'fresh-timer';
       Input = (New-FixtureInput -SessionId ([guid]::NewGuid()) -CurrentDir $repo -Model 'Opus' -Remaining 50);
       CacheSeed = @{ ('TIMER_Opus') = ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() - 600000).ToString() } },
    @{ Name = 'cache-segment-large';
       Input = (New-FixtureInput -SessionId ([guid]::NewGuid()) -CurrentDir $repo -Model 'Opus' -InputTokens 50000 -OutputTokens 25000 -Remaining 85) },
    @{ Name = 'cached-effort-label';
       Input = (New-FixtureInput -SessionId ([guid]::NewGuid()) -CurrentDir $repo -Model 'Opus' -Remaining 50);
       Settings = @{ effortLevel = 'medium' } },
    @{ Name = 'apiduration-zero';
       Input = (New-FixtureInput -SessionId ([guid]::NewGuid()) -CurrentDir $repo -Model 'Opus' -Remaining 50 -ApiDurationMS 0) }
)

$mismatches = 0
$total = $fixtures.Count
foreach ($f in $fixtures) {
    $res = Run-Both -Fixture $f
    $psOut = $res.ps.Stdout
    $goOut = $res.go.Stdout
    # Normalize: strip ANSI, strip trailing whitespace
    $strip = { param($s) ($s -replace "`e\[[0-9;]*m",'').TrimEnd() }
    $psN = & $strip $psOut
    $goN = & $strip $goOut
    if ($psN -eq $goN) {
        Write-Host "[OK]   $($f.Name)"
    } else {
        $mismatches++
        Write-Host "[DIFF] $($f.Name)" -ForegroundColor Red
        Write-Host "  ps: $psN"
        Write-Host "  go: $goN"
    }
}

Write-Host ""
Write-Host "$($total - $mismatches)/$total fixtures matched"
if ($mismatches -gt 0) { exit 1 }
