#!/bin/bash
# Container entrypoint — runs as root, initializes firewall, drops to hermes user.
# This design lets us keep --security-opt=no-new-privileges while still
# configuring iptables (which requires root).

set -euo pipefail

# Initialize firewall as root (requires NET_ADMIN, NET_RAW capabilities)
if [ -x /usr/local/bin/init-firewall.sh ]; then
    echo "=== Initializing network firewall ==="
    /usr/local/bin/init-firewall.sh
    echo ""
fi

# Ensure persistent volume mount points are owned by hermes (uid 1000).
# Docker named volumes default to root:root on first creation, which would
# break codex/claude/hermes since they run as the unprivileged user.
for dir in \
    /home/hermes/.codex \
    /home/hermes/.claude \
    /home/hermes/.hermes \
    /home/hermes/.ssh \
    /commandhistory; do
    if [ -d "$dir" ]; then
        chown -R hermes:hermes "$dir" 2>/dev/null || true
    fi
done

# Drop to hermes user for everything else
if [ $# -eq 0 ]; then
    exec runuser -u hermes -- bash
else
    exec runuser -u hermes -- "$@"
fi
