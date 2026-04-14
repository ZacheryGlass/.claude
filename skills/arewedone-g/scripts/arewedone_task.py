import argparse
import os
import subprocess
import sys
import tempfile


def git(args):
    """Run a git command, return stdout or error string."""
    try:
        return subprocess.check_output(
            ["git"] + args.split(),
            text=True, encoding="utf-8", stderr=subprocess.STDOUT
        ).strip()
    except Exception as e:
        return f"(error: {e})"


def get_git_context():
    """File-level worktree changes + recent commits. No diff content — Gemini reads files directly."""
    log = git("log --oneline -7")
    status = git("status --short")
    name_status = git("diff --name-status HEAD")
    staged = git("diff --cached --name-status")

    parts = [f"--- RECENT COMMITS (last 7) ---\n{log}"]
    parts.append(f"--- WORKING TREE STATUS ---\n{status or '(clean)'}")
    if name_status:
        parts.append(f"--- CHANGED FILES (unstaged vs HEAD) ---\n{name_status}")
    if staged:
        parts.append(f"--- STAGED FILES ---\n{staged}")
    return "\n\n".join(parts)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--summary", help="A summary of what was worked on")
    parser.add_argument("--model", default="gemini-3.1-pro-preview", help="Gemini model to use (default: gemini-3.1-pro-preview)")
    args = parser.parse_args()

    print("Collecting context...", file=sys.stderr)
    git_context = get_git_context()

    with tempfile.NamedTemporaryFile(mode="w", delete=False, suffix=".txt", encoding="utf-8") as tmp:
        if args.summary:
            tmp.write("=== CONTEXT: WHAT WE'VE BEEN WORKING ON ===\n")
            tmp.write(args.summary)
            tmp.write("\n\n")
        tmp.write("=== RECENT GIT CHANGES ===\n")
        tmp.write(git_context)
        tmp_context_path = tmp.name

    claude_dir = os.path.expanduser("~/.claude")
    system_md_path = os.path.join(claude_dir, "agents", "structural-completeness-reviewer.md")
    interface_script = os.path.join(os.path.dirname(__file__), "gemini_interface.py")

    for path, label in [(system_md_path, "Agent definition"), (interface_script, "Interface script")]:
        if not os.path.exists(path):
            print(f"Error: {label} not found at {path}", file=sys.stderr)
            os.remove(tmp_context_path)
            sys.exit(1)

    prompt = (
        "Perform a structural completeness review of the recent changes. "
        "The context file contains a summary of what was worked on, recent git commits, "
        "and the files that changed. Use your tools to read the relevant changed files "
        "and verify completeness, dead code removal, and integration hygiene."
    )

    cmd = [
        sys.executable, interface_script,
        "--prompt", prompt,
        "--system-md", system_md_path,
        "--context-file", tmp_context_path,
        "--cwd", os.getcwd(),
        "--model", args.model,
    ]

    print("Tasking Gemini with structural completeness review...", file=sys.stderr)
    try:
        result = subprocess.run(cmd)
        exit_code = result.returncode
    except KeyboardInterrupt:
        print("\nReview cancelled.", file=sys.stderr)
        exit_code = 130
    finally:
        try:
            os.remove(tmp_context_path)
        except Exception:
            pass

    sys.exit(exit_code)


if __name__ == "__main__":
    main()
