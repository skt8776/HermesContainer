#!/bin/bash
# Hermes Agent Dev Container Firewall
# Based on Anthropic's Claude Code init-firewall.sh
# https://github.com/anthropics/claude-code/blob/main/.devcontainer/init-firewall.sh
#
# Default output is concise. Set FIREWALL_DEBUG=1 to see resolving/adding
# details for each domain.

set -euo pipefail
IFS=$'\n\t'

DEBUG="${FIREWALL_DEBUG:-0}"
DEPLOY_HOST="${DEPLOY_HOST:-general-01.kimys.net}"

dbg() { [ "$DEBUG" = "1" ] && echo "$@"; return 0; }
say() { echo "$@"; }

# ─── 1. Preserve Docker DNS rules before flushing ─────────────────────────
DOCKER_DNS_RULES=$(iptables-save -t nat | grep "127\.0\.0\.11" || true)

iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
ipset destroy allowed-domains 2>/dev/null || true

# ─── 2. Restore Docker internal DNS resolution ────────────────────────────
if [ -n "$DOCKER_DNS_RULES" ]; then
    dbg "Restoring Docker DNS rules..."
    iptables -t nat -N DOCKER_OUTPUT 2>/dev/null || true
    iptables -t nat -N DOCKER_POSTROUTING 2>/dev/null || true
    echo "$DOCKER_DNS_RULES" | xargs -L 1 iptables -t nat
else
    dbg "No Docker DNS rules to restore"
fi

# ─── 3. Base rules: DNS, SSH, localhost ───────────────────────────────────
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A INPUT  -p udp --sport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT  -p tcp --sport 22 -m state --state ESTABLISHED -j ACCEPT
iptables -A INPUT  -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# Inbound on Docker port-forwards (OAuth callbacks, OAuth proxy, agent UI)
iptables -A INPUT -p tcp --dport 1455  -j ACCEPT
iptables -A INPUT -p tcp --dport 54545 -j ACCEPT
iptables -A INPUT -p tcp --dport 10531 -j ACCEPT
iptables -A INPUT -p tcp --dport 8090  -j ACCEPT

# ─── 4. ipset for CIDR/IP allowlist ───────────────────────────────────────
ipset create allowed-domains hash:net

# ─── 5. GitHub meta IP ranges ─────────────────────────────────────────────
dbg "Fetching GitHub IP ranges..."
gh_ranges=$(curl -s https://api.github.com/meta)
if [ -z "$gh_ranges" ] || ! echo "$gh_ranges" | jq -e '.web and .api and .git' >/dev/null; then
    say "[firewall] WARNING: failed to fetch GitHub meta IP ranges"
else
    while read -r cidr; do
        if [[ "$cidr" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
            ipset add allowed-domains "$cidr"
            dbg "  Added GitHub CIDR $cidr"
        fi
    done < <(echo "$gh_ranges" | jq -r '(.web + .api + .git)[]' | aggregate -q 2>/dev/null)
fi

# ─── 6. Domain groups (parallel arrays for portability across bash versions) ─
GROUP_LABELS=(
    "OpenAI/ChatGPT"
    "Anthropic"
    "GitHub raw"
    "Registries"
    "VS Code"
    "Discord"
    "Slack"
    "Deploy"
)
GROUP_DOMAINS=(
    "auth.openai.com api.openai.com chatgpt.com cdn.oaistatic.com platform.openai.com models.inference.ai.azure.com"
    "api.anthropic.com console.anthropic.com claude.ai statsig.anthropic.com statsig.com sentry.io"
    "raw.githubusercontent.com objects.githubusercontent.com codeload.github.com ghcr.io"
    "registry.npmjs.org pypi.org files.pythonhosted.org deb.debian.org security.debian.org deb.nodesource.com"
    "marketplace.visualstudio.com vscode.blob.core.windows.net update.code.visualstudio.com"
    "discord.com gateway.discord.gg cdn.discordapp.com media.discordapp.net"
    "slack.com api.slack.com wss-primary.slack.com wss-backup.slack.com hooks.slack.com files.slack.com edgeapi.slack.com"
    "$DEPLOY_HOST"
)

# ─── 7. Resolve all domains ───────────────────────────────────────────────
# IFS is set to $'\n\t' globally for safety, so we must use `read -ra` to
# split the space-separated domain lists into proper arrays.
TOTAL_DOMAINS=0
TOTAL_FAILED=0
for i in "${!GROUP_LABELS[@]}"; do
    IFS=' ' read -ra _domains <<< "${GROUP_DOMAINS[$i]}"
    for domain in "${_domains[@]}"; do
        TOTAL_DOMAINS=$((TOTAL_DOMAINS + 1))
        dbg "Resolving $domain..."
        ips=$(dig +short +time=3 +tries=2 A "$domain" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || true)
        if [ -z "$ips" ]; then
            TOTAL_FAILED=$((TOTAL_FAILED + 1))
            dbg "  WARNING: failed to resolve $domain"
            continue
        fi
        while read -r ip; do
            [ -z "$ip" ] && continue
            dbg "  Adding $ip for $domain"
            ipset add allowed-domains "$ip" 2>/dev/null || true
        done < <(echo "$ips")
    done
done

# ─── 8. Host network ──────────────────────────────────────────────────────
HOST_IP=$(ip route | grep default | awk '{print $3}' | head -n1)
if [ -n "$HOST_IP" ]; then
    HOST_NETWORK=$(echo "$HOST_IP" | sed "s/\.[0-9]*$/.0\/24/")
    dbg "Host network: $HOST_NETWORK"
    iptables -A INPUT  -s "$HOST_NETWORK" -j ACCEPT
    iptables -A OUTPUT -d "$HOST_NETWORK" -j ACCEPT
fi

# ─── 9. Default-deny ──────────────────────────────────────────────────────
iptables -P INPUT   DROP
iptables -P FORWARD DROP
iptables -P OUTPUT  DROP
iptables -A INPUT  -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m set --match-set allowed-domains dst -j ACCEPT
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited

# ─── 10. Concise summary ──────────────────────────────────────────────────
say "[firewall] default-deny egress + allowlist active (FIREWALL_DEBUG=1 for verbose)"
say "[firewall] allowed groups:"
for i in "${!GROUP_LABELS[@]}"; do
    printf "  %-15s %s\n" "${GROUP_LABELS[$i]}" "${GROUP_DOMAINS[$i]}"
done
say "  GitHub API      <CIDR ranges from api.github.com/meta>"
RESOLVED=$((TOTAL_DOMAINS - TOTAL_FAILED))
if [ "$TOTAL_FAILED" -gt 0 ]; then
    say "[firewall] resolved $RESOLVED/$TOTAL_DOMAINS domains ($TOTAL_FAILED failed — re-run with FIREWALL_DEBUG=1)"
else
    say "[firewall] resolved $RESOLVED/$TOTAL_DOMAINS domains"
fi

# ─── 11. Quick verification (silent on success) ───────────────────────────
if curl --connect-timeout 5 -sS https://example.com >/dev/null 2>&1; then
    say "[firewall] FAIL: example.com reachable (should be blocked)"
    exit 1
fi
if ! curl --connect-timeout 5 -sS https://api.github.com/zen >/dev/null 2>&1; then
    say "[firewall] FAIL: api.github.com unreachable (should be allowed)"
    exit 1
fi
say "[firewall] verified: example.com blocked, api.github.com reachable"
