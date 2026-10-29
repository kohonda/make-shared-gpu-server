@AGENTS.md

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Reproducible setup suite for shared GPU servers in a research lab (gpu01, gpu02, ...). Targets Ubuntu 22.04/24.04. All scripts are idempotent Bash with `set -euo pipefail`.

Key design decisions:
- **No system CUDA Toolkit** -- PyTorch is installed per-project via `uv` or `pixi`
- **NVIDIA drivers are installed manually** -- `setup.sh` only checks their presence
- **Tailscale SSH is the sole access method** -- no passwords, no SSH key distribution
- **Monitoring stack (Prometheus + Grafana + dcgm-exporter) is optional**

## Commands

```bash
# Main server setup (requires root, idempotent)
sudo ./scripts/setup.sh

# Add a lab user (Tailscale SSH only, no password)
sudo ./scripts/add-user.sh <username>

# Install & configure Tailscale (interactive — opens auth URL)
sudo ./scripts/setup-tailscale.sh

# Install & configure Tailscale (headless — auth key, no browser needed)
TAILSCALE_AUTHKEY=tskey-auth-XXXX sudo -E ./scripts/setup-tailscale.sh

# Launch monitoring stack (requires config/monitoring/.env)
sudo ./scripts/setup-monitoring.sh

# Lint all shell scripts
shellcheck scripts/*.sh scripts/lib/*.sh
```

## Architecture

```
scripts/
  setup.sh              # Main setup: packages, Docker, nvidia-container-toolkit, uv, pixi, ufw, skel
  add-user.sh           # Create user in labmembers+docker groups, lock password, home 750
  setup-tailscale.sh    # Install Tailscale, print interactive auth instructions
  setup-monitoring.sh   # docker compose up for monitoring stack
  lib/common.sh         # Shared helpers: logging (INFO/WARN/ERROR), root check, pkg detection, Ubuntu version

config/
  monitoring/           # Docker Compose stack: prometheus, grafana, dcgm-exporter, node-exporter
  profile.d/            # System-wide env vars (HF_HOME, TORCH_HOME) -> /etc/profile.d/
  skel/                 # New user dotfiles (.bashrc, .tmux.conf) -> /etc/skel/
  motd/                 # Login banner (GPU status, disk usage) -> /etc/update-motd.d/
  ssh/                  # sshd hardening (no password, no root) -> /etc/ssh/sshd_config.d/00-lab.conf
  apt/                  # unattended-upgrades NVIDIA blacklist -> /etc/apt/apt.conf.d/
  ufw/                  # Firewall rules (SSH+monitoring on tailscale0 only)

docs/
  admin/                # Setup guide, user management procedures
  user/                 # Getting-started guides (ja/en), FAQ
```

Scripts source `scripts/lib/common.sh` for shared functions. Config files under `config/` are copied to their system destinations by `setup.sh`.

## Conventions

- All scripts use `set -euo pipefail` and must pass `shellcheck`
- Logging format: `[INFO]`, `[WARN]`, `[ERROR]` with timestamps (use helpers from `lib/common.sh`)
- Idempotency: check before acting (`command -v`, `dpkg -l`, `id`, `getent group`)
- Support both Ubuntu 22.04 and 24.04 (detect via `lsb_release`)
- Configuration variables go at the top of each script, not hardcoded inline
- User docs are bilingual (Japanese and English)
