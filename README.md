# Hermes Agent Hardened Dev Container

A sandboxed Docker container for running [Nous Research's Hermes Agent](https://github.com/NousResearch/hermes-agent), [OpenAI's Codex CLI](https://github.com/openai/codex), and [Anthropic's Claude Code](https://github.com/anthropics/claude-code) together under a strict network firewall — safe enough to let AI agents modify, test, and deploy your projects.

## Why This Exists

Running an autonomous agent on your host machine means trusting it with your entire filesystem, credentials, and network. This repo provides a harness so you can:

- Give the agent a project to work on, without giving it the rest of your machine.
- Limit outbound network access to a curated allowlist (OpenAI APIs, GitHub, npm, your deploy server — nothing else).
- Use your **ChatGPT Pro subscription** via Codex OAuth instead of pay-as-you-go API billing.
- Wire the agent to Discord/Slack for remote interaction when it's running headless.

## Architecture

```
[Your Machine]
    │
    ▼
[Docker Container: hardened]
    │  - non-root user `hermes`, capabilities dropped
    │  - default-deny egress firewall (iptables + ipset)
    │  - no-new-privileges, pids/memory/cpu limits
    │
    ├── Codex CLI             → ChatGPT Pro OAuth (browser device-code flow)
    ├── openai-oauth proxy    → localhost:10531 (bridges OAuth → OpenAI API shape)
    ├── Claude Code CLI       → Claude Pro/Max OAuth (separate browser flow)
    └── Hermes Agent          → orchestrator
             │
             ├── LLM calls → localhost:10531/v1 (ChatGPT Pro subscription)
             ├── Delegation → `claude -p "<task>"` subprocess (Claude Pro/Max)
             └── operates on → /workspace/<your-project>/
```

**Role split:** Hermes is the orchestrator (Discord/Slack gateways, workflows,
long-running tasks). Claude Code is the code-editing executor, called by
Hermes on demand via the `claude_code` skill. This lets you use both
subscriptions for what each does best.

The firewall allowlist is adapted from [Anthropic's Claude Code devcontainer](https://github.com/anthropics/claude-code/tree/main/.devcontainer).

## Prerequisites

- **Docker Desktop** (Windows/macOS) or Docker Engine (Linux)
- A **ChatGPT Plus or Pro** subscription (for Codex OAuth — Hermes orchestration LLM)
- A **Claude Pro or Max** subscription (for Claude Code OAuth — code-editing executor)
- Optional: **VS Code** / **Cursor** with the [Dev Containers](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers) extension

## Quick Start

### 1. Build the image

```bash
# Unix / Git Bash / WSL
./run.sh build

# Windows PowerShell / CMD
.\run.bat build
```

### 2. Create or select a project

```bash
./run.sh init my-project          # creates ./my-project/ and adds it to .gitignore
./run.sh init alcohol-service     # reuses the existing folder
```

### 3. One-time: Codex OAuth login (ChatGPT Pro)

```bash
./run.sh login
# A URL + device code will be printed. Open the URL in your host browser and enter the code.
# The token is stored in a Docker volume and reused across container runs.
```

### 4. One-time: Claude Code OAuth login (Claude Pro/Max)

```bash
./run.sh claude-login
# Opens a browser flow similar to codex login.
# Tokens are stored in a separate `hermes-claude-auth` volume.
```

### 5. Install the Claude Code delegation skill

```bash
./run.sh install-claude-skill
# Copies the skill template from /opt/hermes-skills/claude_code/
# into your persistent Hermes home at ~/.hermes/skills/claude_code/.
```

### 6. Configure Hermes (interactive wizard)

```bash
./run.sh setup
# When asked for an LLM provider, choose "Custom OpenAI-compatible endpoint"
# Base URL:  http://localhost:10531/v1
# API key:   any non-empty string (the proxy replaces it with your OAuth token)
```

### 7. (Optional) Configure Discord/Slack gateway

```bash
./run.sh gateway-setup
# Provide bot tokens from Discord Developer Portal / Slack App settings.
```

### 8. Run the agent

```bash
# One-shot interactive session:
./run.sh run

# Long-running background (needed for Discord/Slack gateway):
./run.sh up         # detached start
./run.sh attach     # shell into the running container
./run.sh logs       # view gateway and OAuth proxy logs
./run.sh stop       # shut down
```

## Command Reference

| Command | Description |
|---------|-------------|
| `build` | Build the Docker image |
| `init <name>` | Create or select a project folder (auto-gitignored) |
| `login` | Codex OAuth login — ChatGPT Pro (one-time per host) |
| `claude-login` | Claude Code OAuth login — Claude Pro/Max (one-time per host) |
| `install-claude-skill` | Copy the Claude Code delegation skill into Hermes |
| `setup` | Hermes setup wizard |
| `gateway-setup` | Configure Discord / Slack / WhatsApp gateway |
| `up` | Start long-running container (OAuth proxy + gateway) |
| `attach` | Open shell in a running container |
| `logs` | View gateway + proxy logs |
| `stop` | Stop the long-running container |
| `run` | One-shot `hermes` session with OAuth proxy started |
| `start` | One-shot interactive shell |
| `noshield` | DEBUG ONLY — shell without firewall or hardening |

## Project Folders

Project folders live at the repo root (`./<project-name>/`) and are **excluded from this infrastructure repo's git history** via `.gitignore`. If you want to version a project separately, `cd` into its folder and `git init` there.

The active project is tracked by the `.current-project` file (also gitignored).

## Security Model

| Layer | Protection |
|-------|-----------|
| **User** | Non-root `hermes` (uid 1000), set via entrypoint privilege drop |
| **Capabilities** | `--cap-drop=ALL` then minimal add-back (`NET_ADMIN`/`NET_RAW` for firewall only) |
| **Privilege escalation** | `--security-opt=no-new-privileges` |
| **Resources** | `--pids-limit=1024 --memory=6g --cpus=3` |
| **Network egress** | iptables default-DROP + ipset allowlist (see `init-firewall.sh`) |
| **Ports exposed to host** | `127.0.0.1` only (10531, 8090) — not reachable from your LAN |
| **Filesystem** | Only `/workspace` is bind-mounted; Codex/Hermes/SSH state in named volumes |

See `CLAUDE.md` for internal conventions and `.devcontainer/init-firewall.sh` for the full domain allowlist.

## Using with VS Code / Cursor

Open the repo folder in VS Code or Cursor, then:

1. `Ctrl+Shift+P` → **Dev Containers: Reopen in Container**
2. Wait for the image to build (first time) and firewall to initialize.
3. Run `codex login`, `hermes setup`, `hermes` inside the integrated terminal.

## Troubleshooting

### `Permission denied (os error 13)` during `codex login` / `claude login` / `hermes setup`

**Symptom:**
```
WARNING: proceeding, even though we could not update PATH: Permission denied (os error 13)
Error loading configuration: Permission denied (os error 13)
```

**Cause:** Stale Docker volumes left over from a previous build are owned by `root:root`, but the container now runs as the `hermes` user (uid 1000) and cannot write into them.

**Fix:** remove the stale volumes (no real auth tokens lost — they could not have been written in the first place):
```powershell
docker volume rm hermes-codex-auth hermes-claude-auth hermes-home hermes-ssh hermes-bash-history
```
Then re-run `.\run.bat login`. The current `entrypoint.sh` `chown`s the mount points on every container start, so this only happens with volumes created before that fix landed.

### `ERR_EMPTY_RESPONSE` after authenticating in the browser

**Symptom:** You opened the OAuth URL, signed in, and the redirect to `http://localhost:1455/auth/callback?code=...` shows "localhost에서 전송한 데이터가 없습니다 / ERR_EMPTY_RESPONSE". The terminal still says "Starting local login server".

**Cause:** Browser-callback OAuth across Docker Desktop / WSL / Windows networking is fragile. Even with port forwarding, packets sometimes get dropped between the host network stack and the container.

**Fix:** Cancel with **Ctrl+C** and re-run. The current `run.sh` / `run.bat` use **device-code** flow for `codex login` (no callback needed — you paste a short code on the browser):
```powershell
.\run.bat login
# Output:
#   Open: https://auth.openai.com/codex/device
#   Code: XXXX-YYYY
```

For `claude login`, if the embedded browser flow fails the same way, use the API-key fallback:
```powershell
.\run.bat start
# inside the container:
claude
/login            # then paste an API key from console.anthropic.com
```

### `codex login` hangs after printing the URL

Same root cause as `ERR_EMPTY_RESPONSE` above. Cancel with **Ctrl+C** and use the current launcher (`./run.sh login` / `.\run.bat login`) which already uses device-auth.

### `docker build` fails with apt GPG `NO_PUBKEY` errors

The base devcontainers image ships with a stale yarn apt source. The Dockerfile already removes `/etc/apt/sources.list.d/yarn.list` before its own `apt-get update` — if you still hit this, you're likely on an old image. Run `docker system prune -a` and rebuild.

### Hermes setup cannot validate `localhost:10531`

The OAuth proxy (`openai-oauth`) is not running yet because `setup` is one-shot. Save the wizard with the placeholder values anyway — the wizard accepts unreachable endpoints. The proxy is auto-started on every `.\run.bat run` and `.\run.bat up`.

### Container "already running" when calling `up`

```powershell
.\run.bat stop
.\run.bat up
```

### A legitimate domain is blocked by the firewall

Edit `.devcontainer/init-firewall.sh`, add the domain to the `for domain in` loop, then:
```powershell
.\run.bat build
```

### Hermes can't reach the OpenAI proxy

Check `.\run.bat logs` for openai-oauth output. The proxy needs an active Codex login — re-run `.\run.bat login` if tokens expired (about every 30 days).

## License and Credits

- Firewall script adapted from [Anthropic / claude-code](https://github.com/anthropics/claude-code) (MIT)
- Hermes Agent by [Nous Research](https://github.com/NousResearch/hermes-agent) (MIT)
- Codex CLI by [OpenAI](https://github.com/openai/codex) (Apache-2.0)
- Claude Code by [Anthropic](https://github.com/anthropics/claude-code) (proprietary, see Anthropic's terms)
- `openai-oauth` proxy by [EvanZhouDev](https://github.com/EvanZhouDev/openai-oauth) (MIT)

This repository is the composition/configuration layer; see each upstream for their respective licenses and terms of use. Using ChatGPT subscription tokens through `openai-oauth` is a community workaround — review OpenAI's terms before relying on it for anything beyond personal experimentation.
