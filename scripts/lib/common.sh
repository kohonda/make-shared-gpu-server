#!/usr/bin/env bash
# Common helper functions for lab GPU server setup scripts.
# Source this file from other scripts: `source "$(dirname "$0")/lib/common.sh"`

# Colors (only when stdout is a tty)
if [[ -t 1 ]]; then
    _C_RESET=$'\033[0m'
    _C_INFO=$'\033[32m'
    _C_WARN=$'\033[33m'
    _C_ERR=$'\033[31m'
else
    _C_RESET=""; _C_INFO=""; _C_WARN=""; _C_ERR=""
fi

_ts() { date +'%Y-%m-%d %H:%M:%S'; }

log_info()  { printf '%s%s [INFO]%s  %s\n'  "$_C_INFO" "$(_ts)" "$_C_RESET" "$*"; }
log_warn()  { printf '%s%s [WARN]%s  %s\n'  "$_C_WARN" "$(_ts)" "$_C_RESET" "$*" >&2; }
log_error() { printf '%s%s [ERROR]%s %s\n'  "$_C_ERR"  "$(_ts)" "$_C_RESET" "$*" >&2; }

die() { log_error "$*"; exit 1; }

require_root() {
    if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
        die "This script must be run as root (try: sudo $0)"
    fi
}

cmd_exists() { command -v "$1" >/dev/null 2>&1; }

pkg_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}

# Install apt packages if missing. Accepts multiple package names.
ensure_apt_pkgs() {
    local missing=()
    local p
    for p in "$@"; do
        if ! pkg_installed "$p"; then
            missing+=("$p")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_info "Installing apt packages: ${missing[*]}"
        DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${missing[@]}"
    else
        log_info "apt packages already installed: $*"
    fi
}

apt_update_once() {
    if [[ -z "${_APT_UPDATED:-}" ]]; then
        log_info "Running apt-get update"
        apt-get update -qq
        _APT_UPDATED=1
    fi
}

# Detect Ubuntu version. Exports UBUNTU_VERSION (e.g. "22.04") and UBUNTU_CODENAME.
detect_ubuntu_version() {
    if [[ ! -r /etc/os-release ]]; then
        die "/etc/os-release not found; cannot detect OS"
    fi
    # shellcheck disable=SC1091
    . /etc/os-release
    if [[ "${ID:-}" != "ubuntu" ]]; then
        die "This script only supports Ubuntu (detected: ${ID:-unknown})"
    fi
    UBUNTU_VERSION="${VERSION_ID:-}"
    UBUNTU_CODENAME="${VERSION_CODENAME:-}"
    case "$UBUNTU_VERSION" in
        22.04|24.04) ;;
        *) die "Unsupported Ubuntu version: $UBUNTU_VERSION (supported: 22.04, 24.04)" ;;
    esac
    export UBUNTU_VERSION UBUNTU_CODENAME
    log_info "Detected Ubuntu $UBUNTU_VERSION ($UBUNTU_CODENAME)"
}

# Ensure a unix group exists.
ensure_group() {
    local g="$1"
    if getent group "$g" >/dev/null; then
        log_info "Group already exists: $g"
    else
        log_info "Creating group: $g"
        groupadd "$g"
    fi
}

# Install a file from src to dst with given mode, only if changed.
install_file() {
    local src="$1" dst="$2" mode="${3:-0644}"
    if [[ -f "$dst" ]] && cmp -s "$src" "$dst"; then
        log_info "Up-to-date: $dst"
    else
        install -D -m "$mode" "$src" "$dst"
        log_info "Installed: $dst (mode $mode)"
    fi
}
