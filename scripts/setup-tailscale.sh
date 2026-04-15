#!/usr/bin/env bash
#
# Install Tailscale and print interactive auth instructions.
#   sudo ./scripts/setup-tailscale.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_root
detect_ubuntu_version

if cmd_exists tailscale; then
    log_info "tailscale already installed: $(tailscale version | head -n1)"
else
    log_info "Adding Tailscale apt repository"
    curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/${UBUNTU_CODENAME}.noarmor.gpg" \
        -o /usr/share/keyrings/tailscale-archive-keyring.gpg
    curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/${UBUNTU_CODENAME}.tailscale-keyring.list" \
        -o /etc/apt/sources.list.d/tailscale.list
    apt-get update -qq
    ensure_apt_pkgs tailscale
    systemctl enable --now tailscaled
fi

cat <<'EOF'

================ Tailscale next steps ================
Run the following command to authenticate this host:

    sudo tailscale up --ssh --hostname="$(hostname)" --advertise-tags=tag:server

  --ssh              : enables Tailscale SSH (no separate key required)
  --hostname=...     : registers under the current hostname
  --advertise-tags=..: assigns a tag for ACL-based SSH access control

After running, follow the printed URL to log in via your tailnet admin.

To see status:        tailscale status
To find the IP:       tailscale ip -4
To bring it down:     sudo tailscale down
=======================================================
EOF
