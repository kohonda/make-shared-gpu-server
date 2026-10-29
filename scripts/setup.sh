#!/usr/bin/env bash
#
# Lab GPU server main setup script.
# Run as root on a fresh Ubuntu 22.04 / 24.04 host *after* installing the
# NVIDIA driver manually (this script does NOT install it).
#
#   sudo ./scripts/setup.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# ---------- configurable variables ----------
LAB_LOCAL_CIDR="${LAB_LOCAL_CIDR:-192.168.0.0/16}"
SHARED_GROUP="${SHARED_GROUP:-labmembers}"
SHARED_ROOT="${SHARED_ROOT:-/shared}"
SCRATCH_DIR="${SCRATCH_DIR:-/scratch}"
ARCHIVE_DIR="${ARCHIVE_DIR:-/archive}"
UV_INSTALL_DIR="${UV_INSTALL_DIR:-/usr/local/bin}"
PIXI_INSTALL_DIR="${PIXI_INSTALL_DIR:-/usr/local/bin}"
SSHD_DROPIN_DIR="${SSHD_DROPIN_DIR:-/etc/ssh/sshd_config.d}"
SSHD_DROPIN="00-lab.conf"
SSHD_LEGACY_DROPIN="99-lab.conf"   # name used before 00-lab.conf; removed if present
# --------------------------------------------

# Install the sshd drop-in, drop the legacy one, and reload only a config that validates.
harden_sshd() {
    install_file "$REPO_ROOT/config/ssh/$SSHD_DROPIN" "$SSHD_DROPIN_DIR/$SSHD_DROPIN" 0644
    if [[ -e "$SSHD_DROPIN_DIR/$SSHD_LEGACY_DROPIN" ]]; then
        rm -f "$SSHD_DROPIN_DIR/$SSHD_LEGACY_DROPIN"
        log_info "Removed legacy drop-in: $SSHD_DROPIN_DIR/$SSHD_LEGACY_DROPIN"
    fi
    sshd -t || die "sshd -t rejected the sshd configuration; not reloading ssh"
    systemctl reload ssh
    log_info "sshd configuration validated and reloaded"
}

require_root
detect_ubuntu_version

log_info "===== 1. Base apt packages ====="
apt_update_once
ensure_apt_pkgs \
    build-essential cmake git curl wget unzip ca-certificates gnupg lsb-release \
    tmux byobu htop ncdu tree jq \
    python3-pip ufw software-properties-common \
    openssh-server net-tools
# Ensure sshd is running and enabled on boot.
systemctl enable --now ssh

# Harden sshd: no password auth, no root login (Tailscale SSH is primary).
harden_sshd

log_info "===== 2. gpustat ====="
if cmd_exists gpustat; then
    log_info "gpustat already installed"
else
    log_info "Installing gpustat via pip (--break-system-packages)"
    pip3 install --break-system-packages --quiet gpustat
fi

log_info "===== 3. NVIDIA driver check (manual install assumed) ====="
if ! cmd_exists nvidia-smi; then
    log_error "nvidia-smi not found. Install the NVIDIA driver manually before running this script."
    log_error "See docs/admin/setup-guide.md (NVIDIA driver section) for instructions."
    exit 1
fi
if ! nvidia-smi >/dev/null 2>&1; then
    log_error "nvidia-smi is installed but failed to run. Check kernel module / driver health."
    exit 1
fi
log_info "nvidia-smi OK: $(nvidia-smi --query-gpu=name --format=csv,noheader | head -n1)"

log_info "===== 4. Docker Engine ====="
if ! cmd_exists docker; then
    log_info "Adding Docker apt repository"
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    cat >/etc/apt/sources.list.d/docker.list <<EOF
deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME} stable
EOF
    apt-get update -qq
    ensure_apt_pkgs docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    systemctl enable --now docker
else
    log_info "Docker already installed"
fi
ensure_group docker

log_info "===== 5. NVIDIA Container Toolkit ====="
if ! pkg_installed nvidia-container-toolkit; then
    log_info "Adding NVIDIA Container Toolkit repository"
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
        | gpg --dearmor --yes -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
    curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
        | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
        > /etc/apt/sources.list.d/nvidia-container-toolkit.list
    apt-get update -qq
    ensure_apt_pkgs nvidia-container-toolkit
    nvidia-ctk runtime configure --runtime=docker
    systemctl restart docker
else
    log_info "nvidia-container-toolkit already installed"
fi

log_info "===== 6. uv ====="
if [[ -x "$UV_INSTALL_DIR/uv" ]]; then
    log_info "uv already installed at $UV_INSTALL_DIR/uv"
else
    log_info "Installing uv to $UV_INSTALL_DIR"
    curl -LsSf https://astral.sh/uv/install.sh \
        | env UV_INSTALL_DIR="$UV_INSTALL_DIR" UV_NO_MODIFY_PATH=1 sh
fi

log_info "===== 7. pixi ====="
if [[ -x "$PIXI_INSTALL_DIR/pixi" ]]; then
    log_info "pixi already installed at $PIXI_INSTALL_DIR/pixi"
else
    log_info "Installing pixi to $PIXI_INSTALL_DIR"
    curl -fsSL https://pixi.sh/install.sh \
        | env PIXI_HOME=/usr/local PIXI_NO_PATH_UPDATE=1 bash
fi

log_info "===== 8. Shared groups & directories ====="
ensure_group "$SHARED_GROUP"

mkdir -p "$SHARED_ROOT/datasets" "$SHARED_ROOT/models" "$SHARED_ROOT/workspace"
mkdir -p "$ARCHIVE_DIR" "$SCRATCH_DIR"

# /shared/datasets and /shared/models: group read, admin (root) write
chgrp -R "$SHARED_GROUP" "$SHARED_ROOT/datasets" "$SHARED_ROOT/models"
chmod 2755 "$SHARED_ROOT/datasets" "$SHARED_ROOT/models"

# /shared/workspace: group read/write + setgid so new files inherit group
chgrp -R "$SHARED_GROUP" "$SHARED_ROOT/workspace"
chmod 2775 "$SHARED_ROOT/workspace"

# /scratch: world rw + sticky
chmod 1777 "$SCRATCH_DIR"

# /archive: admin write, group read
chgrp "$SHARED_GROUP" "$ARCHIVE_DIR"
chmod 2750 "$ARCHIVE_DIR"

log_info "===== 9. Shared environment variables ====="
install_file "$REPO_ROOT/config/profile.d/lab-defaults.sh" /etc/profile.d/lab-defaults.sh 0644

log_info "===== 10. /etc/skel dotfiles ====="
install_file "$REPO_ROOT/config/skel/.bashrc"    /etc/skel/.bashrc    0644
install_file "$REPO_ROOT/config/skel/.tmux.conf" /etc/skel/.tmux.conf 0644

log_info "===== 11. Firewall (ufw) ====="
bash "$REPO_ROOT/config/ufw/rules.sh" "$LAB_LOCAL_CIDR"

log_info "===== 12. Unattended upgrades (security only) ====="
ensure_apt_pkgs unattended-upgrades
# Enable automatic updates
cat >/etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
# Restrict to security origins only (idempotent: comment out non-security lines).
sed -i \
    -e 's|^\(\s*\)"\${distro_id}:\${distro_codename}-updates";|\1// "${distro_id}:${distro_codename}-updates";|' \
    /etc/apt/apt.conf.d/50unattended-upgrades || true

log_info "===== 13. MOTD ====="
install_file "$REPO_ROOT/config/motd/99-server-status" /etc/update-motd.d/99-server-status 0755

log_info "===== 14. /scratch cleanup cron (commented out by default) ====="
cat >/etc/cron.d/scratch-cleanup <<'EOF'
# Auto-delete files in /scratch older than 30 days.
# Uncomment the line below to enable.
# 0 4 * * * root find /scratch -mindepth 1 -type f -atime +30 -delete
EOF
chmod 0644 /etc/cron.d/scratch-cleanup

log_info "===== Setup complete ====="
echo
echo "Summary:"
echo "  Ubuntu      : $UBUNTU_VERSION"
echo "  Driver      : $(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n1)"
echo "  Docker      : $(docker --version 2>/dev/null || echo missing)"
echo "  uv          : $("$UV_INSTALL_DIR/uv" --version 2>/dev/null || echo missing)"
echo "  pixi        : $("$PIXI_INSTALL_DIR/pixi" --version 2>/dev/null || echo missing)"
echo "  Shared dirs : $SHARED_ROOT, $SCRATCH_DIR, $ARCHIVE_DIR"
echo
echo "Next steps:"
echo "  - Add users:        sudo ./scripts/add-user.sh <username>"
echo "  - Tailscale:        sudo ./scripts/setup-tailscale.sh"
echo "  - Monitoring stack: sudo ./scripts/setup-monitoring.sh"
