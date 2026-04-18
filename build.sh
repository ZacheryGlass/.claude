#!/usr/bin/env bash
# Build statusline.exe (or platform-native binary) from statusline.go.
set -euo pipefail
cd "$(dirname "$0")"

GO="${GO:-go}"
if ! command -v "$GO" >/dev/null 2>&1; then
    echo "go not found on PATH; install Go or set GO=/path/to/go" >&2
    exit 1
fi

[ -f go.mod ] || "$GO" mod init statusline >/dev/null

OUT=statusline
case "$(uname -s 2>/dev/null || echo)" in
    MINGW*|MSYS*|CYGWIN*|*_NT-*) OUT=statusline.exe ;;
esac

"$GO" build -trimpath -ldflags='-s -w' -o "$OUT" statusline.go
ls -la "$OUT"
