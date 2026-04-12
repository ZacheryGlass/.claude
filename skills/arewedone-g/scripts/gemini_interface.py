import argparse
import os
import subprocess
import sys


def main():
    # Fix Windows console encoding — Gemini outputs emoji (✅, ❌) which cp1252 can't handle
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    parser = argparse.ArgumentParser(description="Delegate tasks to Gemini CLI")
    parser.add_argument("--prompt", required=True, help="The prompt to send to Gemini CLI")
    parser.add_argument("--system-md", help="Path to a markdown file to prepend as system instructions")
    parser.add_argument("--context-file", help="Path to a file containing additional context")
    parser.add_argument("--cwd", help="Working directory for the Gemini CLI")
    parser.add_argument("--model", default="gemini-3.1-pro-preview", help="Gemini model to use")

    args = parser.parse_args()

    # Build the full prompt: system instructions (from --system-md) + task prompt
    full_prompt = args.prompt
    if args.system_md and os.path.exists(args.system_md):
        with open(args.system_md, "r", encoding="utf-8") as f:
            content = f.read()
        # Strip YAML frontmatter if present
        if content.startswith("---"):
            parts = content.split("---", 2)
            instructions = parts[2].strip() if len(parts) >= 3 else content
        else:
            instructions = content.strip()
        full_prompt = f"{instructions}\n\n---\n\n{args.prompt}"

    if args.context_file:
        context_path = os.path.abspath(args.context_file)
        # @ syntax attaches file content to the prompt in Gemini CLI
        full_prompt += f"\n\nContext file: @{context_path}"

    # -p = non-interactive (headless) mode; --approval-mode=plan = read-only tools only
    cmd = ["gemini.cmd", "-p", full_prompt, "--approval-mode=plan", "-o", "text", "-m", args.model]

    process = subprocess.Popen(
        cmd,
        cwd=args.cwd if args.cwd else os.getcwd(),
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    process.stdin.close()

    for line in process.stdout:
        print(line, end="")
        sys.stdout.flush()

    process.wait()
    sys.exit(process.returncode)


if __name__ == "__main__":
    main()
