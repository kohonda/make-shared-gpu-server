#!/usr/bin/env bash
#
# Bring up the Prometheus + Grafana + dcgm-exporter + node-exporter stack.
#   sudo ./scripts/setup-monitoring.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

MON_DIR="$REPO_ROOT/config/monitoring"
ENV_FILE="$MON_DIR/.env"
BIND_ADDR_KEY="MON_BIND_ADDR"
UNIT_NAME="lab-monitoring.service"
UNIT_TEMPLATE="$REPO_ROOT/config/systemd/$UNIT_NAME"
UNIT_DST="/etc/systemd/system/$UNIT_NAME"
# ExecStart= splits on whitespace and expands % and $, so a path outside this set
# would give a unit that fails at every boot.
UNIT_SAFE_PATH_REGEX='^[[:alnum:]/._+@:-]+$'

# Print this host's Tailscale IPv4 address, or die when Tailscale is not up.
tailscale_ipv4() {
    local ip
    cmd_exists tailscale || die "tailscale is not installed. Run scripts/setup-tailscale.sh first."
    ip=$(tailscale ip -4 2>/dev/null | head -n1) || true
    [[ -n "$ip" ]] || die "Tailscale is not running (tailscale ip -4 returned nothing). Bring it up first."
    printf '%s\n' "$ip"
}

# Set KEY=VALUE in an env file, replacing an existing KEY= line or appending one.
set_env_value() {
    local file="$1" key="$2" value="$3"
    if grep -q "^${key}=" "$file"; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$file"
    else
        printf '%s=%s\n' "$key" "$value" >>"$file"
    fi
}

# Install and enable the unit that re-runs this script at boot. It is not started
# now: the stack is already up.
install_boot_unit() {
    local rendered_unit
    if [[ ! "$REPO_ROOT" =~ $UNIT_SAFE_PATH_REGEX ]]; then
        log_warn "Not installing $UNIT_NAME: systemd cannot run a script under '$REPO_ROOT'."
        log_warn "The stack will not start by itself after a reboot. Move the repository and re-run."
        return 0
    fi
    rendered_unit=$(mktemp)
    sed "s|@REPO_ROOT@|${REPO_ROOT}|g" "$UNIT_TEMPLATE" >"$rendered_unit"
    install_file "$rendered_unit" "$UNIT_DST"
    rm -f "$rendered_unit"
    systemctl daemon-reload
    systemctl enable "$UNIT_NAME"
}

require_root

if ! cmd_exists docker; then
    die "docker is not installed. Run scripts/setup.sh first."
fi
if ! docker compose version >/dev/null 2>&1; then
    die "docker compose plugin missing. Run scripts/setup.sh first."
fi

if [[ ! -f "$ENV_FILE" ]]; then
    # Copying here would let the unit's next retry start Grafana with the
    # placeholder password from .env.example.
    [[ -z "${INVOCATION_ID:-}" ]] || die "$ENV_FILE not found. Create it from .env.example."
    log_warn ".env not found. Copying from .env.example."
    cp "$MON_DIR/.env.example" "$ENV_FILE"
    log_warn "Edit $ENV_FILE to set GF_SECURITY_ADMIN_PASSWORD before continuing."
    exit 1
fi

BIND_ADDR=$(tailscale_ipv4)
set_env_value "$ENV_FILE" "$BIND_ADDR_KEY" "$BIND_ADDR"
log_info "Grafana / Prometheus will bind to $BIND_ADDR ($BIND_ADDR_KEY in $ENV_FILE)"

log_info "Starting monitoring stack with docker compose"
# Pass the address in the environment too: Compose prefers an exported variable
# over --env-file, so an inherited MON_BIND_ADDR could otherwise widen the bind.
( cd "$MON_DIR" && env "$BIND_ADDR_KEY=$BIND_ADDR" docker compose --env-file .env up -d )

if [[ -z "${INVOCATION_ID:-}" ]]; then
    install_boot_unit
else
    log_info "Running from a systemd unit (INVOCATION_ID set); not reinstalling $UNIT_NAME"
fi

log_info "Stack is up. Grafana: http://$BIND_ADDR:3000  Prometheus: http://$BIND_ADDR:9090"
log_info "(Published on the Tailscale IP only; dcgm-exporter publishes no host port.)"
