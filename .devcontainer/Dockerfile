# Hermes Agent + Codex CLI Dev Container
# - Nous Research Hermes Agent (self-improving AI agent)
# - OpenAI Codex CLI (for ChatGPT Pro OAuth)
# - openai-oauth (bridges Codex tokens → OpenAI-compatible endpoint)

FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

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

# ─── OpenAI Codex CLI (ChatGPT Pro OAuth) ─────────────────────────────────
RUN npm install -g @openai/codex

# ─── Anthropic Claude Code (Claude Pro/Max OAuth) ─────────────────────────
# Hermes delegates actual code edits to Claude Code via subprocess.
RUN npm install -g @anthropic-ai/claude-code

# ─── openai-oauth (bridges Codex tokens to OpenAI-compatible endpoint) ────
# This lets Hermes use ChatGPT Pro subscription via localhost proxy
RUN npm install -g openai-oauth || echo "openai-oauth install failed, will install at runtime"

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
    && CI=1 HERMES_NO_WIZARD=1 bash /tmp/hermes-install.sh || echo "Hermes install completed (wizard skipped)" \
    && rm -f /tmp/hermes-install.sh

ENV PATH="/home/${USERNAME}/.local/bin:${PATH}"

# ─── Entrypoint: starts as root → runs firewall → drops to hermes ─────────
# This design keeps --security-opt=no-new-privileges compatible with sudo-less setup.
USER root
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD []
