#!/usr/bin/env python3
"""Safely prune stale git worktrees and local branches.

Invariant: NEVER lose a commit. A branch is deleted only when every commit on it
is reachable from some OTHER surviving ref (another local branch, a remote-tracking
branch, or a tag). A worktree is removed only when it is clean (no uncommitted or
untracked changes). Anything with unique work is kept and reported.

Clean worktrees that still hold *ignored* sensitive local files (.env, private keys,
local databases) are kept too -- `git worktree remove` would delete those otherwise.
Override with --remove-ignored.

Dry-run by default -- prints the plan and changes nothing. Pass --apply to execute.
"""
import argparse
import os
import subprocess
import sys
from fnmatch import fnmatch

# Ignored local-only files worth protecting from `git worktree remove`. Matched
# case-insensitively against the basename of each ignored entry.
SENSITIVE_IGNORED = [
    ".env", ".env.*", "*.env", ".envrc",
    "*.pem", "*.key", "*.p12", "*.pfx", "*.keystore", "*.jks",
    "id_rsa", "id_dsa", "id_ecdsa", "id_ed25519",
    "*.sqlite", "*.sqlite3", "*.db",
    ".netrc", ".npmrc", ".pypirc",
    "credentials", "credentials.*", "secrets", "secrets.*", "*.secret",
]


def git(args, cwd, check=True):
    r = subprocess.run(["git"] + args, cwd=cwd, capture_output=True, text=True)
    if check and r.returncode != 0:
        sys.exit(f"git {' '.join(args)} failed:\n{r.stderr.strip()}")
    return r.stdout


def norm(p):
    return os.path.normcase(os.path.normpath(os.path.abspath(p)))


def parse_worktrees(repo):
    """Return list of dicts: {path, branch (or None), detached (bool)}."""
    out = git(["worktree", "list", "--porcelain"], repo)
    wts, cur = [], {}
    for line in out.splitlines():
        if not line.strip():
            if cur:
                wts.append(cur); cur = {}
            continue
        key, _, val = line.partition(" ")
        if key == "worktree":
            cur = {"path": val, "branch": None, "detached": False}
        elif key == "branch":
            cur["branch"] = val.replace("refs/heads/", "", 1)
        elif key == "detached":
            cur["detached"] = True
    if cur:
        wts.append(cur)
    return wts


def _unquote(path):
    """git porcelain wraps paths with special chars in double quotes."""
    if len(path) >= 2 and path[0] == '"' and path[-1] == '"':
        return path[1:-1]
    return path


def ignored_entries(repo, path):
    """Ignored files/dirs present in a worktree (the '!!' porcelain lines)."""
    out = git(["-C", path, "status", "--porcelain", "--ignored"], repo, check=False)
    return [_unquote(l[3:]) for l in out.splitlines() if l.startswith("!!")]


def sensitive_ignored(entries):
    """Basenames of ignored entries that match a SENSITIVE_IGNORED pattern."""
    hits = set()
    for e in entries:
        base = os.path.basename(e.rstrip("/"))
        if any(fnmatch(base, pat) for pat in SENSITIVE_IGNORED):
            hits.add(base)
    return sorted(hits)


def detect_default_branches(repo):
    """Branch names that a remote HEAD (origin/HEAD, ...) points at, plus the
    configured init.defaultBranch -- protected even when they hold no unique work."""
    names = set()
    out = git(["for-each-ref", "--format=%(refname) %(symref)", "refs/remotes"],
              repo, check=False)
    for line in out.splitlines():
        ref, _, sym = line.partition(" ")
        if ref.endswith("/HEAD") and sym.startswith("refs/remotes/"):
            comps = sym.split("/", 3)          # refs/remotes/<remote>/<branch...>
            if len(comps) == 4 and comps[3]:
                names.add(comps[3])
    cfg = git(["config", "--get", "init.defaultBranch"], repo, check=False).strip()
    if cfg:
        names.add(cfg)
    return names


def unique_commits(repo, branch, excluded):
    """Commits on refs/heads/<branch> not reachable from any ref except itself and
    the excluded set (branches already slated for deletion)."""
    all_refs = git(["for-each-ref", "--format=%(refname)",
                    "refs/heads", "refs/remotes", "refs/tags"], repo).split()
    dead = {f"refs/heads/{b}" for b in excluded} | {f"refs/heads/{branch}"}
    others = [r for r in all_refs if r not in dead]
    if not others:
        return ["<no other refs>"]
    out = git(["rev-list", f"refs/heads/{branch}", "--not", *others], repo, check=False)
    return out.split()


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--apply", action="store_true",
                    help="actually remove worktrees / delete branches (default: dry-run)")
    ap.add_argument("--fetch", action="store_true",
                    help="run 'git fetch --all --prune' first so remote-tracking refs are current")
    ap.add_argument("--remove-ignored", action="store_true",
                    help="remove clean worktrees even if they hold ignored sensitive files (e.g. .env)")
    ap.add_argument("--protect", action="append", default=[], metavar="BRANCH",
                    help="branch name to always keep (repeatable)")
    ap.add_argument("--repo", default=".", help="path inside the target repo (default: cwd)")
    args = ap.parse_args()

    repo = args.repo
    if git(["rev-parse", "--is-inside-work-tree"], repo, check=False).strip() != "true":
        sys.exit(f"not a git work tree: {args.repo}")

    if args.fetch:
        print("== git fetch --all --prune ==")
        print(git(["fetch", "--all", "--prune"], repo, check=False).strip() or "  (done)")

    common = git(["rev-parse", "--path-format=absolute", "--git-common-dir"], repo).strip()
    main_wt = norm(os.path.dirname(common))          # primary worktree -- never remove
    cur_branch = git(["rev-parse", "--abbrev-ref", "HEAD"], repo).strip()

    worktrees = parse_worktrees(repo)
    mode = "APPLY" if args.apply else "DRY-RUN"
    print(f"\n===== git-worktree-prune ({mode}) =====")

    # ---- Phase 1: worktrees ----
    print("\n--- worktrees ---")
    kept_wt_branches = set()          # branches held by worktrees we keep -> protect them
    wt_to_remove = []
    for wt in worktrees:
        p = wt["path"]
        label = wt["branch"] or ("(detached)" if wt["detached"] else "(bare)")
        if norm(p) == main_wt:
            print(f"  KEEP  {p}  [{label}]  -- primary worktree")
            if wt["branch"]:
                kept_wt_branches.add(wt["branch"])
            continue
        if not os.path.isdir(p):
            print(f"  PRUNE {p}  [{label}]  -- directory gone (git worktree prune)")
            continue  # handled by `git worktree prune`
        dirty = git(["-C", p, "status", "--porcelain"], repo, check=False).strip()
        if dirty:
            n = len(dirty.splitlines())
            print(f"  KEEP  {p}  [{label}]  -- {n} uncommitted/untracked change(s)")
            if wt["branch"]:
                kept_wt_branches.add(wt["branch"])
            continue
        if wt["detached"]:
            # detached HEAD: only removable if its commit is reachable elsewhere
            head = git(["-C", p, "rev-parse", "HEAD"], repo).strip()
            reach = git(["branch", "-a", "--contains", head], repo, check=False).strip()
            if not reach:
                print(f"  KEEP  {p}  [detached {head[:9]}]  -- commit not on any branch")
                continue
        ignored = ignored_entries(repo, p)
        sensitive = sensitive_ignored(ignored)
        if sensitive and not args.remove_ignored:
            print(f"  KEEP  {p}  [{label}]  -- clean but holds ignored sensitive file(s): "
                  f"{', '.join(sensitive)} (use --remove-ignored to override)")
            if wt["branch"]:
                kept_wt_branches.add(wt["branch"])
            continue
        extra = (f" ({len(ignored)} ignored entr{'y' if len(ignored) == 1 else 'ies'} "
                 f"will be deleted)") if ignored else ""
        print(f"  REMOVE {p}  [{label}]  -- clean{extra}")
        wt_to_remove.append(p)

    if args.apply:
        for p in wt_to_remove:
            git(["worktree", "remove", p], repo, check=False)
        git(["worktree", "prune"], repo, check=False)
        print(f"  -> removed {len(wt_to_remove)} worktree(s); pruned stale entries")
    else:
        print(f"  (dry-run: would remove {len(wt_to_remove)} worktree(s))")

    # ---- Phase 2: branches ----
    print("\n--- local branches ---")
    default_branches = detect_default_branches(repo)
    protected = ({cur_branch, "main", "master", "HEAD"} | default_branches
                 | set(args.protect) | kept_wt_branches)
    extra_defaults = sorted(default_branches - {"main", "master"})
    if extra_defaults:
        print(f"  (default branch protected: {', '.join(extra_defaults)})")
    branches = [b for b in git(["for-each-ref", "--format=%(refname:short)", "refs/heads"], repo).split()]

    to_delete, kept = [], []
    changed = True
    while changed:                    # fixed point: excluding slated deletions can free/keep others
        changed = False
        for b in sorted(branches):
            if b in protected or b in to_delete:
                continue
            if not unique_commits(repo, b, to_delete):
                to_delete.append(b)
                changed = True
    for b in sorted(branches):
        if b in protected:
            kept.append((b, "protected"))
        elif b not in to_delete:
            uc = unique_commits(repo, b, to_delete)
            kept.append((b, f"{len(uc)} unique commit(s) not on any other ref"))

    for b, why in kept:
        print(f"  KEEP   {b}  -- {why}")
    for b in sorted(to_delete):
        print(f"  DELETE {b}  -- fully reachable from other refs (no work lost)")

    if args.apply:
        for b in to_delete:
            r = subprocess.run(["git", "-C", repo, "branch", "-D", b], capture_output=True, text=True)
            print(f"    {'deleted' if r.returncode == 0 else 'FAILED'} {b}"
                  + ("" if r.returncode == 0 else f": {r.stderr.strip()}"))
    else:
        print(f"  (dry-run: would delete {len(to_delete)} branch(es))")

    print(f"\n===== summary ({mode}): "
          f"worktrees remove={len(wt_to_remove)} keep={len(worktrees)-len(wt_to_remove)}; "
          f"branches delete={len(to_delete)} keep={len(kept)} =====")
    if not args.apply and (wt_to_remove or to_delete):
        print("Re-run with --apply to execute. Nothing was changed.")


if __name__ == "__main__":
    main()
