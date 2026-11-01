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

require_root

if ! cmd_exists docker; then
    die "docker is not installed. Run scripts/setup.sh first."
fi
if ! docker compose version >/dev/null 2>&1; then
    die "docker compose plugin missing. Run scripts/setup.sh first."
fi

if [[ ! -f "$ENV_FILE" ]]; then
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

log_info "Stack is up. Grafana: http://$BIND_ADDR:3000  Prometheus: http://$BIND_ADDR:9090"
log_info "(Published on the Tailscale IP only; dcgm-exporter publishes no host port.)"
