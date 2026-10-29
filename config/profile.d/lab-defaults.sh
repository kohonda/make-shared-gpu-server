# Lab-wide defaults sourced for every login shell.
# Installed by scripts/setup.sh to /etc/profile.d/lab-defaults.sh

# Shared HuggingFace / Torch caches so users don't each download models.
# scripts/setup.sh creates these group-writable (setgid + default ACL) under
# SHARED_CACHE_DIR; keep the two paths in sync if that variable is changed.
export HF_HOME=/shared/cache/huggingface
export TORCH_HOME=/shared/cache/torch

# Default XDG cache stays in user home.
export XDG_CACHE_HOME=${XDG_CACHE_HOME:-$HOME/.cache}

# Make uv / pixi available even for non-interactive shells.
case ":$PATH:" in
    *":/usr/local/bin:"*) ;;
    *) export PATH="/usr/local/bin:$PATH" ;;
esac
