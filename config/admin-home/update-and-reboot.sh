#!/usr/bin/env bash
#
# Upgrade all packages (NVIDIA driver included), then reboot.
# Stops without rebooting if apt fails.
#
set -euo pipefail

sudo apt update
sudo apt upgrade -y
sudo reboot
