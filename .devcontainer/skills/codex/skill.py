"""Codex CLI delegation skill for Hermes Agent.

Lets Hermes delegate coding tasks to OpenAI Codex CLI via subprocess.
Codex runs with its own OAuth (ChatGPT Pro) and its own
sandboxed tool set.

Usage inside Hermes:
    from skills.codex.skill import call_codex
    result = call_codex(
        task="Refactor backend/api/chat_routes.py to extract session management",
        cwd="/workspace/alcohol-service",
    )
"""

from __future__ import annotations

import subprocess
from pathlib import Path

DEFAULT_TIMEOUT = 900  # 15 minutes
CODEX_BIN = "codex"


def call_codex(
    task: str,
    cwd: str | Path = "/workspace",
    *,
    timeout: int = DEFAULT_TIMEOUT,
    full_auto: bool = True,
    additional_dirs: list[str] | None = None,
    skip_git_check: bool = True,
    json_output: bool = False,
    ephemeral: bool = False,
) -> dict:
    """Delegate a task to Codex CLI.

    Args:
        task:             The prompt / task description for Codex.
        cwd:              Working directory for the Codex session.
                          Codex will operate within this subtree.
        timeout:          Max seconds before the subprocess is killed.
        full_auto:        --full-auto sandboxed automatic execution
                          (no per-action approval prompts; ideal for delegation).
        additional_dirs:  Additional writable directories (--add-dir).
        skip_git_check:   --skip-git-repo-check (allow non-git directories).
        json_output:      --json (JSONL event stream on stdout).
        ephemeral:        --ephemeral (don't persist session files to disk).

    Returns:
        {
            "returncode": int,
            "stdout": str,        # Codex's output (or JSONL events)
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

    cmd = [CODEX_BIN, "exec"]
    if full_auto:
        cmd.append("--full-auto")
    if skip_git_check:
        cmd.append("--skip-git-repo-check")
    if json_output:
        cmd.append("--json")
    if ephemeral:
        cmd.append("--ephemeral")
    cmd.extend(["-C", str(cwd_path)])
    if additional_dirs:
        for d in additional_dirs:
            cmd.extend(["--add-dir", d])
    cmd.append(task)

    try:
        proc = subprocess.run(
            cmd,
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
            "stderr": f"'{CODEX_BIN}' not found on PATH. Install with: npm install -g @openai/codex",
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
    result = call_codex(task=task_arg, cwd=cwd_arg)
    print(json.dumps(result, indent=2, ensure_ascii=False))
    sys.exit(0 if result["returncode"] == 0 else 1)
