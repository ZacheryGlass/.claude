#!/usr/bin/env bash
# run_goals.sh — launch parallel non-interactive Claude Code sessions, each
# driven by the native /goal loop, each isolated in its own git worktree.
#
# Zero-persistence: the run dir lives under $TMPDIR via mktemp and is deleted
# on exit (unless --keep or an explicit -o DIR is given). The printed summary
# is the only artifact. Zero-work worktrees are auto-pruned at end of run.
set -u

CONCURRENCY=3
MODEL=""
PERM_MODE="acceptEdits"
ALLOWED_TOOLS=""
REPO="$(pwd)"
RESULTS_DIR=""
WORKTREE=1
DRY_RUN=0
KEEP=0
TIMEOUT=0

usage() {
cat <<'EOF'
Usage: run_goals.sh [options] [-g "GOAL TEXT" ...] [goal-file ...]

Each -g argument (or goal file's content) becomes the condition for one
`claude -p "/goal ..."` session. Sessions run in parallel, each in its own
git worktree. Results print to stdout; nothing persists on disk.

Options:
  -g, --goal TEXT           Goal condition passed inline (repeatable)
  -c, --concurrency N       Max parallel sessions (default 3)
  -m, --model MODEL         Model for child sessions (default: user default)
  -p, --permission-mode M   default|acceptEdits|dontAsk|bypassPermissions
                            (default acceptEdits)
  -a, --allowed-tools LIST  --allowedTools rules for children,
                            e.g. 'Bash(npm test *),Bash(git commit *)'
  -t, --timeout SECONDS     Kill a child session that overruns (default: off)
  -r, --repo DIR            Repo to run in (default: cwd)
  -o, --out DIR             Results dir (implies --keep; default: mktemp, deleted on exit)
      --keep                Do not delete the run dir on exit
      --no-worktree         Run children directly in the repo (unsafe in parallel)
      --dry-run             Print commands without launching
  -h, --help                Show this help
EOF
}

die() { echo "run_goals: $*" >&2; exit 1; }

GOAL_FILES=()
GOAL_TEXTS=()
while [ $# -gt 0 ]; do
  case "$1" in
    -g|--goal)            GOAL_TEXTS+=("$2"); shift 2 ;;
    -c|--concurrency)     CONCURRENCY="$2"; shift 2 ;;
    -m|--model)           MODEL="$2"; shift 2 ;;
    -p|--permission-mode) PERM_MODE="$2"; shift 2 ;;
    -a|--allowed-tools)   ALLOWED_TOOLS="$2"; shift 2 ;;
    -t|--timeout)         TIMEOUT="$2"; shift 2 ;;
    -r|--repo)            REPO="$2"; shift 2 ;;
    -o|--out)             RESULTS_DIR="$2"; KEEP=1; shift 2 ;;
    --keep)               KEEP=1; shift ;;
    --no-worktree)        WORKTREE=0; shift ;;
    --dry-run)            DRY_RUN=1; shift ;;
    -h|--help)            usage; exit 0 ;;
    -*)                   die "unknown option: $1" ;;
    *)                    GOAL_FILES+=("$1"); shift ;;
  esac
done

TOTAL=$(( ${#GOAL_TEXTS[@]} + ${#GOAL_FILES[@]} ))
[ "$TOTAL" -gt 0 ] || { usage; exit 1; }
command -v claude >/dev/null 2>&1 || die "claude CLI not found on PATH"
if [ "${#GOAL_FILES[@]}" -gt 0 ]; then
  for f in "${GOAL_FILES[@]}"; do [ -r "$f" ] || die "cannot read goal file: $f"; done
fi

REPO="$(cd "$REPO" && pwd)" || die "bad --repo"
if [ "$WORKTREE" -eq 1 ]; then
  git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || die "$REPO is not a git repo (worktree isolation requires git; use --no-worktree)"
fi

if [ -z "$RESULTS_DIR" ]; then
  RESULTS_DIR="$(mktemp -d "${TMPDIR:-/tmp}/run-goals.XXXXXX")" || die "mktemp failed"
else
  mkdir -p "$RESULTS_DIR" || die "cannot create results dir"
fi

cleanup_run_dir() {
  if [ "$KEEP" -eq 0 ]; then
    rm -rf "$RESULTS_DIR"
  else
    echo "run dir kept: $RESULTS_DIR"
  fi
}
trap cleanup_run_dir EXIT

default_ref() {
  local ref
  ref="$(git -C "$REPO" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)" \
    && { echo "$ref"; return; }
  local b
  for b in main master; do
    git -C "$REPO" show-ref --verify --quiet "refs/heads/$b" && { echo "$b"; return; }
  done
  echo "HEAD"
}

slugify_text() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' \
    | sed 's/^-*//;s/-*$//' | cut -c1-32
}

slugify_file() {
  basename "$1" | sed 's/\.[^.]*$//' | tr '[:upper:]' '[:lower:]' \
    | tr -cs 'a-z0-9' '-' | sed 's/^[0-9-]*//;s/-*$//' | cut -c1-32
}

launch() {
  # $1=goal text file (inside run dir)  $2=slug
  local file="$1" slug="$2"
  local out="$RESULTS_DIR/$slug.json" err="$RESULTS_DIR/$slug.err"
  local goal_text
  goal_text="$(cat "$file")"
  local cmd=(claude -p "/goal ${goal_text}" --output-format json --permission-mode "$PERM_MODE")
  [ -n "$MODEL" ]         && cmd+=(--model "$MODEL")
  [ -n "$ALLOWED_TOOLS" ] && cmd+=(--allowedTools "$ALLOWED_TOOLS")
  [ "$WORKTREE" -eq 1 ]   && cmd+=(--worktree "goal-${slug}")

  if [ "$DRY_RUN" -eq 1 ]; then
    printf 'DRY RUN [%s]: (cd %q && ' "$slug" "$REPO"
    printf '%q ' "${cmd[@]}"
    printf ')\n'
    echo 0 > "$RESULTS_DIR/$slug.exit"
    return 0
  fi

  echo "[$(date +%H:%M:%S)] launch: $slug"
  ( cd "$REPO" && "${cmd[@]}" >"$out" 2>"$err" ) &
  local cpid=$!
  local wpid=""
  if [ "$TIMEOUT" -gt 0 ]; then
    ( sleep "$TIMEOUT"; kill "$cpid" 2>/dev/null ) & wpid=$!
  fi
  wait "$cpid"
  local rc=$?
  [ -n "$wpid" ] && kill "$wpid" 2>/dev/null
  echo "$rc" > "$RESULTS_DIR/$slug.exit"
  echo "[$(date +%H:%M:%S)] done:   $slug (exit $rc)"
}

# Materialize every goal (inline texts + files) into the ephemeral run dir
i=0
SLUGS=()
add_goal() {
  # $1=slug base  $2=source (text|file)  $3=payload
  i=$((i + 1))
  local slug
  slug="$(printf '%02d' "$i")-$1"
  SLUGS+=("$slug")
  if [ "$2" = "text" ]; then
    printf '%s' "$3" > "$RESULTS_DIR/$slug.goal.md"
  else
    cp "$3" "$RESULTS_DIR/$slug.goal.md"
  fi
}
if [ "${#GOAL_TEXTS[@]}" -gt 0 ]; then
  for t in "${GOAL_TEXTS[@]}"; do add_goal "$(slugify_text "$t")" text "$t"; done
fi
if [ "${#GOAL_FILES[@]}" -gt 0 ]; then
  for f in "${GOAL_FILES[@]}"; do add_goal "$(slugify_file "$f")" file "$f"; done
fi

# Launch pool
for slug in "${SLUGS[@]}"; do
  while [ "$(jobs -rp | wc -l | tr -d ' ')" -ge "$CONCURRENCY" ]; do sleep 2; done
  launch "$RESULTS_DIR/$slug.goal.md" "$slug" &
  sleep 1   # stagger concurrent worktree creation
done
wait

# Summary (stdout is the only artifact — run dir is deleted on exit)
echo ""
echo "==== run-goals summary ===="
overall=0
for slug in "${SLUGS[@]}"; do
  rc="$(cat "$RESULTS_DIR/$slug.exit" 2>/dev/null || echo '?')"
  session=""; result=""; is_error=""
  if [ -s "$RESULTS_DIR/$slug.json" ] && command -v jq >/dev/null 2>&1; then
    session="$(jq -r '.session_id // empty' "$RESULTS_DIR/$slug.json" 2>/dev/null)"
    is_error="$(jq -r '.is_error // empty' "$RESULTS_DIR/$slug.json" 2>/dev/null)"
    result="$(jq -r '.result // empty' "$RESULTS_DIR/$slug.json" 2>/dev/null | head -c 2000)"
  fi
  status="OK"
  if [ "$rc" != "0" ] || [ "$is_error" = "true" ]; then status="FAIL"; overall=1; fi
  [ "$rc" = "143" ] && [ "$TIMEOUT" -gt 0 ] && status="TIMEOUT"
  branch="-"
  [ "$WORKTREE" -eq 1 ] && branch="worktree-goal-${slug}"
  echo ""
  echo "[$status] $slug  exit=$rc  session=${session:-?}  branch=$branch"
  if [ -n "$result" ]; then
    printf '%s\n' "$result" | sed 's/^/        /'
  fi
  [ "$status" != "OK" ] && [ -s "$RESULTS_DIR/$slug.err" ] \
    && echo "        stderr: $(head -c 400 "$RESULTS_DIR/$slug.err")"
done

# Auto-prune zero-work worktrees (clean + no commits beyond default branch)
if [ "$WORKTREE" -eq 1 ] && [ "$DRY_RUN" -eq 0 ]; then
  DEF="$(default_ref)"
  echo ""
  echo "---- worktree auto-prune (base: $DEF) ----"
  leftovers=0
  for slug in "${SLUGS[@]}"; do
    wt="$REPO/.claude/worktrees/goal-$slug"
    br="worktree-goal-$slug"
    [ -d "$wt" ] || continue
    dirty="$(git -C "$wt" status --porcelain 2>/dev/null | head -1)"
    unique="$(git -C "$REPO" rev-list --count "$DEF..$br" 2>/dev/null || echo '?')"
    if [ -z "$dirty" ] && [ "$unique" = "0" ]; then
      git -C "$REPO" worktree remove "$wt" >/dev/null 2>&1 \
        && git -C "$REPO" branch -D "$br" >/dev/null 2>&1 \
        && echo "pruned: $br (no work produced)" \
        || { echo "kept:   $br (prune failed — clean up manually)"; leftovers=1; }
    else
      reason="has $unique commit(s) beyond $DEF"
      [ -n "$dirty" ] && reason="$reason, uncommitted changes"
      echo "kept:   $br ($reason) — review at $wt"
      leftovers=1
    fi
  done
  if [ "$leftovers" -eq 1 ]; then
    echo ""
    echo "after review/merge, clean leftovers with:"
    echo "  $(dirname "$0")/cleanup_goals.sh -r $REPO           # dry-run"
    echo "  $(dirname "$0")/cleanup_goals.sh -r $REPO --apply   # execute"
  fi
fi

echo ""
echo "resume a session:  (cd $REPO && claude --resume <session-id>)"
exit "$overall"
