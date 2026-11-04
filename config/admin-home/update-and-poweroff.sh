#!/usr/bin/env bash
#
# Upgrade all packages (NVIDIA driver included), then power off.
# Stops without powering off if apt fails.
#
set -euo pipefail

sudo apt update
sudo apt upgrade -y
sudo poweroff
