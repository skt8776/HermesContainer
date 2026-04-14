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

# Persist Claude Code's main config (~/.claude.json) across container
# restarts via the .claude volume.
#
# Background:
#   Claude stores OAuth credentials in ~/.claude/.credentials.json
#   (volume — persistent) and its main config in ~/.claude.json
#   (home root — ephemeral, wiped on every container start). Without
#   the main config, Claude treats the user as not logged in even
#   though valid credentials exist.
#
#   Claude maintains backups at ~/.claude/backups/.claude.json.backup.*
#   inside the volume, BUT after a container restart Claude rewrites
#   the main config to a near-empty stub (just `firstStartTime`) and
#   then backs THAT up, drowning out the older backup that had the
#   real auth state. So "most recent backup" is the wrong heuristic —
#   we use the LARGEST backup, which is the one with real data.
#
# Strategy:
#   1. Move any existing real ~/.claude.json into the volume
#      (~/.claude/main-config.json).
#   2. If the volume's copy is missing or a tiny stub, restore from
#      the largest backup.
#   3. Replace ~/.claude.json with a symlink to the volume copy so
#      Claude's future writes also persist.

CLAUDE_CONFIG_LINK=/home/hermes/.claude.json
CLAUDE_CONFIG_REAL=/home/hermes/.claude/main-config.json

# Step 1: import any existing real file into the volume
if [ -f "$CLAUDE_CONFIG_LINK" ] && [ ! -L "$CLAUDE_CONFIG_LINK" ]; then
    if [ ! -e "$CLAUDE_CONFIG_REAL" ]; then
        mv "$CLAUDE_CONFIG_LINK" "$CLAUDE_CONFIG_REAL"
    else
        rm -f "$CLAUDE_CONFIG_LINK"
    fi
fi

# Step 2: if the volume copy is missing or a tiny stub, restore from
# the largest backup (it has the OAuth account state we need).
NEED_RESTORE=false
if [ ! -e "$CLAUDE_CONFIG_REAL" ]; then
    NEED_RESTORE=true
elif [ "$(stat -c %s "$CLAUDE_CONFIG_REAL" 2>/dev/null || echo 0)" -lt 200 ]; then
    NEED_RESTORE=true
fi

if [ "$NEED_RESTORE" = true ] && [ -d /home/hermes/.claude/backups ]; then
    # ls -S sorts by size, largest first
    LARGEST_BACKUP=$(ls -S /home/hermes/.claude/backups/.claude.json.backup.* 2>/dev/null | head -1)
    if [ -n "$LARGEST_BACKUP" ]; then
        BACKUP_SIZE=$(stat -c %s "$LARGEST_BACKUP" 2>/dev/null || echo 0)
        if [ "$BACKUP_SIZE" -gt 100 ]; then
            cp "$LARGEST_BACKUP" "$CLAUDE_CONFIG_REAL"
            echo "Restored Claude main config from largest backup ($BACKUP_SIZE bytes)"
        fi
    fi
fi

# Step 3: chmod (while still root-owned), chown, then symlink.
if [ -e "$CLAUDE_CONFIG_REAL" ]; then
    chmod 600 "$CLAUDE_CONFIG_REAL" 2>/dev/null || true
    chown hermes:hermes "$CLAUDE_CONFIG_REAL"
    rm -f "$CLAUDE_CONFIG_LINK"
    ln -s "$CLAUDE_CONFIG_REAL" "$CLAUDE_CONFIG_LINK"
    chown -h hermes:hermes "$CLAUDE_CONFIG_LINK"
fi

# Drop to hermes user for everything else
if [ $# -eq 0 ]; then
    exec runuser -u hermes -- bash
else
    exec runuser -u hermes -- "$@"
fi
