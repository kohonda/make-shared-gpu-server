#!/usr/bin/env bash
#
# Apply ufw rules for the lab GPU server.
#   sudo ./config/ufw/rules.sh
#
# Policy:
#   - default deny incoming, allow outgoing
#   - SSH allowed ONLY on tailscale0 (Tailscale SSH handles auth)
#   - Grafana (3000) / Prometheus (9090) allowed only on tailscale0
#
# When the tailscale0 interface does not exist yet, nothing is changed: enabling
# ufw then would drop the LAN SSH session an admin is working over.
#
set -euo pipefail

TAILSCALE_IFACE="tailscale0"

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    echo "[ERROR] must be run as root" >&2
    exit 1
fi

if ! command -v ufw >/dev/null 2>&1; then
    echo "[ERROR] ufw is not installed" >&2
    exit 1
fi

if [[ ! -e "/sys/class/net/$TAILSCALE_IFACE" ]]; then
    echo "[WARN] $TAILSCALE_IFACE not found: ufw left unchanged (not reset, not enabled)." >&2
    echo "[WARN] Bring Tailscale up (scripts/setup-tailscale.sh), then re-run scripts/setup.sh." >&2
    exit 0
fi

ufw --force reset >/dev/null
ufw default deny incoming
ufw default allow outgoing

# SSH (tailscale-only)
ufw allow in on tailscale0 to any port 22 proto tcp comment 'SSH via tailscale'

# Monitoring (tailnet only)
ufw allow in on tailscale0 to any port 3000 proto tcp comment 'Grafana via tailscale'
ufw allow in on tailscale0 to any port 9090 proto tcp comment 'Prometheus via tailscale'

# node-exporter: allow Prometheus (Docker bridge) to scrape host metrics
ufw allow from 172.16.0.0/12 to any port 9100 proto tcp comment 'node-exporter from Docker'

ufw --force enable
ufw status verbose
