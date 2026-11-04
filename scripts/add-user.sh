#!/usr/bin/env bash
#
# Add a new lab user.
#   sudo ./scripts/add-user.sh <username>
#
# Assumes Tailscale SSH is the primary access path. No initial password
# and no authorized_keys are set up: the account is locked. Access is
# granted by sharing this machine with the user (Tailscale Machines -> Share);
# inviting the user to the tailnet is an option for admins / special users only.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# ---------- configurable variables ----------
SHARED_GROUP="${SHARED_GROUP:-labmembers}"
# --------------------------------------------

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

ensure_group "$SHARED_GROUP"
ensure_group docker

log_info "Creating user: $USERNAME"
useradd -m -s /bin/bash -G "$SHARED_GROUP",docker "$USERNAME"

# Lock the password (no password login possible).
passwd -l "$USERNAME" >/dev/null

# Lock down home directory (750: user's private group only, others closed).
chmod 750 "/home/$USERNAME"

TS_HOSTNAME=$(hostname)
TS_IP=$(tailscale ip -4 2>/dev/null) || true   # Tailscale may be absent or stopped
# MagicDNS FQDN (<host>.<tailnet>.ts.net); shared machines are reachable only by it or the IP.
TS_FQDN=$(tailscale status --json 2>/dev/null \
    | python3 -c 'import json,sys; print(json.load(sys.stdin).get("Self",{}).get("DNSName","").rstrip("."))' \
    2>/dev/null) || true   # Tailscale may be absent or stopped

cat <<EOF

================ User Created ================
  Username : $USERNAME
  Groups   : $(id -nG "$USERNAME")
  Home     : /home/$USERNAME (mode 750)
  Password : LOCKED (Tailscale SSH is the access path)

SSH CONNECTION (tell the user):
  ssh $USERNAME@${TS_FQDN:-<host>.<tailnet>.ts.net}
  ssh $USERNAME@${TS_IP:-<tailscale-ip>}
  ssh $USERNAME@${TS_HOSTNAME:-<host>}   (tailnet members only)

NEXT STEPS:
  1. Share this machine with the user's email: Tailscale admin console ->
     Machines -> this machine -> Share. No password, no SSH key required.
  2. If this is a new user, add a rule to the policy file's "ssh" section
     (users: ["$USERNAME"], dst: ["tag:server"]):
     https://login.tailscale.com/admin/acls/file
  3. Tell the user the FQDN above: ssh $USERNAME@${TS_FQDN:-<host>.<tailnet>.ts.net}
  (admins / special users only: invite to the tailnet instead, see docs/admin/add-user.md)

  To open a shell as this user from the admin account:
      sudo -i -u $USERNAME
===============================================
EOF
