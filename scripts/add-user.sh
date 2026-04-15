#!/usr/bin/env bash
#
# Add a new lab user.
#   sudo ./scripts/add-user.sh <username>
#
# Assumes Tailscale SSH is the primary access path. No initial password
# and no authorized_keys are set up: the account is locked. Access is
# granted by inviting the user to the tailnet.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_root

if [[ $# -ne 1 ]]; then
    die "Usage: $0 <username>"
fi
USERNAME="$1"

if ! [[ "$USERNAME" =~ ^[a-z_][a-z0-9._-]{0,31}$ ]]; then
    die "Invalid username: $USERNAME"
fi

if id "$USERNAME" >/dev/null 2>&1; then
    die "User already exists: $USERNAME"
fi

ensure_group labmembers
ensure_group docker

log_info "Creating user: $USERNAME"
useradd -m -s /bin/bash -G labmembers,docker "$USERNAME"

# Lock the password (no password login possible).
passwd -l "$USERNAME" >/dev/null

# Lock down home directory (750: user's private group only, others closed).
chmod 750 "/home/$USERNAME"

TS_HOSTNAME=$(hostname)
TS_IP=$(tailscale ip -4 2>/dev/null)

cat <<EOF

================ User Created ================
  Username : $USERNAME
  Groups   : $(id -nG "$USERNAME")
  Home     : /home/$USERNAME (mode 750)
  Password : LOCKED (Tailscale SSH is the access path)

SSH CONNECTION (tell the user):
  ssh $USERNAME@${TS_HOSTNAME:-<server-tailnet-name>}
  ssh $USERNAME@${TS_IP:-<tailscale-ip>}

NEXT STEPS:
  1. Invite the user to the lab tailnet so they can reach this host
     via Tailscale SSH. No password, no SSH key required.
  2. Add the user to the Tailscale ACL SSH rules:
     https://login.tailscale.com/admin/acls/file
  3. To open a shell as this user from the admin account:
         sudo -i -u $USERNAME
===============================================
EOF
