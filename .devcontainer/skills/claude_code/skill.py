"""Claude Code delegation skill for Hermes Agent.

Lets Hermes delegate coding tasks to Claude Code via subprocess.
Claude Code runs with its own OAuth (Claude Pro/Max) and its own
sandboxed tool set (Read/Write/Edit/Bash/Grep/Glob).

Usage inside Hermes:
    from skills.claude_code.skill import call_claude_code
    result = call_claude_code(
        task="Refactor this file to use async/await",
        cwd="/workspace/my-project/backend/main.py"
    )
"""

from __future__ import annotations

import shlex
import subprocess
from pathlib import Path


DEFAULT_TIMEOUT = 900  # 15 minutes
CLAUDE_BIN = "claude"


def call_claude_code(
    task: str,
    cwd: str | Path = "/workspace",
    *,
    timeout: int = DEFAULT_TIMEOUT,
    allowed_tools: list[str] | None = None,
    permission_mode: str = "acceptEdits",
) -> dict:
    """Delegate a task to Claude Code.

    Args:
        task:             The prompt / task description for Claude Code.
        cwd:              Working directory for the Claude session.
                          Claude will only touch files within this subtree.
        timeout:          Max seconds before the subprocess is killed.
        allowed_tools:    Restrict which tools Claude may use (e.g. ["Read", "Edit"]).
                          None = Claude's default tool set.
        permission_mode:  "default" (ask), "acceptEdits" (auto-accept file edits),
                          "plan" (read-only planning), "bypassPermissions" (danger).

    Returns:
        {
            "returncode": int,
            "stdout": str,        # Claude's final output
            "stderr": str,        # any error output
            "timed_out": bool,
        }
    """
    cwd_path = Path(cwd).resolve()
    if not cwd_path.exists():
        return {
            "returncode": -1,
            "stdout": "",
            "stderr": f"cwd does not exist: {cwd_path}",
            "timed_out": False,
        }

    cmd = [CLAUDE_BIN, "-p", task, "--permission-mode", permission_mode]
    if allowed_tools:
        cmd.extend(["--allowed-tools", ",".join(allowed_tools)])

    try:
        proc = subprocess.run(
            cmd,
            cwd=str(cwd_path),
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        return {
            "returncode": proc.returncode,
            "stdout": proc.stdout,
            "stderr": proc.stderr,
            "timed_out": False,
        }
    except subprocess.TimeoutExpired as exc:
        return {
            "returncode": -1,
            "stdout": exc.stdout.decode() if exc.stdout else "",
            "stderr": (exc.stderr.decode() if exc.stderr else "") + f"\n[timeout after {timeout}s]",
            "timed_out": True,
        }
    except FileNotFoundError:
        return {
            "returncode": -1,
            "stdout": "",
            "stderr": f"'{CLAUDE_BIN}' not found on PATH. Install with: npm install -g @anthropic-ai/claude-code",
            "timed_out": False,
        }


if __name__ == "__main__":
    import json
    import sys

    if len(sys.argv) < 2:
        print("Usage: skill.py '<task description>' [cwd]")
        sys.exit(1)

    task_arg = sys.argv[1]
    cwd_arg = sys.argv[2] if len(sys.argv) > 2 else "/workspace"
    result = call_claude_code(task=task_arg, cwd=cwd_arg)
    print(json.dumps(result, indent=2, ensure_ascii=False))
    sys.exit(0 if result["returncode"] == 0 else 1)
