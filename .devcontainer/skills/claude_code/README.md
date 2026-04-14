# Claude Code Skill

Delegates coding tasks from Hermes Agent to Claude Code via subprocess.

## Why This Exists

Hermes Agent (running on ChatGPT Pro) is the **orchestrator** — it decides
what needs to happen, when, and coordinates workflows. Claude Code (running
on Claude Pro/Max) is the **executor** for actual code modification work,
using its own strong tools (Read/Edit/Bash/Grep/Glob) and its own permission
model.

## Setup

1. `./run.sh claude-login` — authorize Claude Pro/Max via OAuth
2. `./run.sh install-claude-skill` — copy this skill into `~/.hermes/skills/`
3. Restart Hermes so it picks up the new skill

## Public API

```python
from skills.claude_code.skill import call_claude_code

result = call_claude_code(
    task="Refactor backend/api/chat_routes.py to extract session management",
    cwd="/workspace/alcohol-service",
    permission_mode="acceptEdits",
    allowed_tools=["Read", "Edit", "Grep", "Glob"],  # optional
    timeout=600,
)

# result: { "returncode": 0, "stdout": "...", "stderr": "...", "timed_out": False }
```

## Permission Modes

| Mode | Behavior |
|------|----------|
| `default` | Claude asks before each tool use (interactive) |
| `acceptEdits` | Auto-accept file edits, ask for other tools |
| `plan` | Read-only planning mode (no writes, no shell) |
| `bypassPermissions` | Skip all prompts (dangerous — avoid in automation) |

## Security Notes

- Claude Code respects the container's filesystem and network firewall.
- `cwd` is clamped inside `/workspace`; passing paths outside has no effect
  because the container bind-mount is the boundary.
- Claude Code's shell tool inherits the firewall — it cannot reach hosts
  outside the allowlist configured in `init-firewall.sh`.

## Direct CLI Invocation

You can also call the skill directly without going through Hermes:

```bash
python ~/.hermes/skills/claude_code/skill.py "Fix the N+1 query in users.py" /workspace/alcohol-service
```
