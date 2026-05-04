# Hermes Agent + Codex CLI Dev Container
# - Nous Research Hermes Agent (self-improving AI agent)
# - OpenAI Codex CLI (for ChatGPT Pro OAuth)
# - openai-oauth (bridges Codex tokens → OpenAI-compatible endpoint)

FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    # Tell Claude Code to keep ALL its state inside this directory.
    # Without this, Claude splits state between ~/.claude/ (volume) and
    # ~/.claude.json (home root, not in volume), so credentials persist
    # but onboarding/login state doesn't, and `claude` interactive
    # re-prompts for OAuth on every container start.
    # This is Anthropic's official solution — see their reference
    # devcontainer at github.com/anthropics/claude-code/.devcontainer
    CLAUDE_CONFIG_DIR=/home/hermes/.claude

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# ─── System dependencies (Hermes + firewall + deploy + everyday tools) ───
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Core
    ca-certificates \
    curl \
    wget \
    git \
    bash \
    sudo \
    # Build chain
    build-essential \
    pkg-config \
    libssl-dev \
    libffi-dev \
    # Python
    python3.11 \
    python3.11-venv \
    python3-pip \
    # Hermes runtime requirements
    ripgrep \
    ffmpeg \
    # Network / deployment
    openssh-client \
    rsync \
    gnupg \
    jq \
    # Firewall
    iptables \
    ipset \
    dnsutils \
    aggregate \
    iproute2 \
    # Everyday tools
    vim \
    nano \
    less \
    htop \
    tree \
    file \
    tmux \
    procps \
    psmisc \
    net-tools \
    bash-completion \
    man-db \
    unzip \
    zip \
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf /usr/bin/python3.11 /usr/local/bin/python \
    && ln -sf /usr/bin/python3.11 /usr/local/bin/python3

# ─── Node.js 22 LTS (Hermes requirement) ──────────────────────────────────
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/* \
    && node --version && npm --version

# ─── uv (fast Python package manager, used by Hermes) ─────────────────────
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

# (Global npm packages — codex, claude-code, openai-oauth — are installed
# as the hermes user further below, so the user can later run
# `npm install -g <pkg>` to upgrade without hitting EACCES on
# /usr/lib/node_modules.)

# ─── Playwright Chromium runtime dependencies ─────────────────────────────
# Hermes's installer runs `npx playwright install --with-deps chromium`,
# which shells out to `sudo apt-get install` for these libs. Our hermes
# user has sudo scoped only to init-firewall.sh, so --with-deps fails with
# "sudo: a password is required" and the installer prints
# "Playwright browser installation failed — browser tools will not work."
# We preinstall the system libs as root here, then strip --with-deps from
# the installer invocation below so the sudo path is skipped entirely.
# Package list matches `npx playwright install-deps --dry-run chromium`.
RUN apt-get update && apt-get install -y --no-install-recommends \
    libasound2 libatk-bridge2.0-0 libatk1.0-0 libatspi2.0-0 libcairo2 \
    libcups2 libdbus-1-3 libdrm2 libgbm1 libglib2.0-0 libnspr4 libnss3 \
    libpango-1.0-0 libx11-6 libxcb1 libxcomposite1 libxdamage1 libxext6 \
    libxfixes3 libxkbcommon0 libxrandr2 xvfb \
    fonts-noto-color-emoji fonts-unifont libfontconfig1 libfreetype6 \
    xfonts-scalable fonts-liberation fonts-ipafont-gothic fonts-wqy-zenhei \
    fonts-tlwg-loma-otf fonts-freefont-ttf \
    && rm -rf /var/lib/apt/lists/*

# ─── Skill templates (copied to ~/.hermes/skills/ via install-claude-skill) ─
COPY .devcontainer/skills /opt/hermes-skills

# ─── Create non-root user with restricted sudo (firewall script only) ─────
# User can only run the firewall init script as root, nothing else
ARG USERNAME=hermes
ARG USER_UID=1000
ARG USER_GID=1000
RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m -s /bin/bash $USERNAME \
    && echo "$USERNAME ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME

# Put hermes's user-local bin on PATH for ALL subsequent layers and at
# runtime. This is the npm global prefix (configured below) plus the spot
# where pip --user / Hermes installer drop binaries. Set BEFORE the npm
# install steps so the hermes RUN sees it.
ENV PATH="/home/${USERNAME}/.local/bin:${PATH}"

# ─── Global npm packages (installed as hermes, not root) ──────────────────
# Why as hermes: codex's auto-updater (and any user-initiated
# `npm install -g <pkg>`) would otherwise hit EACCES on /usr/lib/node_modules,
# which is owned by root. Using a hermes-writable prefix at ~/.local makes
# upgrades work with normal user permissions. PATH is set above, so the
# resulting bins (codex, claude, openai-oauth) are found at runtime.
USER $USERNAME
RUN mkdir -p /home/hermes/.local/lib /home/hermes/.local/bin \
    && npm config set prefix /home/hermes/.local

# OpenAI Codex CLI (ChatGPT Pro OAuth)
RUN npm install -g @openai/codex

# Anthropic Claude Code (Claude Pro/Max OAuth) — Hermes delegates
# actual code edits to Claude Code via subprocess.
RUN npm install -g @anthropic-ai/claude-code

# openai-oauth (bridges Codex tokens to OpenAI-compatible endpoint) —
# lets Hermes use ChatGPT Pro subscription via localhost proxy.
RUN npm install -g openai-oauth || echo "openai-oauth install failed, will install at runtime"

USER root

# ─── Dotfiles for the hermes user (paste-friendly bash + clipboard bridge) ─
# .bashrc / .inputrc enable bracketed paste mode and unbind Ctrl+V's
# quoted-insert so terminal paste actions reach the prompt.
# .local/bin/cb is a clipboard bridge for cases where TUIs (like Claude Code)
# don't accept direct paste — you stage clipboard content via a shared file.
COPY --chown=hermes:hermes .devcontainer/home/.bashrc       /home/hermes/.bashrc
COPY --chown=hermes:hermes .devcontainer/home/.inputrc      /home/hermes/.inputrc
COPY --chown=hermes:hermes .devcontainer/home/.local/bin/cb /home/hermes/.local/bin/cb
RUN chmod 755 /home/hermes/.local/bin/cb

# Install firewall and entrypoint scripts (owned by root)
COPY .devcontainer/init-firewall.sh /usr/local/bin/init-firewall.sh
COPY .devcontainer/entrypoint.sh    /usr/local/bin/entrypoint.sh
RUN chmod 755 /usr/local/bin/init-firewall.sh /usr/local/bin/entrypoint.sh \
    && chown root:root /usr/local/bin/init-firewall.sh /usr/local/bin/entrypoint.sh

# Install Hermes Agent as hermes user (non-interactive)
USER $USERNAME
WORKDIR /workspace

RUN curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh -o /tmp/hermes-install.sh \
    && chmod +x /tmp/hermes-install.sh \
    # Hermes installer reads prompts from `< /dev/tty` even with CI=1 set,
    # which fails in a Docker build (no controlling terminal). Strip the
    # explicit /dev/tty redirection so reads use stdin, then feed 'n' to
    # every prompt via process substitution (avoids SIGPIPE under pipefail).
    && sed -i 's|< /dev/tty||g' /tmp/hermes-install.sh \
    # Strip `--with-deps` from the Playwright install call. That flag makes
    # playwright shell out to `sudo apt-get install`, which fails here
    # because our hermes user's sudo is scoped to init-firewall.sh only.
    # The system libs are preinstalled as root above, so dropping the flag
    # lets `npx playwright install chromium` just download browsers as user.
    && sed -i 's|npx playwright install --with-deps chromium|npx playwright install chromium|g' /tmp/hermes-install.sh \
    && CI=1 HERMES_NO_WIZARD=1 NONINTERACTIVE=1 DEBIAN_FRONTEND=noninteractive \
       bash /tmp/hermes-install.sh < <(printf 'n\n%.0s' $(seq 1 200)) \
    && rm -f /tmp/hermes-install.sh \
    && test -x /home/hermes/.local/bin/hermes

USER root

# Move the hermes-agent code OUT of /home/hermes/.hermes/ (which becomes
# a Docker volume mount at runtime, hiding everything inside) into /opt/
# (which is part of the image and never volume-mounted). The runtime
# entrypoint re-injects a symlink so /home/hermes/.hermes/hermes-agent
# resolves to /opt/hermes-agent inside the volume.
RUN mv /home/hermes/.hermes/hermes-agent /opt/hermes-agent \
    && ln -s /opt/hermes-agent /home/hermes/.hermes/hermes-agent \
    && chown -h hermes:hermes /home/hermes/.hermes/hermes-agent

# Expose hermes (and other user-local binaries) on the standard PATH.
# runuser resets PATH to a compiled-in default (typically /usr/sbin:/usr/bin)
# for security, so without these symlinks the entrypoint's
#   exec runuser -u hermes -- hermes setup
# fails with "failed to execute hermes: No such file or directory".
RUN ln -sf /home/hermes/.local/bin/hermes       /usr/local/bin/hermes \
    && ln -sf /home/hermes/.local/bin/cb           /usr/local/bin/cb \
    && ln -sf /home/hermes/.local/bin/codex        /usr/local/bin/codex \
    && ln -sf /home/hermes/.local/bin/claude       /usr/local/bin/claude \
    && ln -sf /home/hermes/.local/bin/openai-oauth /usr/local/bin/openai-oauth \
    && /usr/local/bin/hermes --version \
    && /usr/local/bin/codex --version \
    && /usr/local/bin/claude --version

# ─── Entrypoint: starts as root → runs firewall → drops to hermes ─────────
# This design keeps --security-opt=no-new-privileges compatible with sudo-less setup.
USER root
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD []
