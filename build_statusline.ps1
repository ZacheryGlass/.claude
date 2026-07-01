# Build statusline binaries from statusline.go.
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
$oldGOOS = $env:GOOS
$oldGOARCH = $env:GOARCH
try {
    if (-not (Test-Path 'go.mod')) {
        & $go mod init statusline | Out-Null
    }
    $env:GOOS = 'windows'
    $env:GOARCH = 'amd64'
    & $go build -trimpath -ldflags='-s -w' -o statusline.exe statusline.go
    if ($LASTEXITCODE -ne 0) { throw "go build failed for windows/amd64 (exit $LASTEXITCODE)" }

    $env:GOOS = 'darwin'
    $env:GOARCH = 'arm64'
    & $go build -trimpath -ldflags='-s -w' -o statusline-darwin-arm64 statusline.go
    if ($LASTEXITCODE -ne 0) { throw "go build failed for darwin/arm64 (exit $LASTEXITCODE)" }

    $env:GOARCH = 'amd64'
    & $go build -trimpath -ldflags='-s -w' -o statusline-darwin-amd64 statusline.go
    if ($LASTEXITCODE -ne 0) { throw "go build failed for darwin/amd64 (exit $LASTEXITCODE)" }

    Write-Host ("Built: {0} ({1:N0} bytes)" -f (Resolve-Path .\statusline.exe), (Get-Item .\statusline.exe).Length)
    Write-Host ("Built: {0} ({1:N0} bytes)" -f (Resolve-Path .\statusline-darwin-arm64), (Get-Item .\statusline-darwin-arm64).Length)
    Write-Host ("Built: {0} ({1:N0} bytes)" -f (Resolve-Path .\statusline-darwin-amd64), (Get-Item .\statusline-darwin-amd64).Length)
} finally {
    if ($null -eq $oldGOOS) { Remove-Item Env:\GOOS -ErrorAction SilentlyContinue } else { $env:GOOS = $oldGOOS }
    if ($null -eq $oldGOARCH) { Remove-Item Env:\GOARCH -ErrorAction SilentlyContinue } else { $env:GOARCH = $oldGOARCH }
    Pop-Location
}
