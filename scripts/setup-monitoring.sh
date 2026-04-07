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

require_root

if ! cmd_exists docker; then
    die "docker is not installed. Run scripts/setup.sh first."
fi
if ! docker compose version >/dev/null 2>&1; then
    die "docker compose plugin missing. Run scripts/setup.sh first."
fi

MON_DIR="$REPO_ROOT/config/monitoring"
ENV_FILE="$MON_DIR/.env"

if [[ ! -f "$ENV_FILE" ]]; then
    log_warn ".env not found. Copying from .env.example."
    cp "$MON_DIR/.env.example" "$ENV_FILE"
    log_warn "Edit $ENV_FILE to set GF_SECURITY_ADMIN_PASSWORD before continuing."
    exit 1
fi

log_info "Starting monitoring stack with docker compose"
( cd "$MON_DIR" && docker compose --env-file .env up -d )

log_info "Stack is up. Grafana: http://<host>:3000  Prometheus: http://<host>:9090"
log_info "(Both ports are restricted to the tailscale0 interface by ufw.)"
