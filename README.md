# Hermes Agent Hardened Dev Container

A sandboxed Docker container for running [Nous Research's Hermes Agent](https://github.com/NousResearch/hermes-agent) with [OpenAI's Codex CLI](https://github.com/openai/codex) under a strict network firewall — safe enough to let AI agents modify, test, and deploy your projects.

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
    └── Hermes Agent          → calls localhost:10531/v1, subscription billing
             │
             └── operates on → /workspace/<your-project>/
```

The firewall allowlist is adapted from [Anthropic's Claude Code devcontainer](https://github.com/anthropics/claude-code/tree/main/.devcontainer).

## Prerequisites

- **Docker Desktop** (Windows/macOS) or Docker Engine (Linux)
- A **ChatGPT Plus or Pro** subscription (for OAuth)
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

### 3. One-time: Codex OAuth login

```bash
./run.sh login
# A URL + device code will be printed. Open the URL in your host browser and enter the code.
# The token is stored in a Docker volume and reused across container runs.
```

### 4. Configure Hermes (interactive wizard)

```bash
./run.sh setup
# When asked for an LLM provider, choose "Custom OpenAI-compatible endpoint"
# Base URL:  http://localhost:10531/v1
# API key:   any non-empty string (the proxy replaces it with your OAuth token)
```

### 5. (Optional) Configure Discord/Slack gateway

```bash
./run.sh gateway-setup
# Provide bot tokens from Discord Developer Portal / Slack App settings.
```

### 6. Run the agent

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
| `login` | Codex OAuth login (one-time per host) |
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

**"Container already running" when calling `up`**
```bash
./run.sh stop
./run.sh up
```

**Firewall is too restrictive (a legitimate domain is blocked)**
Edit `.devcontainer/init-firewall.sh`, add the domain to the `for domain in` loop, then `./run.sh build` to rebuild.

**Codex login browser isn't opening**
The CLI uses device-code flow in headless environments. Copy the printed URL to your host browser manually.

**Hermes can't reach the OpenAI proxy**
Check `./run.sh logs` for openai-oauth output. The proxy needs an active Codex login — re-run `./run.sh login` if tokens expired.

## License and Credits

- Firewall script adapted from [Anthropic / claude-code](https://github.com/anthropics/claude-code) (MIT)
- Hermes Agent by [Nous Research](https://github.com/NousResearch/hermes-agent) (MIT)
- Codex CLI by [OpenAI](https://github.com/openai/codex) (Apache-2.0)

This repository is the composition/configuration layer; see each upstream for their respective licenses.
