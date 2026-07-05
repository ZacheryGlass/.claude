: <<'__EMOJI_REMOVER_CMD__'
@echo off
setlocal
py -c "import os,sys,runpy;runpy.run_path(os.path.expanduser('~/.claude/hooks/'+sys.argv[1]),run_name='__main__')" emoji_remover.py
exit /b %ERRORLEVEL%
__EMOJI_REMOVER_CMD__

dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1
exec python3 "$dir/emoji_remover.py"
