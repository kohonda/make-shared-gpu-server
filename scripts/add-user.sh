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

if [[ $# -ne 1 ]]; then
    die "Usage: $0 <username>"
fi
USERNAME="$1"

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

# Lock down home directory.
chmod 700 "/home/$USERNAME"
install -d -o "$USERNAME" -g "$USERNAME" -m 700 "/home/$USERNAME/.ssh"
touch "/home/$USERNAME/.ssh/authorized_keys"
chown "$USERNAME:$USERNAME" "/home/$USERNAME/.ssh/authorized_keys"
chmod 600 "/home/$USERNAME/.ssh/authorized_keys"

cat <<EOF

================ User Created ================
  Username        : $USERNAME
  Initial password: $INITIAL_PASS
  Groups          : $(id -nG "$USERNAME")
  Home            : /home/$USERNAME (mode 700)
  Authorized keys : /home/$USERNAME/.ssh/authorized_keys

NOTE:
  - The user must change the password on first login (chage -d 0 set).
  - Add the user's SSH public key to authorized_keys to enable key login.
  - Communicate the initial password through a secure channel.
===============================================
EOF
