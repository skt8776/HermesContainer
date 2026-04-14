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

# Re-inject the hermes-agent symlink inside the .hermes volume.
# Background: the Hermes installer puts the agent code at
# /home/hermes/.hermes/hermes-agent/. That directory is the mount
# target of the hermes-home volume, so on first run the volume HIDES
# the in-image install. We move the install to /opt/hermes-agent in
# the image (Dockerfile) and recreate the symlink here on every
# container start.
#
# Stale-volume case: an earlier (broken) install may have left a real
# hermes-agent directory inside the volume. We unconditionally replace
# it with our symlink so the canonical /opt/hermes-agent is always used.
# User config / skills / sessions in sibling subdirs are untouched.
if [ -d /opt/hermes-agent ]; then
    if [ -e /home/hermes/.hermes/hermes-agent ] && [ ! -L /home/hermes/.hermes/hermes-agent ]; then
        rm -rf /home/hermes/.hermes/hermes-agent
    fi
    if [ ! -L /home/hermes/.hermes/hermes-agent ]; then
        ln -s /opt/hermes-agent /home/hermes/.hermes/hermes-agent
        chown -h hermes:hermes /home/hermes/.hermes/hermes-agent
    fi
fi

# Auto-restore Claude's main config from backup if missing.
# With CLAUDE_CONFIG_DIR=/home/hermes/.claude (set in Dockerfile),
# Claude expects its main config at /home/hermes/.claude/.claude.json
# (inside the volume). After a fresh login or migration, the backups
# at /home/hermes/.claude/backups/.claude.json.backup.* hold valid
# state — restore the largest one if the live file is missing or a
# tiny stub. This handles re-using a volume after switching to
# CLAUDE_CONFIG_DIR.
CLAUDE_LIVE=/home/hermes/.claude/.claude.json
CLAUDE_BACKUPS=/home/hermes/.claude/backups
if [ -d "$CLAUDE_BACKUPS" ]; then
    LIVE_SIZE=0
    [ -f "$CLAUDE_LIVE" ] && LIVE_SIZE=$(stat -c %s "$CLAUDE_LIVE" 2>/dev/null || echo 0)
    if [ "$LIVE_SIZE" -lt 200 ]; then
        # Largest backup wins (real data > tiny stub)
        LARGEST=$(ls -S "$CLAUDE_BACKUPS"/.claude.json.backup.* 2>/dev/null | head -1)
        if [ -n "$LARGEST" ]; then
            BACKUP_SIZE=$(stat -c %s "$LARGEST" 2>/dev/null || echo 0)
            if [ "$BACKUP_SIZE" -gt "$LIVE_SIZE" ] && [ "$BACKUP_SIZE" -gt 200 ]; then
                cp "$LARGEST" "$CLAUDE_LIVE"
                chmod 600 "$CLAUDE_LIVE"
                chown hermes:hermes "$CLAUDE_LIVE"
                echo "Restored Claude main config from largest backup ($BACKUP_SIZE bytes)"
            fi
        fi
    fi
fi

# Drop to hermes user for everything else
if [ $# -eq 0 ]; then
    exec runuser -u hermes -- bash
else
    exec runuser -u hermes -- "$@"
fi
