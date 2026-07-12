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

# Injected into every child via --append-system-prompt. Observed stall mode:
# a headless child ends its turn "to wait" for background Bash jobs, the
# process exits, and the jobs die with it — the run then reports exit 0.
HEADLESS_RULE='Headless goal run: ending your turn ends the session process, and any background Bash jobs are killed with it. Run long pipeline stages in the foreground, or poll them to completion inside the same turn; never end a turn while work is still pending. Commit and push your work before finishing - deliverables (commits, PR) are the only trusted evidence of completion.'

usage() {
cat <<'EOF'
Usage: run_goals.sh [options] [-g "GOAL TEXT" ...] [goal-file ...]

Each -g argument (or goal file's content) becomes the condition for one
`claude -p "/goal ..."` session. Sessions run in parallel, each in its own
git worktree. Results print to stdout; nothing persists on disk.

Options:
  -g, --goal TEXT           Goal condition passed inline (repeatable)
  -R, --resume SLUG[:SID]   Resume an interrupted goal session in its existing
                            worktree (repeatable). SLUG = worktree name minus
                            'goal-'. SID defaults to the deterministic UUIDv5
                            of the slug (runs launched before session naming
                            existed need the explicit :SID form).
      --resume-goal TEXT    Attach to the most recent -R: re-send this exact
                            /goal prompt to the resumed session (re-arms the
                            goal loop) instead of a generic continue nudge.
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
RESUMES=()
RESUME_GOALS=()
while [ $# -gt 0 ]; do
  case "$1" in
    -g|--goal)            GOAL_TEXTS+=("$2"); shift 2 ;;
    -R|--resume)          RESUMES+=("$2"); RESUME_GOALS+=(""); shift 2 ;;
    --resume-goal)        [ "${#RESUMES[@]}" -gt 0 ] || die "--resume-goal must follow a -R"
                          RESUME_GOALS[$(( ${#RESUMES[@]} - 1 ))]="$2"; shift 2 ;;
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

TOTAL=$(( ${#GOAL_TEXTS[@]} + ${#GOAL_FILES[@]} + ${#RESUMES[@]} ))
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

# The session ID is a deterministic UUIDv5 of the slug — the slug (== the
# worktree name) effectively NAMES the session. If a run is killed mid-flight,
# the session ID is recomputable from the worktree name alone (no output
# capture needed): transcripts persist under ~/.claude/projects/ keyed by the
# child's cwd, and resume = (cd <worktree> && claude --resume <sid>).
# RUN_TAG in the slug keeps IDs unique across runs (a reused slug would
# collide with the existing session of the same name).
sid_for_slug() {
  python3 -c "import uuid,sys; print(uuid.uuid5(uuid.NAMESPACE_URL, 'run-goals://' + sys.argv[1]))" "$1" 2>/dev/null
}

resume_hint() {
  # $1=slug — where and how to resume this goal's session. An explicit SID
  # (from -R slug:sid) overrides the derived one.
  local sid
  sid="$(cat "$RESULTS_DIR/$1.resume" 2>/dev/null)"
  [ -n "$sid" ] || sid="$(sid_for_slug "$1")"
  local loc="$REPO"
  [ "$WORKTREE" -eq 1 ] && loc="$REPO/.claude/worktrees/goal-$1"
  echo "(cd $loc && claude --resume $sid)"
}

launch() {
  # $1=goal text file (inside run dir)  $2=slug
  local file="$1" slug="$2"
  local out="$RESULTS_DIR/$slug.json" err="$RESULTS_DIR/$slug.err"
  local cmd sid runcwd="$REPO" verb="launch"
  if [ -f "$RESULTS_DIR/$slug.resume" ]; then
    # Resume mode: re-enter an interrupted session inside its EXISTING
    # worktree. Transcripts are keyed by the child's cwd, so run from the
    # worktree and do NOT pass --worktree (it already exists).
    local sid_override
    sid_override="$(cat "$RESULTS_DIR/$slug.resume")"
    sid="${sid_override:-$(sid_for_slug "$slug")}"
    runcwd="$REPO/.claude/worktrees/goal-$slug"
    verb="resume"
    # With --resume-goal, re-send the exact original /goal prompt (re-arms
    # the goal loop); otherwise a generic continuation nudge.
    local prompt='Interrupted mid-goal: resume from the committed worktree state and finish the original /goal COMPLETION condition. Check git log/status first - do not redo completed work.'
    [ -s "$file" ] && prompt="/goal $(cat "$file")"
    cmd=(claude -p "$prompt" \
         --resume "$sid" --output-format json --permission-mode "$PERM_MODE" \
         --append-system-prompt "$HEADLESS_RULE")
    [ -n "$MODEL" ]         && cmd+=(--model "$MODEL")
    [ -n "$ALLOWED_TOOLS" ] && cmd+=(--allowedTools "$ALLOWED_TOOLS")
  else
    local goal_text
    goal_text="$(cat "$file")"
    cmd=(claude -p "/goal ${goal_text}" --output-format json --permission-mode "$PERM_MODE" \
        --append-system-prompt "$HEADLESS_RULE")
    [ -n "$MODEL" ]         && cmd+=(--model "$MODEL")
    [ -n "$ALLOWED_TOOLS" ] && cmd+=(--allowedTools "$ALLOWED_TOOLS")
    [ "$WORKTREE" -eq 1 ]   && cmd+=(--worktree "goal-${slug}")
    sid="$(sid_for_slug "$slug")"
    [ -n "$sid" ] && cmd+=(--session-id "$sid")
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    printf 'DRY RUN [%s]: (cd %q && ' "$slug" "$runcwd"
    printf '%q ' "${cmd[@]}"
    printf ')\n'
    echo 0 > "$RESULTS_DIR/$slug.exit"
    return 0
  fi

  echo "[$(date +%H:%M:%S)] $verb: $slug session=${sid:-auto}"
  [ -n "$sid" ] && echo "        resume if interrupted: $(resume_hint "$slug")"
  ( cd "$runcwd" && "${cmd[@]}" >"$out" 2>"$err" ) &
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

# Materialize every goal (inline texts + files) into the ephemeral run dir.
# RUN_TAG (runner PID) keeps worktree/branch names unique across CONCURRENT
# invocations — two runs launched with similar goal text otherwise slugify to
# the same worktree and collide.
RUN_TAG="$$"
i=0
SLUGS=()
add_goal() {
  # $1=slug base  $2=source (text|file)  $3=payload
  i=$((i + 1))
  local slug
  slug="$(printf '%02d' "$i")-r${RUN_TAG}-$1"
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
# Resume entries keep their ORIGINAL slug (no RUN_TAG re-prefix) so the
# derived session ID and existing worktree both match.
if [ "${#RESUMES[@]}" -gt 0 ]; then
  ri=0
  for r in "${RESUMES[@]}"; do
    rslug="${r%%:*}"
    rsid="${r#*:}"; [ "$rsid" = "$r" ] && rsid=""
    [ -d "$REPO/.claude/worktrees/goal-$rslug" ] || die "resume: worktree goal-$rslug not found under $REPO/.claude/worktrees/"
    SLUGS+=("$rslug")
    printf '%s' "$rsid" > "$RESULTS_DIR/$rslug.resume"
    # optional exact /goal prompt to re-send on resume
    [ -n "${RESUME_GOALS[$ri]}" ] && printf '%s' "${RESUME_GOALS[$ri]}" > "$RESULTS_DIR/$rslug.goal.md"
    ri=$((ri + 1))
  done
fi

# On kill/interrupt, children die with us — print everything needed to
# resume each goal before exiting (worktrees + branches are left intact).
interrupted() {
  echo ""
  echo "==== run-goals INTERRUPTED — resume commands (work + worktrees preserved) ===="
  local slug
  for slug in "${SLUGS[@]}"; do
    echo "$slug"
    echo "        $(resume_hint "$slug")"
  done
  echo "(each resumed session keeps its full context; nothing was pruned)"
  exit 130
}
trap interrupted TERM INT

# Launch pool
for slug in "${SLUGS[@]}"; do
  while [ "$(jobs -rp | wc -l | tr -d ' ')" -ge "$CONCURRENCY" ]; do sleep 2; done
  launch "$RESULTS_DIR/$slug.goal.md" "$slug" &
  sleep 1   # stagger concurrent worktree creation
done
wait
trap - TERM INT

# Summary (stdout is the only artifact — run dir is deleted on exit)
DEF="$(default_ref)"
echo ""
echo "==== run-goals summary ===="
echo "(exit 0 means the child session ended cleanly, NOT that the goal completed —"
echo " check each work: line and verify deliverables (commits/PR) before trusting OK)"
overall=0
for slug in "${SLUGS[@]}"; do
  rc="$(cat "$RESULTS_DIR/$slug.exit" 2>/dev/null || echo '?')"
  session=""; result=""; is_error=""
  if [ -s "$RESULTS_DIR/$slug.json" ] && command -v jq >/dev/null 2>&1; then
    session="$(jq -r '.session_id // empty' "$RESULTS_DIR/$slug.json" 2>/dev/null)"
    is_error="$(jq -r '.is_error // empty' "$RESULTS_DIR/$slug.json" 2>/dev/null)"
    result="$(jq -r '.result // empty' "$RESULTS_DIR/$slug.json" 2>/dev/null | head -c 2000)"
  fi
  if [ -z "$session" ]; then
    session="$(cat "$RESULTS_DIR/$slug.resume" 2>/dev/null)"
    [ -n "$session" ] || session="$(sid_for_slug "$slug")"
  fi
  status="OK"
  if [ "$rc" != "0" ] || [ "$is_error" = "true" ]; then status="FAIL"; overall=1; fi
  [ "$rc" = "143" ] && [ "$TIMEOUT" -gt 0 ] && status="TIMEOUT"
  branch="-"; work=""
  if [ "$WORKTREE" -eq 1 ]; then
    branch="worktree-goal-${slug}"
    wt="$REPO/.claude/worktrees/goal-$slug"
    if [ -d "$wt" ]; then
      # children may switch branches — report the worktree's actual HEAD
      head_br="$(git -C "$wt" branch --show-current 2>/dev/null)"
      [ -n "$head_br" ] && branch="$head_br"
      commits="$(git -C "$wt" rev-list --count "$DEF..HEAD" 2>/dev/null || echo '?')"
      dirty=""
      [ -n "$(git -C "$wt" status --porcelain 2>/dev/null | head -1)" ] && dirty=", uncommitted changes"
      work="        work: $commits commit(s) beyond $DEF$dirty"
    fi
  fi
  echo ""
  echo "[$status] $slug  exit=$rc  session=${session:-?}  branch=$branch"
  [ -n "$work" ] && echo "$work"
  if [ -n "$result" ]; then
    printf '%s\n' "$result" | sed 's/^/        /'
  fi
  [ "$status" != "OK" ] && [ -s "$RESULTS_DIR/$slug.err" ] \
    && echo "        stderr: $(head -c 400 "$RESULTS_DIR/$slug.err")"
done

# Auto-prune zero-work worktrees (clean + no commits beyond default branch)
if [ "$WORKTREE" -eq 1 ] && [ "$DRY_RUN" -eq 0 ]; then
  echo ""
  echo "---- worktree auto-prune (base: $DEF) ----"
  leftovers=0
  for slug in "${SLUGS[@]}"; do
    wt="$REPO/.claude/worktrees/goal-$slug"
    br="worktree-goal-$slug"
    [ -d "$wt" ] || continue
    # the child session has exited, so any session lock it left is stale
    git -C "$REPO" worktree unlock "$wt" >/dev/null 2>&1
    dirty="$(git -C "$wt" status --porcelain 2>/dev/null | head -1)"
    # judge the worktree by its actual HEAD — children may switch branches
    head_br="$(git -C "$wt" branch --show-current 2>/dev/null)"
    [ -z "$head_br" ] && head_br="$br"
    unique="$(git -C "$wt" rev-list --count "$DEF..HEAD" 2>/dev/null || echo '?')"
    if [ -z "$dirty" ] && [ "$unique" = "0" ]; then
      if git -C "$REPO" worktree remove "$wt" >/dev/null 2>&1; then
        git -C "$REPO" branch -D "$br" >/dev/null 2>&1
        echo "pruned: goal-$slug (no work produced)"
      else
        echo "kept:   goal-$slug (prune failed — clean up manually)"; leftovers=1
      fi
    else
      reason="on $head_br, $unique commit(s) beyond $DEF"
      [ -n "$dirty" ] && reason="$reason, uncommitted changes"
      echo "kept:   goal-$slug ($reason) — review at $wt"
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
echo "resume a session:  cd into its WORKTREE (transcripts are keyed by cwd), then claude --resume <session-id>"
echo "recover a lost id: python3 -c \"import uuid; print(uuid.uuid5(uuid.NAMESPACE_URL, 'run-goals://<slug>'))\"  # slug = worktree name minus 'goal-'"
exit "$overall"
