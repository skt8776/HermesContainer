# CLAUDE.md

Guidance for Claude Code (and any AI assistant) operating inside this repository.

The repo is the **infrastructure layer** for running **Nous Research's Hermes Agent**, **OpenAI's Codex CLI**, and **Anthropic's Claude Code** together inside a single hardened Docker container with a **default-deny network firewall**. Hermes orchestrates; Claude Code executes code-editing tasks on delegation; Codex provides the ChatGPT Pro OAuth that backs Hermes's LLM calls.

The most common job for an AI assistant in this repo is **walking a new user from a fresh clone all the way to a running Hermes prompt**. The "Onboarding Walkthrough" section below is the script for that.

---

## Repo Layout

```
dev-container/
├── .devcontainer/
│   ├── Dockerfile           # Debian + Python 3.11 + Node 22 + Hermes + Codex + Claude Code
│   ├── init-firewall.sh     # iptables/ipset allowlist (adapted from Anthropic's Claude Code)
│   ├── entrypoint.sh        # Starts as root → runs firewall → chowns volumes → drops to hermes
│   ├── devcontainer.json    # VS Code/Cursor Dev Container config
│   └── skills/
│       └── claude_code/     # Template for Hermes→Claude Code delegation skill
├── run.sh                   # Unix/Git Bash launcher
├── run.bat                  # Windows CMD/PowerShell launcher
├── README.md                # User-facing docs
├── CLAUDE.md                # You are here
├── .gitignore
├── .gitattributes           # Force LF for *.sh, CRLF for *.bat
├── .env.example
└── <project-name>/          # User project folders (gitignored, created via `run.sh init`)
```

---

## Onboarding Walkthrough

When a user is starting from a fresh `git clone`, walk them through this sequence. **Do not skip steps** — each one was added to fix a real failure mode (see "Failure Modes Encountered" below).

### Step 0 — Prerequisites
- Docker Desktop is installed and **currently running** (`docker ps` succeeds).
- Host shell: PowerShell/CMD (use `run.bat`) or bash/Git Bash/WSL (use `run.sh`).
- User has at least one of: ChatGPT Plus/Pro subscription **or** OpenAI API key (for Hermes orchestration).
- User has at least one of: Claude Pro/Max subscription **or** Anthropic API key (for the Claude Code delegation skill).

### Step 1 — Build the image
```powershell
.\run.bat build
```
First build pulls Debian, Node 22, Python 3.11, installs Hermes + Codex + Claude Code + openai-oauth. Expect 2–5 minutes.

### Step 2 — Pick a project folder
```powershell
.\run.bat init <project-name>
```
- If the folder exists, it's reused.
- If new, it's created with a stub README.
- Either way, the folder is appended to `.gitignore` and recorded in `.current-project`.
- **Do not** bind-mount user projects manually — always go through `init` so gitignore stays in sync.

### Step 3 — Codex login (ChatGPT Pro OAuth)
```powershell
.\run.bat login
```
- Uses **device-auth** flow by default (`codex login --device-auth`).
- Prints a URL (`https://auth.openai.com/codex/device`) and a code like `XXXX-YYYY`.
- User opens the URL in their host browser, signs in to ChatGPT, enters the code.
- On success, the CLI prints "Successfully logged in" and exits.
- Tokens persist in the `hermes-codex-auth` Docker volume.

**Why device-auth not browser callback:** The browser callback flow on `localhost:1455` is fragile across Docker Desktop / WSL / Windows networking and was producing `ERR_EMPTY_RESPONSE`. Device-auth needs no port forwarding and works everywhere.

### Step 4 — Claude Code login (Claude Pro/Max OAuth)
```powershell
.\run.bat claude-login
```
- Browser-based OAuth flow. After authorizing in the browser, the CLI asks "paste code here if prompted".
- The paste prompt does not accept Ctrl+V from PowerShell (see "Failure Modes Encountered" below). **Type the short code by hand** — fastest path.
- Tokens persist in the `hermes-claude-auth` Docker volume at `/home/hermes/.claude/.credentials.json`.

**Sanity check** — `claude login` *always* re-prompts even when already authenticated, which makes it look like login isn't persisting. To verify auth without re-prompting:
```powershell
.\run.bat claude-status
# Expected output (when logged in):
#   { "loggedIn": true, "subscriptionType": "max", ... }
```
A user reporting "I logged in but next time it asks me to log in again" is almost certainly running `claude-login` repeatedly. Tell them to use `claude-status` instead, or just run `claude` (which uses cached creds without prompting).

### Step 5 — Install the Claude Code delegation skill
```powershell
.\run.bat install-claude-skill
```
Copies `/opt/hermes-skills/claude_code/` (baked into the image) into `~/.hermes/skills/claude_code/` (in the persistent volume). Hermes will pick it up on its next start.

### Step 6 — Hermes setup wizard
```powershell
.\run.bat setup
```
- When asked for an LLM provider, choose **"Custom OpenAI-compatible endpoint"**.
- Base URL: `http://localhost:10531/v1`
- API key: any non-empty string (e.g. `chatgpt`) — the local `openai-oauth` proxy substitutes the real OAuth token.
- Skip provider questions you don't need; Hermes setup is forgiving.

### Step 7 — (Optional) Discord/Slack gateway
```powershell
.\run.bat gateway-setup
```
Provides `hermes gateway` interactively. Bot tokens come from Discord Developer Portal / Slack App settings.

### Step 8 — Run
```powershell
# One-shot interactive (typical first run):
.\run.bat run

# Long-running for Discord/Slack/cron-style workflows:
.\run.bat up
.\run.bat attach     # shell into the running container
.\run.bat logs       # tail OAuth proxy and gateway logs
.\run.bat stop
```

---

## Failure Modes Encountered

These are real issues we hit while bringing the container up; the fixes are committed but the symptoms still surface in fresh environments. When a user reports any of these, jump straight to the resolution.

### Permission denied (os error 13) on `codex login` or any first-time write
**Symptom:**
```
WARNING: proceeding, even though we could not update PATH: Permission denied (os error 13)
Error loading configuration: Permission denied (os error 13)
```
**Cause:** Docker named volumes default to `root:root` ownership. The container drops to the unprivileged `hermes` user (uid 1000), which then cannot write into `/home/hermes/.codex`, `~/.claude`, `~/.hermes`, `~/.ssh`, or `/commandhistory`.
**Fix in code:** `entrypoint.sh` runs `chown -R hermes:hermes` over each persistent mount point before exec'ing into the user shell. The `CHOWN` capability is granted in the runtime args specifically for this.
**If a user still hits this:** they probably have stale volumes from before the fix. Have them run:
```powershell
docker volume rm hermes-codex-auth hermes-claude-auth hermes-home hermes-ssh hermes-bash-history
```
Then start over from `run.bat login`.

### `ERR_EMPTY_RESPONSE` on the OAuth callback
**Symptom:** Browser opens to the callback URL (`http://localhost:1455/auth/callback?code=...`) and shows `localhost에서 전송한 데이터가 없습니다 / ERR_EMPTY_RESPONSE`.
**Cause #1 (firewall):** The container's INPUT default policy is DROP. Inbound traffic to forwarded ports was being silently killed.
**Fix in code:** `init-firewall.sh` now ACCEPTs INPUT on the OAuth and proxy ports (1455, 54545, 10531, 8090).
**Cause #2 (port forwarding gaps):** Docker Desktop / WSL2 / Windows networking sometimes drops the loopback forwarding even when the rule is in place.
**Fix in code:** `codex login` uses `--device-auth` instead of the browser-callback flow. No callback means no callback failure.
**For Claude Code login**, if the browser flow fails the same way, route the user through `claude /login` inside an interactive container shell to paste an API key.

### `codex login` hangs after printing the URL
**Symptom:** URL is printed, terminal sits there forever even after the user authenticates in their browser.
**Cause:** Same as above — callback never made it back to the container.
**Fix:** Cancel with Ctrl+C and re-run with the current `run.sh`/`run.bat`, which uses `--device-auth` by default.

### Hermes setup wizard cannot reach `localhost:10531`
**Symptom:** Setup wizard says it can't validate the OpenAI-compatible endpoint.
**Cause:** The `openai-oauth` proxy is not running. `setup` is one-shot and doesn't auto-start the proxy.
**Fix:** Save the wizard with placeholder values (the wizard accepts unreachable endpoints), then start the long-running container with `.\run.bat run` or `.\run.bat up` — both auto-launch `openai-oauth` in the background before Hermes itself starts.

### `docker build` fails with apt GPG errors
**Symptom:** `NO_PUBKEY 62D54FD4003F6525` or similar from yarn repository.
**Cause:** The base image ships with a stale yarn apt source.
**Fix in code:** The Dockerfile removes `/etc/apt/sources.list.d/yarn.list` before its own `apt-get update`.

### Paste (Ctrl+V / right-click) doesn't work, especially in Claude Code
**Symptom:** User pastes from Windows clipboard with `Ctrl+V`, right-click, or `Shift+Insert` and nothing happens — or only the first line of a multi-line paste lands. Worst case: the OAuth code prompt during `claude login` won't accept any paste at all.

**Two layers, three workarounds:**

1. **At bash prompt** — bash's default `quoted-insert` binding on `Ctrl+V` swallows pasted text.
   **Fix in code:** `/home/hermes/.bashrc` and `/home/hermes/.inputrc` are baked into the image. They unbind `Ctrl+V` and enable bracketed-paste mode. After a fresh build, paste works in Windows Terminal (Ctrl+V, right-click, Shift+Insert).
   **If a user is on legacy `cmd.exe`:** only right-click works (with QuickEdit). Tell them to switch to Windows Terminal.

2. **Inside Claude Code's TUI (general text)** — Claude Code captures the terminal and handles input itself. Direct paste sometimes fails for multi-line content or special characters. Use the clipboard bridge:
   - Host (PowerShell): `Get-Clipboard | Out-File -Encoding utf8 .clipboard`
   - Container: `cb` (cat clipboard), `cb | claude -p` (one-shot prompt), or reference `@/workspace/.clipboard` from inside the `claude` TUI.
   - The other direction: `echo "..." | cbset` writes to `/workspace/.clipboard`.
   - The `.clipboard` file is gitignored.

3. **OAuth code prompt during `claude login` (the hard case)** — the "paste code here if prompted" prompt during Claude Code login does not accept paste from PowerShell/CMD on Windows.

   **Root cause analysis** (so future Claude doesn't waste time re-investigating):
   - Claude Code is built on Ink (React for terminals). Ink relies on **bracketed paste mode**: the terminal wraps pasted content in `\e[200~ ... \e[201~` so the app can detect a paste event vs. fast typing.
   - On a host shell (macOS Terminal, native Linux), the chain is `Terminal → claude`. Bracketed paste round-trips correctly.
   - Inside our container launched from PowerShell, the chain is `Windows Terminal → docker.exe (ConPTY) → Docker Desktop Linux VM → container PTY → claude`. The Windows ConPTY ↔ Linux PTY bridge **does not preserve bracketed paste escape sequences**. Claude enables bracketed paste mode (sends `\e[?2004h`), but Windows Terminal never sees the enable, so it never wraps the paste, so Claude only sees rapid keystrokes — and the OAuth prompt's input handler treats that as raw typing that gets eaten or fragmented.
   - Changing the container's base OS (Debian → Ubuntu/Alpine) does **not** help. The bottleneck is the Windows-side TTY chain, not the container.

   **Workarounds, in order of effectiveness:**
   1. **Run from WSL2 instead of PowerShell.** This is the only fix that addresses the root cause. From an Ubuntu/Debian WSL2 shell, run `./run.sh claude-login`. The TTY chain becomes `Windows Terminal → WSL2 bash → docker (Linux client) → container`, all Linux PTYs end-to-end, bracketed paste survives, paste works.
   2. **Type the OAuth code manually.** Codes are short (≤30 chars), takes about 30 seconds. Reliable everywhere.
   3. **Try `Shift+Insert` or middle-mouse-click** in Windows Terminal. A few users report these work where `Ctrl+V` does not, presumably because they take a different code path.
   4. **Last resort:** drop into `./run.sh start`, then run `claude /login` manually inside that exact session.

   The clipboard bridge (`cb`) **does not help here** — Claude is blocking on stdin, so piping text in via another command cannot reach the prompt.

**Do not** add API-key based auth as a workaround unless the user explicitly asks. The user has stated they want to keep OAuth for subscription billing.
**Do not** add a `claude-token` / `setup-token` launcher — that prompt has the same paste limitation and the user already declined it.

### Container can reach `auth.openai.com` but not `chatgpt.com`
**Symptom:** Login starts but device-auth code-redemption page won't load.
**Cause:** Allowlist miss. Both domains are needed (auth handles login, chatgpt handles the device-code page, the OAuth proxy talks to chatgpt.com/backend-api).
**Fix in code:** Both `auth.openai.com` and `chatgpt.com` are in the allowlist.
**If a user reports a missed domain:** add it to the `for domain in` loop in `init-firewall.sh` and rebuild.

---

## Conventions

### Project Folders
- Project folders live at the repo root (`./<project-name>/`), never nested under `.devcontainer/`.
- `run.sh init` and `run.bat init` automatically append the folder to `.gitignore`.
- The `.current-project` file tracks the active project; it is gitignored.

### Container Security Model
- Container runs as non-root user `hermes` (uid 1000) via entrypoint privilege drop.
- `--cap-drop=ALL`, then minimal add-back: `NET_ADMIN` and `NET_RAW` (firewall), `CHOWN`/`SETUID`/`SETGID`/`DAC_OVERRIDE` (volume permissions and runuser).
- `--security-opt=no-new-privileges` blocks setuid escalation. Therefore: no sudo for the user. The firewall script runs as part of the entrypoint while we are still root, before the privilege drop.
- Network egress is default-DENY. The allowlist is in `init-firewall.sh`.
- Inbound on forwarded ports (1455, 54545, 10531, 8090) is explicitly ACCEPTed; everything else INPUT-DROPped by default policy.
- Persistent state lives in named Docker volumes (`hermes-codex-auth`, `hermes-claude-auth`, `hermes-home`, `hermes-ssh`, `hermes-bash-history`), never in the repo.

### OAuth & Credentials
- **OpenAI / ChatGPT Pro:** `codex login --device-auth` → tokens in `hermes-codex-auth` volume → bridged via `openai-oauth` on `localhost:10531` → Hermes calls `http://localhost:10531/v1`.
- **Anthropic / Claude Pro/Max:** `claude login` → tokens in `hermes-claude-auth` volume.
  - The Dockerfile sets `CLAUDE_CONFIG_DIR=/home/hermes/.claude` so Claude keeps its main config (`.claude.json`) and credentials in the same volume-mounted directory. Without this env var, Claude splits state between `~/.claude/` (volume) and `~/.claude.json` (home root, ephemeral); the missing main config makes `claude` interactive re-prompt for OAuth on every container restart even though `claude auth status` reports logged-in. Anthropic's reference devcontainer uses the same env var. See [issue #1736](https://github.com/anthropics/claude-code/issues/1736).
- **Never** commit API keys, OAuth tokens, or `.env` files.

### Hermes → Claude Code / Codex Delegation
- Hermes is the orchestrator (Discord/Slack gateways, multi-step workflows, conversation state).
- For code-editing work, Hermes invokes a coding agent via a skill:
  - `~/.hermes/skills/claude_code/skill.py` → `claude -p "<task>"` (Claude Pro/Max)
  - `~/.hermes/skills/codex/skill.py` → `codex exec --full-auto -C <cwd> "<task>"` (ChatGPT Pro/Plus)
- Each skill returns `{returncode, stdout, stderr, timed_out}` so Hermes can chain results.
- Claude Code uses its own permission model (`acceptEdits`, `plan`, `bypassPermissions`) and tool set (Read, Edit, Bash, Grep, Glob).
- Codex uses sandbox modes (`workspace-write` via `--full-auto`) and writes only inside `cwd` + any `add-dir` paths.
- Skill templates live at `/opt/hermes-skills/{claude_code,codex}/` in the image; copy to the user's Hermes home via:
  - `./run.sh install-claude-skill` — Claude Code only
  - `./run.sh install-codex-skill` — Codex only
  - `./run.sh install-skills` — both
- Hermes can choose per task: long careful refactors via Claude, tight command-execution loops via Codex, or split a workflow across both.

---

## Rules for Claude Code Operating Here

### DO
- Keep the firewall allowlist minimal. If the agent needs a new domain, add it to `init-firewall.sh` deliberately and explain the reason in the commit message.
- When adding a launcher command, add to **both** `run.sh` and `run.bat` so the Unix/Windows experience stays in parity.
- Use **ASCII-only content in `run.bat`** — Windows CP949 codepage corrupts Unicode (box-drawing characters, em-dashes, Korean text in REM lines, etc.) and breaks parsing.
- Keep `CLAUDE.md` and `README.md` in sync when changing structure or commands.
- Treat user project folders (e.g., `alcohol-service/`) as user-owned. Don't modify them unless explicitly asked.
- Prefer **device-auth or paste-API-key flows** over browser-callback OAuth in any new login command — callbacks are the most fragile part of this stack.

### DO NOT
- Don't remove `--security-opt=no-new-privileges`, `--cap-drop=ALL`, or the firewall entrypoint. These are load-bearing.
- Don't bypass the firewall (e.g., wiring `noshield` mode into scripts or docs as a normal flow). It exists only as a last-resort debugging escape hatch.
- Don't grant `sudo` privileges to the `hermes` user beyond what's already scoped. The entrypoint runs anything that needs root before the privilege drop.
- Don't commit `alcohol-service/` or any project folder. They are intentionally gitignored.
- Don't nest `.git/` inside project folders unless the user explicitly wants per-project versioning. Project folders are the user's domain.
- Don't try to "fix" the LF/CRLF warnings — `.gitattributes` enforces LF for `.sh` and CRLF for `.bat` deliberately.

---

## Common Tasks

| Task | Where to change |
|------|-----------------|
| Allow a new domain | `.devcontainer/init-firewall.sh` (add to the `for domain in` loop) |
| Open a new inbound port | `.devcontainer/init-firewall.sh` (add `iptables -A INPUT -p tcp --dport <n> -j ACCEPT`) |
| Add a launcher command | Both `run.sh` (case statement) and `run.bat` (goto dispatch) |
| Change resource limits | `runArgs` in `devcontainer.json` and `HARDENING` in both launchers |
| Change deployment target | `DEPLOY_HOST` env var (default `general-01.kimys.net`) |
| Update Hermes/Codex/Claude Code version | Rebuild the image; latest is pulled by the install scripts and npm |
| Change Claude Code skill API | `.devcontainer/skills/claude_code/skill.py`, then re-run `install-claude-skill` |
| Add a new Hermes skill | Create `.devcontainer/skills/<name>/`, mirror the install pattern |

---

## Testing Changes

After modifying firewall, Dockerfile, or entrypoint:

```bash
./run.sh build
./run.sh start    # firewall verification prints, then drops to hermes shell
```

The basic sanity check is:
- `PASS: example.com blocked as expected`
- `PASS: api.github.com reachable as expected`
- `PASS: api.openai.com reachable`

If any of those fail, the firewall is broken and downstream onboarding will fail too.

For a deeper smoke test:
```bash
./run.sh start
# inside the container:
codex --version       # should print version
claude --version      # should print version
hermes --version      # should print version
ls /opt/hermes-skills # should show claude_code/ template
```
