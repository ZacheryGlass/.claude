# Build statusline.exe from statusline.go.
# Usage: pwsh -File build.ps1
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

# Locate go: prefer PATH, fall back to portable install.
$go = (Get-Command go -ErrorAction SilentlyContinue).Source
if (-not $go) {
    $portable = Join-Path $env:USERPROFILE '.local\go-tools\go\bin\go.exe'
    if (Test-Path $portable) { $go = $portable }
}
if (-not $go) {
    throw "go not found on PATH or at ~/.local/go-tools/go/bin/go.exe"
}

Push-Location $here
try {
    if (-not (Test-Path 'go.mod')) {
        & $go mod init statusline | Out-Null
    }
    & $go build -trimpath -ldflags='-s -w' -o statusline.exe statusline.go
    if ($LASTEXITCODE -ne 0) { throw "go build failed (exit $LASTEXITCODE)" }
    Write-Host ("Built: {0} ({1:N0} bytes)" -f (Resolve-Path .\statusline.exe), (Get-Item .\statusline.exe).Length)
} finally {
    Pop-Location
}
