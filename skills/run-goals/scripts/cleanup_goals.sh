#!/usr/bin/env bash
# cleanup_goals.sh — remove leftover run-goals worktrees and branches.
#
# Scope: ONLY worktrees under .claude/worktrees/goal-* and branches named
# worktree-goal-*. Dry-run by default; --apply to execute; --force to discard
# dirty worktrees and unmerged branches. For repo-wide cleanup with full
# cross-ref reachability checks, use the /git-worktree-prune skill instead.
set -u

APPLY=0
FORCE=0
REPO="$(pwd)"

usage() {
cat <<'EOF'
Usage: cleanup_goals.sh [-r DIR] [--apply] [--force]

Removes leftover run-goals worktrees (.claude/worktrees/goal-*) and local
branches (worktree-goal-*).

Safety (without --force):
  - a worktree is removed only if it has no uncommitted/untracked changes
  - a branch is deleted only if it has no commits beyond the default branch

Options:
  -r, --repo DIR   Repo to clean (default: cwd)
      --apply      Execute the plan (default: dry-run, prints plan only)
      --force      Also discard dirty worktrees and unmerged branches
  -h, --help       Show this help
EOF
}

die() { echo "cleanup_goals: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    -r|--repo) REPO="$2"; shift 2 ;;
    --apply)   APPLY=1; shift ;;
    --force)   FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *)         die "unknown option: $1" ;;
  esac
done

REPO="$(cd "$REPO" && pwd)" || die "bad --repo"
git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "$REPO is not a git repo"

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
DEF="$(default_ref)"

MODE="dry-run"
[ "$APPLY" -eq 1 ] && MODE="apply"
echo "repo: $REPO"
echo "default branch: $DEF"
echo "mode: $MODE$([ "$FORCE" -eq 1 ] && echo ' + force')"
echo ""

removed=0
kept=0

# --- Pass 1: goal worktrees (from `git worktree list --porcelain`) ---------
SEEN_BRANCHES=""
cur_path=""
cur_branch=""

process_worktree() {
  local wt="$1" br="$2"
  case "$br" in worktree-goal-*) ;; *)
    case "$wt" in */.claude/worktrees/goal-*) ;; *) return ;; esac
  esac
  SEEN_BRANCHES="$SEEN_BRANCHES $br"

  local dirty unique
  dirty="$(git -C "$wt" status --porcelain 2>/dev/null | head -1)"
  unique="$(git -C "$REPO" rev-list --count "$DEF..$br" 2>/dev/null || echo '?')"

  # Worktree
  if [ -n "$dirty" ] && [ "$FORCE" -eq 0 ]; then
    echo "KEEP   worktree $wt -- uncommitted changes (--force to discard)"
    kept=$((kept + 1))
  else
    local wnote=""
    [ -n "$dirty" ] && wnote=" (discarding uncommitted changes)"
    if [ "$APPLY" -eq 1 ]; then
      if [ "$FORCE" -eq 1 ]; then
        git -C "$REPO" worktree remove --force "$wt" >/dev/null 2>&1
      else
        git -C "$REPO" worktree remove "$wt" >/dev/null 2>&1
      fi
      if [ -d "$wt" ]; then
        echo "FAIL   worktree $wt -- removal failed"
        kept=$((kept + 1))
        return
      fi
    fi
    echo "REMOVE worktree $wt$wnote"
    removed=$((removed + 1))
  fi

  # Branch (only after worktree is gone / would be gone)
  if [ -n "$dirty" ] && [ "$FORCE" -eq 0 ]; then
    return   # worktree kept -> branch stays checked out
  fi
  delete_branch "$br" "$unique"
}

delete_branch() {
  local br="$1" unique="$2"
  if [ "$unique" = "0" ]; then
    # every commit reachable from $DEF -> -D loses nothing
    if [ "$APPLY" -eq 1 ]; then
      git -C "$REPO" branch -D "$br" >/dev/null 2>&1 \
        || { echo "FAIL   branch $br -- delete failed"; kept=$((kept + 1)); return; }
    fi
    echo "DELETE branch $br -- no commits beyond $DEF"
    removed=$((removed + 1))
  elif [ "$FORCE" -eq 1 ]; then
    if [ "$APPLY" -eq 1 ]; then
      git -C "$REPO" branch -D "$br" >/dev/null 2>&1 \
        || { echo "FAIL   branch $br -- delete failed"; kept=$((kept + 1)); return; }
    fi
    echo "DELETE branch $br -- DISCARDING $unique unmerged commit(s) (--force)"
    removed=$((removed + 1))
  else
    echo "KEEP   branch $br -- $unique unmerged commit(s); merge/push first,"
    echo "       rerun with --force to discard, or run /git-worktree-prune"
    kept=$((kept + 1))
  fi
}

while IFS= read -r line; do
  case "$line" in
    "worktree "*)          cur_path="${line#worktree }" ;;
    "branch refs/heads/"*) cur_branch="${line#branch refs/heads/}"
                           process_worktree "$cur_path" "$cur_branch" ;;
  esac
done < <(git -C "$REPO" worktree list --porcelain)

# --- Pass 2: orphan worktree-goal-* branches (worktree already removed) ----
for br in $(git -C "$REPO" for-each-ref --format='%(refname:short)' 'refs/heads/worktree-goal-*'); do
  case " $SEEN_BRANCHES " in *" $br "*) continue ;; esac
  unique="$(git -C "$REPO" rev-list --count "$DEF..$br" 2>/dev/null || echo '?')"
  delete_branch "$br" "$unique"
done

# --- Finish ----------------------------------------------------------------
[ "$APPLY" -eq 1 ] && git -C "$REPO" worktree prune >/dev/null 2>&1

echo ""
echo "summary: $removed removed/deleted, $kept kept"
if [ "$APPLY" -eq 0 ] && [ "$removed" -gt 0 ]; then
  echo "dry-run only — rerun with --apply to execute"
fi
exit 0
