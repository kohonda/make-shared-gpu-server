#!/usr/bin/env bash
#
# Apply ufw rules for the lab GPU server.
#   sudo ./config/ufw/rules.sh [LOCAL_CIDR]
#
# Defaults:
#   LOCAL_CIDR = 192.168.0.0/16
#
# Policy:
#   - default deny incoming, allow outgoing
#   - SSH allowed ONLY on tailscale0 (Tailscale SSH handles auth)
#   - Grafana (3000) / Prometheus (9090) allowed only on tailscale0
#
# The LOCAL_CIDR argument is reserved for future use (e.g. opening
# non-SSH services to the lab LAN) and is currently unused.
#
set -euo pipefail

: "${1:-}"  # LOCAL_CIDR reserved; see header comment

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    echo "[ERROR] must be run as root" >&2
    exit 1
fi

if ! command -v ufw >/dev/null 2>&1; then
    echo "[ERROR] ufw is not installed" >&2
    exit 1
fi

ufw --force reset >/dev/null
ufw default deny incoming
ufw default allow outgoing

# SSH (tailscale-only)
ufw allow in on tailscale0 to any port 22 proto tcp comment 'SSH via tailscale'

# Monitoring (tailnet only)
ufw allow in on tailscale0 to any port 3000 proto tcp comment 'Grafana via tailscale'
ufw allow in on tailscale0 to any port 9090 proto tcp comment 'Prometheus via tailscale'

ufw --force enable
ufw status verbose
