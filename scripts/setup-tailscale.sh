#!/usr/bin/env bash
#
# Install Tailscale and bring it up with an auth key, or print interactive
# auth instructions. Independent of scripts/setup.sh; run it first.
#   sudo ./scripts/setup-tailscale.sh
#   TAILSCALE_AUTHKEY=tskey-auth-XXXX sudo -E ./scripts/setup-tailscale.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# ---------- configurable variables ----------
TAILSCALE_AUTHKEY="${TAILSCALE_AUTHKEY:-}"
TAILSCALE_HOSTNAME="${TAILSCALE_HOSTNAME:-$(hostname)}"
TAILSCALE_TAGS="${TAILSCALE_TAGS:-tag:server}"   # must be listed in the policy file's tagOwners
# --------------------------------------------

# True when tailscaled reports BackendState "Running" (already logged in and up).
# The full output is captured first: `grep -q` on a pipe could exit early and
# SIGPIPE tailscale, which pipefail would turn into a false negative.
tailscale_running() {
    local status
    status=$(tailscale status --json 2>/dev/null) || return 1
    grep -Eq '"BackendState": *"Running"' <<<"$status"
}

# Print the tags this node (Self) carries, one per line.
tailscale_self_tags() {
    tailscale status --json 2>/dev/null \
        | python3 -c 'import json,sys; print("\n".join(json.load(sys.stdin).get("Self",{}).get("Tags") or []))'
}

# Bring a node that is already up in line with this script's flags without
# re-authenticating. Tags cannot be changed by `tailscale set`, so a missing
# tag is reported with the command that fixes it.
reconcile_running_node() {
    tailscale set --ssh --hostname="$TAILSCALE_HOSTNAME"
    log_info "Tailscale is already Running — applied --ssh and --hostname=$TAILSCALE_HOSTNAME. IP: $(tailscale ip -4 | head -n1)"
    local tags tag
    tags=$(tailscale_self_tags) || tags=""
    for tag in ${TAILSCALE_TAGS//,/ }; do
        if ! grep -qx "$tag" <<<"$tags"; then
            log_warn "This node lacks $tag, so policy-file ssh rules with dst $tag do not match it."
            log_warn "Fix: sudo tailscale up --ssh --hostname=$TAILSCALE_HOSTNAME --advertise-tags=$TAILSCALE_TAGS --force-reauth"
            log_warn "(or add the tag on the machine page of the Tailscale admin console)"
        fi
    done
}

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

if tailscale_running; then
    reconcile_running_node
elif [[ -n "$TAILSCALE_AUTHKEY" ]]; then
    log_info "Auth key provided — running tailscale up (non-interactive, tags: $TAILSCALE_TAGS)"
    tailscale up --ssh --authkey="$TAILSCALE_AUTHKEY" --hostname="$TAILSCALE_HOSTNAME" \
        --advertise-tags="$TAILSCALE_TAGS"
    log_info "Tailscale is up. Status:"
    tailscale status
    log_info "Tailscale IP: $(tailscale ip -4)"
else
    cat <<EOF

================ Tailscale next steps ================
Run the following command to authenticate this host:

    sudo tailscale up --ssh --hostname="$TAILSCALE_HOSTNAME" --advertise-tags=$TAILSCALE_TAGS

  --ssh              : enables Tailscale SSH (no separate key required)
  --hostname=...     : registers under the current hostname
  --advertise-tags=..: assigns the tag that the policy file's ssh rules match

After running, follow the printed URL to log in via your tailnet admin.

For headless (no browser) servers, generate an auth key at:
    https://login.tailscale.com/admin/settings/keys
Then re-run this script with:
    TAILSCALE_AUTHKEY=tskey-auth-XXXX sudo -E ./scripts/setup-tailscale.sh

To see status:        tailscale status
To find the IP:       tailscale ip -4
To bring it down:     sudo tailscale down
=======================================================
EOF
fi
