# Lab-wide defaults sourced for every login shell.
# Installed by scripts/setup.sh to /etc/profile.d/lab-defaults.sh, with
# @SHARED_CACHE_DIR@ replaced by that script's SHARED_CACHE_DIR.

# Shared HuggingFace hub / Torch caches so users don't each download models.
# HF_HOME stays per-user (~/.cache/huggingface): it also holds `hf auth login`
# tokens, which must not be shared. Only the hub download cache is shared.
export HF_HUB_CACHE=@SHARED_CACHE_DIR@/huggingface/hub
export TORCH_HOME=@SHARED_CACHE_DIR@/torch

# Default XDG cache stays in user home.
export XDG_CACHE_HOME=${XDG_CACHE_HOME:-$HOME/.cache}

# Make uv / pixi available even for non-interactive shells.
case ":$PATH:" in
    *":/usr/local/bin:"*) ;;
    *) export PATH="/usr/local/bin:$PATH" ;;
esac
