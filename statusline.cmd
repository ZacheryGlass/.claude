: <<'__STATUSLINE_CMD__'
@echo off
setlocal
"%~dp0statusline.exe" %*
exit /b %ERRORLEVEL%
__STATUSLINE_CMD__

dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1
os=$(uname -s 2>/dev/null || echo unknown)
arch=$(uname -m 2>/dev/null || echo unknown)

case "$os:$arch" in
  Darwin:arm64|Darwin:aarch64)
    exec "$dir/statusline-darwin-arm64" "$@"
    ;;
  Darwin:x86_64|Darwin:amd64)
    exec "$dir/statusline-darwin-amd64" "$@"
    ;;
  MINGW*:x86_64|MSYS*:x86_64|CYGWIN*:x86_64|MINGW*:amd64|MSYS*:amd64|CYGWIN*:amd64)
    exec "$dir/statusline.exe" "$@"
    ;;
esac

echo "unsupported statusline platform: $os/$arch" >&2
exit 1
