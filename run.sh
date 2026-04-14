#!/bin/bash
# Hermes Agent Hardened Dev Container Launcher
#
# Container lifecycle:
#   - Ephemeral commands (login/setup): new container per run, auto-removed on exit
#   - Long-running (up/gateway): named detached container for background services
#   - Attach: exec into a running container
#
# Usage:
#   ./run.sh build                 - Build image
#   ./run.sh init <name>           - Create or select a project folder
#   ./run.sh login                 - Codex OAuth (ChatGPT Pro)
#   ./run.sh claude-login          - Claude Code OAuth (always re-prompts)
#   ./run.sh claude-status         - Check Claude Code auth (no re-prompt)
#   ./run.sh install-claude-skill  - Install Claude Code skill into Hermes
#   ./run.sh install-codex-skill   - Install Codex skill into Hermes
#   ./run.sh install-skills        - Install both delegation skills
#   ./run.sh setup                 - Hermes setup wizard
#   ./run.sh gateway-setup         - Configure Discord/Slack gateway
#   ./run.sh up                    - Start long-running container (detached)
#   ./run.sh attach                - Open shell in running container
#   ./run.sh logs                  - Tail logs from running container
#   ./run.sh stop                  - Stop long-running container
#   ./run.sh run                   - One-shot hermes run (interactive)
#   ./run.sh start                 - One-shot interactive shell
#   ./run.sh noshield              - Emergency shell without firewall (DEBUG)

set -euo pipefail

IMAGE_NAME="hermes-dev"
CONTAINER_NAME="hermes-agent"
WORKSPACE="$(pwd)"

VOLUMES=(
    -v "${WORKSPACE}:/workspace"
    -v "hermes-codex-auth:/home/hermes/.codex"
    -v "hermes-claude-auth:/home/hermes/.claude"
    -v "hermes-home:/home/hermes/.hermes"
    -v "hermes-ssh:/home/hermes/.ssh"
    -v "hermes-bash-history:/commandhistory"
)

HARDENING=(
    --cap-drop=ALL
    --cap-add=NET_ADMIN
    --cap-add=NET_RAW
    --cap-add=CHOWN
    --cap-add=SETUID
    --cap-add=SETGID
    --cap-add=DAC_OVERRIDE
    --security-opt=no-new-privileges
    --pids-limit=1024
    --memory=6g
    --memory-swap=6g
    --cpus=3
)

PORTS=(
    -p 127.0.0.1:10531:10531
    -p 127.0.0.1:8090:8090
)

ENV=(
    -e DEPLOY_HOST="${DEPLOY_HOST:-general-01.kimys.net}"
)

is_running() {
    docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"
}

case "${1:-start}" in
    build)
        docker build -f .devcontainer/Dockerfile -t "$IMAGE_NAME" .
        ;;
    init)
        if [ -z "${2:-}" ]; then
            echo "Usage: $0 init <project-name>"
            exit 1
        fi
        PROJECT_NAME="$2"
        if ! [[ "$PROJECT_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
            echo "Error: project name must contain only alphanumeric, hyphens, underscores"
            exit 1
        fi
        PROJECT_DIR="${WORKSPACE}/${PROJECT_NAME}"
        if [ -d "$PROJECT_DIR" ]; then
            echo "Using existing project: $PROJECT_DIR"
        else
            echo "Creating new project: $PROJECT_DIR"
            mkdir -p "$PROJECT_DIR"
            cat > "$PROJECT_DIR/README.md" <<EOF
# $PROJECT_NAME

Project managed by Hermes Agent inside the hardened dev container.

## Notes
- This folder is excluded from the parent dev-container git repository.
- If you want to version this project separately, run \`git init\` inside this folder.
EOF
        fi
        GITIGNORE="${WORKSPACE}/.gitignore"
        if ! grep -Fxq "/${PROJECT_NAME}/" "$GITIGNORE" 2>/dev/null; then
            echo "/${PROJECT_NAME}/" >> "$GITIGNORE"
            echo "Added /${PROJECT_NAME}/ to .gitignore"
        fi
        echo "$PROJECT_NAME" > "${WORKSPACE}/.current-project"
        echo "Active project: $PROJECT_NAME"
        ;;
    login)
        # Use device-code flow: Codex prints a short code + URL; user opens
        # the URL on the host browser and pastes the code. No port forwarding
        # required, more robust across Docker/WSL/network setups.
        docker run --rm -it \
            "${HARDENING[@]}" "${VOLUMES[@]}" "${ENV[@]}" \
            "$IMAGE_NAME" codex login --device-auth
        ;;
    claude-login)
        # Claude Code's OAuth flow. Note: this re-prompts even if you're
        # already logged in. Use `claude-status` to check auth without
        # re-prompting.
        docker run --rm -it \
            "${HARDENING[@]}" "${VOLUMES[@]}" "${ENV[@]}" \
            "$IMAGE_NAME" claude login
        ;;
    claude-status)
        # Check whether Claude Code already has valid credentials in the
        # hermes-claude-auth volume. Does not re-prompt or re-authenticate.
        docker run --rm \
            "${HARDENING[@]}" "${VOLUMES[@]}" "${ENV[@]}" \
            "$IMAGE_NAME" claude auth status
        ;;
    install-claude-skill)
        docker run --rm \
            "${HARDENING[@]}" "${VOLUMES[@]}" "${ENV[@]}" \
            "$IMAGE_NAME" \
            bash -c 'mkdir -p ~/.hermes/skills && cp -r /opt/hermes-skills/claude_code ~/.hermes/skills/ && echo "Installed Claude Code skill to ~/.hermes/skills/claude_code/"'
        ;;
    install-codex-skill)
        docker run --rm \
            "${HARDENING[@]}" "${VOLUMES[@]}" "${ENV[@]}" \
            "$IMAGE_NAME" \
            bash -c 'mkdir -p ~/.hermes/skills && cp -r /opt/hermes-skills/codex ~/.hermes/skills/ && echo "Installed Codex skill to ~/.hermes/skills/codex/"'
        ;;
    install-skills)
        # Install both Claude Code and Codex skills in one shot.
        docker run --rm \
            "${HARDENING[@]}" "${VOLUMES[@]}" "${ENV[@]}" \
            "$IMAGE_NAME" \
            bash -c 'mkdir -p ~/.hermes/skills && cp -r /opt/hermes-skills/claude_code /opt/hermes-skills/codex ~/.hermes/skills/ && echo "Installed Claude Code + Codex skills"'
        ;;
    setup)
        docker run --rm -it \
            "${HARDENING[@]}" "${VOLUMES[@]}" "${PORTS[@]}" "${ENV[@]}" \
            "$IMAGE_NAME" hermes setup
        ;;
    gateway-setup)
        docker run --rm -it \
            "${HARDENING[@]}" "${VOLUMES[@]}" "${PORTS[@]}" "${ENV[@]}" \
            "$IMAGE_NAME" hermes gateway
        ;;
    up)
        if is_running; then
            echo "Container '${CONTAINER_NAME}' is already running. Use 'attach' or 'stop'."
            exit 1
        fi
        # Long-running container: OAuth proxy + Hermes gateway in background
        # Entrypoint runs firewall, then keeps bash alive waiting for exec
        docker run -d \
            --name "$CONTAINER_NAME" \
            "${HARDENING[@]}" "${VOLUMES[@]}" "${PORTS[@]}" "${ENV[@]}" \
            "$IMAGE_NAME" \
            bash -c "(openai-oauth > /tmp/oauth.log 2>&1 &) && (hermes gateway start > /tmp/gateway.log 2>&1 &) && sleep infinity"
        echo "Container '${CONTAINER_NAME}' started in background."
        echo "  Attach: ./run.sh attach"
        echo "  Logs:   ./run.sh logs"
        echo "  Stop:   ./run.sh stop"
        ;;
    attach)
        if ! is_running; then
            echo "Container '${CONTAINER_NAME}' is not running. Start it with 'up'."
            exit 1
        fi
        docker exec -it "$CONTAINER_NAME" bash
        ;;
    logs)
        if ! is_running; then
            echo "Container '${CONTAINER_NAME}' is not running."
            exit 1
        fi
        echo "=== OAuth proxy log ==="
        docker exec "$CONTAINER_NAME" cat /tmp/oauth.log 2>/dev/null || echo "(none)"
        echo ""
        echo "=== Gateway log ==="
        docker exec "$CONTAINER_NAME" cat /tmp/gateway.log 2>/dev/null || echo "(none)"
        echo ""
        echo "=== Container log ==="
        docker logs --tail 50 "$CONTAINER_NAME"
        ;;
    stop)
        if is_running; then
            docker stop "$CONTAINER_NAME"
            docker rm "$CONTAINER_NAME" 2>/dev/null || true
            echo "Stopped."
        else
            echo "Not running."
        fi
        ;;
    run)
        docker run --rm -it \
            "${HARDENING[@]}" "${VOLUMES[@]}" "${PORTS[@]}" "${ENV[@]}" \
            "$IMAGE_NAME" \
            bash -c "(openai-oauth &) && sleep 2 && hermes"
        ;;
    start)
        docker run --rm -it \
            "${HARDENING[@]}" "${VOLUMES[@]}" "${PORTS[@]}" "${ENV[@]}" \
            "$IMAGE_NAME"
        ;;
    noshield)
        echo "WARNING: No firewall, no hardening (DEBUG ONLY)"
        docker run --rm -it --entrypoint /bin/bash \
            "${VOLUMES[@]}" "${ENV[@]}" \
            "$IMAGE_NAME"
        ;;
    *)
        cat <<EOF
Usage: $0 <command>

Project:
  init <name>     Create or select a project folder (auto-added to .gitignore)

Setup:
  build                 Build the Docker image
  login                 Codex OAuth login (ChatGPT Pro)
  claude-login          Claude Code OAuth login (always re-prompts)
  claude-status         Check Claude Code auth status (no re-prompt)
  install-claude-skill  Copy Claude Code skill into Hermes skills dir
  install-codex-skill   Copy Codex skill into Hermes skills dir
  install-skills        Install both delegation skills (Claude + Codex)
  setup                 Hermes setup wizard
  gateway-setup         Configure Discord/Slack gateway

Long-running:
  up              Start container in background (OAuth proxy + Gateway)
  attach          Open shell in running container
  logs            Show gateway and OAuth proxy logs
  stop            Stop the running container

One-shot:
  run             Run hermes interactively (proxy auto-started)
  start           Interactive shell
  noshield        DEBUG: shell without firewall
EOF
        exit 1
        ;;
esac
