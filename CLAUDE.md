# CLAUDE.md

Guidance for Claude Code when operating inside this repository.

## What This Repo Is

A hardened Docker dev container that runs **Nous Research's Hermes Agent** and **OpenAI's Codex CLI** with a **default-deny network firewall**. The container serves as a sandboxed harness so AI agents can work on user projects without full host access or unrestricted internet.

## Repo Layout

```
dev-container/
├── .devcontainer/
│   ├── Dockerfile           # Debian + Python 3.11 + Node 22 + Hermes + Codex
│   ├── init-firewall.sh     # iptables/ipset allowlist (adapted from Anthropic's Claude Code)
│   ├── entrypoint.sh        # Starts as root → runs firewall → drops to hermes user
│   └── devcontainer.json    # VS Code/Cursor Dev Container config
├── run.sh                   # Unix/Git Bash launcher
├── run.bat                  # Windows CMD/PowerShell launcher
├── README.md                # User-facing docs
├── CLAUDE.md                # You are here
├── .gitignore
├── .env.example
└── <project-name>/          # User project folders (gitignored, created via `run.sh init`)
```

## Core Conventions

### Project Folders
- **Project folders live at the repo root** (`./<project-name>/`), never nested under `.devcontainer/`.
- Each project folder is automatically added to `.gitignore` by `run.sh init <name>`.
- `alcohol-service/` is one such project folder. It is **not** part of this infra repo.
- The `.current-project` file tracks the active project and is gitignored.

### Container Security Model
- Container runs as non-root user `hermes` (uid 1000) via entrypoint privilege drop.
- All Linux capabilities are dropped except those needed for firewall setup (`NET_ADMIN`, `NET_RAW`) and standard file operations (`CHOWN`, `SETUID`, `SETGID`, `DAC_OVERRIDE`).
- `no-new-privileges` prevents setuid escalation.
- Network egress is default-deny with an explicit allowlist defined in `.devcontainer/init-firewall.sh`.
- Persistent state lives in named Docker volumes (`hermes-codex-auth`, `hermes-home`, `hermes-ssh`, `hermes-bash-history`), never in the repo.

### OAuth & Credentials
- OpenAI access uses **Codex CLI OAuth** (`codex login`) tied to a ChatGPT Pro subscription.
- The OAuth token is stored in the `hermes-codex-auth` volume and bridged to a local OpenAI-compatible proxy via `openai-oauth` on port 10531.
- Hermes is configured to call `http://localhost:10531/v1` as its OpenAI endpoint.
- **Never** commit API keys, OAuth tokens, or `.env` files.

## Rules for Claude Code

### DO
- Keep the firewall allowlist minimal. If the agent needs a new domain, add it deliberately to `init-firewall.sh` and explain why.
- When creating new launcher commands, add to **both** `run.sh` and `run.bat` to maintain parity.
- Use ASCII-only content in `run.bat` (Windows CP949 codepage breaks on Unicode box-drawing characters and other non-ASCII content).
- Keep `CLAUDE.md` and `README.md` in sync when changing structure or commands.
- Treat project folders (e.g., `alcohol-service/`) as user-owned. Do not modify them unless explicitly asked to work on that project.

### DO NOT
- Do not remove `--security-opt=no-new-privileges`, `--cap-drop=ALL`, or the firewall entrypoint. These are load-bearing for the security model.
- Do not bypass the firewall (e.g., by using `noshield` mode) in scripts or documented flows. `noshield` is a last-resort debug command.
- Do not add `sudo` privileges to `hermes` beyond what's already scoped (only `init-firewall.sh`).
- Do not commit `alcohol-service/` or any project folder to git.
- Do not nest `.git/` inside project folders if they are meant to remain gitignored here — if a project needs its own versioning, that is the user's decision.

## Common Tasks

| Task | Where to change |
|------|-----------------|
| Allow a new domain | `.devcontainer/init-firewall.sh` (add to the `for domain in` loop) |
| Add a launcher command | Both `run.sh` (case statement) and `run.bat` (goto dispatch) |
| Change resource limits | `runArgs` in `devcontainer.json` and `HARDENING` in both launchers |
| Change deployment target | `DEPLOY_HOST` env var (defaults to `general-01.kimys.net`) |
| Update Hermes/Codex version | Rebuild the image; latest is pulled by the install script |

## Testing Changes

After modifying firewall, Dockerfile, or entrypoint:

```bash
./run.sh build
./run.sh start    # should print firewall verification output and drop to hermes shell
```

If the firewall output shows `PASS: example.com blocked` and `PASS: api.github.com reachable`, the basic isolation is intact.
