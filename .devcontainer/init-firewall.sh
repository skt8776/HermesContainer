#!/bin/bash
# Hermes Agent Dev Container Firewall
# Based on Anthropic's Claude Code init-firewall.sh
# https://github.com/anthropics/claude-code/blob/main/.devcontainer/init-firewall.sh
#
# Applies default-deny egress policy with explicit allowlist for:
#   - OpenAI/ChatGPT (OAuth, API, subscription backend)
#   - GitHub (Hermes + Codex updates, npm packages)
#   - Package registries (npm, PyPI)
#   - SSH deployment target (configurable via DEPLOY_HOST env)

set -euo pipefail
IFS=$'\n\t'

# ─── Configurable deployment target ───────────────────────────────────────
DEPLOY_HOST="${DEPLOY_HOST:-general-01.kimys.net}"

# ─── 1. Preserve Docker DNS rules before flushing ─────────────────────────
DOCKER_DNS_RULES=$(iptables-save -t nat | grep "127\.0\.0\.11" || true)

# Flush existing rules
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
ipset destroy allowed-domains 2>/dev/null || true

# ─── 2. Restore Docker internal DNS resolution ────────────────────────────
if [ -n "$DOCKER_DNS_RULES" ]; then
    echo "Restoring Docker DNS rules..."
    iptables -t nat -N DOCKER_OUTPUT 2>/dev/null || true
    iptables -t nat -N DOCKER_POSTROUTING 2>/dev/null || true
    echo "$DOCKER_DNS_RULES" | xargs -L 1 iptables -t nat
else
    echo "No Docker DNS rules to restore"
fi

# ─── 3. Base rules: DNS, SSH, localhost ───────────────────────────────────
# DNS
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A INPUT  -p udp --sport 53 -j ACCEPT
# SSH outbound (for rsync deploy)
iptables -A OUTPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT  -p tcp --sport 22 -m state --state ESTABLISHED -j ACCEPT
# Localhost
iptables -A INPUT  -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# Inbound on Docker port-forwards (OAuth callbacks, OAuth proxy, agent UI).
# These are needed when the host browser hits localhost:<port> and Docker
# forwards the connection into the container — without these the INPUT
# default-DROP would silently kill the callback (ERR_EMPTY_RESPONSE).
iptables -A INPUT -p tcp --dport 1455  -j ACCEPT  # codex login callback
iptables -A INPUT -p tcp --dport 54545 -j ACCEPT  # claude login callback
iptables -A INPUT -p tcp --dport 10531 -j ACCEPT  # openai-oauth proxy
iptables -A INPUT -p tcp --dport 8090  -j ACCEPT  # agent UI

# ─── 4. Create ipset for CIDR/IP allowlist ────────────────────────────────
ipset create allowed-domains hash:net

# ─── 5. Fetch GitHub meta IP ranges ───────────────────────────────────────
echo "Fetching GitHub IP ranges..."
gh_ranges=$(curl -s https://api.github.com/meta)
if [ -z "$gh_ranges" ]; then
    echo "ERROR: Failed to fetch GitHub IP ranges"
    exit 1
fi
if ! echo "$gh_ranges" | jq -e '.web and .api and .git' >/dev/null; then
    echo "ERROR: GitHub API response missing required fields"
    exit 1
fi

echo "Processing GitHub IPs..."
while read -r cidr; do
    if [[ ! "$cidr" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        echo "Skipping non-IPv4 CIDR: $cidr"
        continue
    fi
    ipset add allowed-domains "$cidr"
done < <(echo "$gh_ranges" | jq -r '(.web + .api + .git)[]' | aggregate -q)

# ─── 6. Resolve and add Hermes-required domains ───────────────────────────
# OpenAI/ChatGPT OAuth + API + Subscription backend
# Package registries (npm, PyPI)
# VS Code extensions
# SSH deployment target
for domain in \
    "auth.openai.com" \
    "api.openai.com" \
    "chatgpt.com" \
    "cdn.oaistatic.com" \
    "platform.openai.com" \
    "models.inference.ai.azure.com" \
    "api.anthropic.com" \
    "console.anthropic.com" \
    "claude.ai" \
    "statsig.anthropic.com" \
    "statsig.com" \
    "sentry.io" \
    "registry.npmjs.org" \
    "pypi.org" \
    "files.pythonhosted.org" \
    "deb.debian.org" \
    "security.debian.org" \
    "deb.nodesource.com" \
    "raw.githubusercontent.com" \
    "objects.githubusercontent.com" \
    "codeload.github.com" \
    "ghcr.io" \
    "marketplace.visualstudio.com" \
    "vscode.blob.core.windows.net" \
    "update.code.visualstudio.com" \
    "discord.com" \
    "gateway.discord.gg" \
    "cdn.discordapp.com" \
    "media.discordapp.net" \
    "slack.com" \
    "api.slack.com" \
    "wss-primary.slack.com" \
    "wss-backup.slack.com" \
    "hooks.slack.com" \
    "files.slack.com" \
    "edgeapi.slack.com" \
    "$DEPLOY_HOST"; do
    echo "Resolving $domain..."
    ips=$(dig +short +time=3 +tries=2 A "$domain" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || true)
    if [ -z "$ips" ]; then
        echo "  WARNING: Failed to resolve $domain (skipping)"
        continue
    fi

    while read -r ip; do
        [ -z "$ip" ] && continue
        echo "  Adding $ip for $domain"
        ipset add allowed-domains "$ip" 2>/dev/null || true
    done < <(echo "$ips")
done

# ─── 7. Allow host network (for port-forwarding to Docker host) ───────────
HOST_IP=$(ip route | grep default | awk '{print $3}' | head -n1)
if [ -n "$HOST_IP" ]; then
    HOST_NETWORK=$(echo "$HOST_IP" | sed "s/\.[0-9]*$/.0\/24/")
    echo "Host network detected as: $HOST_NETWORK"
    iptables -A INPUT  -s "$HOST_NETWORK" -j ACCEPT
    iptables -A OUTPUT -d "$HOST_NETWORK" -j ACCEPT
else
    echo "WARNING: Could not detect host IP"
fi

# ─── 8. Default-deny policy ───────────────────────────────────────────────
iptables -P INPUT   DROP
iptables -P FORWARD DROP
iptables -P OUTPUT  DROP

# Allow established connections
iptables -A INPUT  -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow outbound to allowlisted IPs only
iptables -A OUTPUT -m set --match-set allowed-domains dst -j ACCEPT

# Explicit reject (fast failure for blocked destinations)
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited

# ─── 9. Verification ──────────────────────────────────────────────────────
echo ""
echo "=== Firewall Verification ==="

# Should FAIL (not in allowlist)
if curl --connect-timeout 5 -sS https://example.com >/dev/null 2>&1; then
    echo "FAIL: example.com is reachable (should be blocked)"
    exit 1
else
    echo "PASS: example.com blocked as expected"
fi

# Should SUCCEED (GitHub in allowlist)
if ! curl --connect-timeout 5 -sS https://api.github.com/zen >/dev/null 2>&1; then
    echo "FAIL: api.github.com is NOT reachable (should be allowed)"
    exit 1
else
    echo "PASS: api.github.com reachable as expected"
fi

# Should SUCCEED (OpenAI in allowlist)
if ! curl --connect-timeout 5 -sS -o /dev/null https://api.openai.com 2>&1; then
    echo "WARN: api.openai.com test returned error (may be normal - no auth)"
else
    echo "PASS: api.openai.com reachable"
fi

echo ""
echo "Firewall configuration complete."
echo "Allowlist active. All other outbound traffic rejected."
