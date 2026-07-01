#!/usr/bin/env bash
# Build statusline binaries from statusline.go.
set -euo pipefail
cd "$(dirname "$0")"

GO="${GO:-go}"
if ! command -v "$GO" >/dev/null 2>&1; then
    echo "go not found on PATH; install Go or set GO=/path/to/go" >&2
    exit 1
fi

[ -f go.mod ] || "$GO" mod init statusline >/dev/null

"$GO" build -trimpath -ldflags='-s -w' -o statusline statusline.go
GOOS=darwin GOARCH=arm64 "$GO" build -trimpath -ldflags='-s -w' -o statusline-darwin-arm64 statusline.go
GOOS=darwin GOARCH=amd64 "$GO" build -trimpath -ldflags='-s -w' -o statusline-darwin-amd64 statusline.go

case "$(uname -s 2>/dev/null || echo)" in
    MINGW*|MSYS*|CYGWIN*|*_NT-*) "$GO" build -trimpath -ldflags='-s -w' -o statusline.exe statusline.go ;;
esac

ls -la statusline statusline-darwin-arm64 statusline-darwin-amd64 2>/dev/null || true
