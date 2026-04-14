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

# Restore Claude Code's main config (~/.claude.json) from backup if missing.
# Claude writes its OAuth credentials to ~/.claude/.credentials.json
# (which is in the persistent volume) AND its main config to
# ~/.claude.json (which is in the home root and ephemeral). Without
# the main config, Claude treats the user as not logged in even though
# valid credentials exist.
#
# Claude itself maintains backups at ~/.claude/backups/.claude.json.backup.*
# inside the volume, so we restore the most recent one on every container
# start. This is what keeps `claude login` from re-prompting after a
# container restart.
if [ ! -f /home/hermes/.claude.json ] && [ -d /home/hermes/.claude/backups ]; then
    LATEST_BACKUP=$(ls -t /home/hermes/.claude/backups/.claude.json.backup.* 2>/dev/null | head -1)
    if [ -n "$LATEST_BACKUP" ]; then
        # Order matters under --cap-drop=ALL: chmod requires either
        # ownership or FOWNER capability. Set perms while root still
        # owns the freshly-copied file, then transfer ownership.
        cp "$LATEST_BACKUP" /home/hermes/.claude.json
        chmod 600 /home/hermes/.claude.json
        chown hermes:hermes /home/hermes/.claude.json
        echo "Restored Claude main config from backup: $(basename "$LATEST_BACKUP")"
    fi
fi

# Drop to hermes user for everything else
if [ $# -eq 0 ]; then
    exec runuser -u hermes -- bash
else
    exec runuser -u hermes -- "$@"
fi
