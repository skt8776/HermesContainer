# Codex CLI Skill

Delegates coding tasks from Hermes Agent to OpenAI Codex CLI via subprocess.

## Why This Exists

Hermes Agent (running on ChatGPT Pro via the openai-oauth proxy) can
orchestrate workflows, but for actual code-editing it's usually better
to delegate to a purpose-built coding agent. This container ships two
such agents:

- **Claude Code** (`claude_code` skill) — Anthropic's coding agent,
  uses Claude Pro/Max OAuth.
- **Codex** (`codex` skill, this one) — OpenAI's coding agent,
  uses ChatGPT Pro/Plus OAuth.

You can invoke either from Hermes depending on which model fits the
task or which subscription you want to spend on.

## Setup

1. `./run.sh login` — authorize ChatGPT Pro/Plus via Codex OAuth
2. `./run.sh install-codex-skill` — copy this skill into `~/.hermes/skills/`
3. Restart Hermes so it picks up the new skill

## Public API

```python
from skills.codex.skill import call_codex

result = call_codex(
    task="Replace in-memory session dict with Redis in chat_routes.py",
    cwd="/workspace/alcohol-service",
    full_auto=True,            # sandboxed automatic execution, no prompts
    skip_git_check=True,       # allow running outside a git repo
    timeout=900,
    additional_dirs=None,      # optional: extra writable directories
    json_output=False,         # set True to get JSONL event stream
    ephemeral=False,           # set True to skip persisting session files
)

# result: { "returncode": 0, "stdout": "...", "stderr": "...", "timed_out": False }
```

## Default Behavior

The skill runs `codex exec --full-auto --skip-git-repo-check -C <cwd> <task>` by
default. `--full-auto` enables sandboxed automatic execution so Codex
runs commands in a workspace-write sandbox without prompting for
approval per action — appropriate for delegation from another agent.

## Security Notes

- Codex respects the container's filesystem and network firewall.
- `--full-auto` keeps Codex's sandboxed write scope to `cwd` (and any
  `additional_dirs` you grant). Pass paths under `/workspace` only.
- Codex's shell tool inherits the firewall — it cannot reach hosts
  outside the allowlist configured in `init-firewall.sh`.
- `--dangerously-bypass-approvals-and-sandbox` is intentionally NOT
  exposed by this skill; the container itself is the outer sandbox,
  but skipping Codex's inner sandbox would still let runaway code run
  arbitrary commands inside it.

## Direct CLI Invocation

You can also call the skill directly without going through Hermes:

```bash
python ~/.hermes/skills/codex/skill.py "Fix the N+1 query in users.py" /workspace/alcohol-service
```

## Comparison with Claude Code Skill

| Aspect | `claude_code` | `codex` |
|--------|--------------|---------|
| Backing model | Claude (Pro/Max) | GPT (ChatGPT Pro/Plus) |
| Auth | `claude login` | `codex login` |
| Per-call command | `claude -p` | `codex exec` |
| Permission flags | `--permission-mode acceptEdits` | `--full-auto` |
| Tool restriction | `--allowed-tools "Read,Edit"` | (governed by sandbox + add-dir) |
| Best for | Long context, careful edits | Tight loops, command execution |
