#!/usr/bin/env bash
#
# Add a new lab user.
#   sudo ./scripts/add-user.sh <username>
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_root

if [[ $# -lt 1 || $# -gt 2 ]]; then
    die "Usage: $0 <username> [path/to/pubkey]"
fi
USERNAME="$1"
PUBKEY="${2:-}"

if [[ -n "$PUBKEY" ]]; then
    if [[ ! -r "$PUBKEY" ]]; then
        die "Public key file not readable: $PUBKEY"
    fi
    if ! ssh-keygen -l -f "$PUBKEY" >/dev/null 2>&1; then
        die "Not a valid SSH public key file: $PUBKEY"
    fi
fi

if ! [[ "$USERNAME" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
    die "Invalid username: $USERNAME"
fi

if id "$USERNAME" >/dev/null 2>&1; then
    die "User already exists: $USERNAME"
fi

ensure_group labmembers
ensure_group docker

log_info "Creating user: $USERNAME"
useradd -m -s /bin/bash -G labmembers,docker "$USERNAME"

# Random initial password (16 chars).
INITIAL_PASS="$(tr -dc 'A-Za-z0-9!@#%+=' </dev/urandom | head -c 16)"
echo "${USERNAME}:${INITIAL_PASS}" | chpasswd
# Force password change on first login.
chage -d 0 "$USERNAME"

# Lock down home directory (750: user's private group only, others closed).
chmod 750 "/home/$USERNAME"
install -d -o "$USERNAME" -g "$USERNAME" -m 700 "/home/$USERNAME/.ssh"

AUTH_KEYS="/home/$USERNAME/.ssh/authorized_keys"
if [[ -n "$PUBKEY" ]]; then
    log_info "Installing public key from $PUBKEY"
    install -o "$USERNAME" -g "$USERNAME" -m 600 "$PUBKEY" "$AUTH_KEYS"
    KEY_STATUS="installed from $PUBKEY"
else
    touch "$AUTH_KEYS"
    chown "$USERNAME:$USERNAME" "$AUTH_KEYS"
    chmod 600 "$AUTH_KEYS"
    KEY_STATUS="empty (add the user's public key manually)"
fi

cat <<EOF

================ User Created ================
  Username        : $USERNAME
  Initial password: $INITIAL_PASS
  Groups          : $(id -nG "$USERNAME")
  Home            : /home/$USERNAME (mode 750)
  Authorized keys : $AUTH_KEYS
                    $KEY_STATUS

NOTE:
  - The user must change the password on first login (chage -d 0 set).
  - To operate as this user from the admin account, use: sudo -i -u $USERNAME
  - Communicate the initial password through a secure channel.
===============================================
EOF
