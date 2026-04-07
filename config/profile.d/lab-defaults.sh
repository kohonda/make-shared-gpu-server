# Lab-wide defaults sourced for every login shell.
# Installed by scripts/setup.sh to /etc/profile.d/lab-defaults.sh

# Shared HuggingFace / Torch caches so users don't each download models.
export HF_HOME=/shared/models/huggingface
export TORCH_HOME=/shared/models/torch

# Default XDG cache stays in user home.
export XDG_CACHE_HOME=${XDG_CACHE_HOME:-$HOME/.cache}

# Make uv / pixi available even for non-interactive shells.
case ":$PATH:" in
    *":/usr/local/bin:"*) ;;
    *) export PATH="/usr/local/bin:$PATH" ;;
esac
