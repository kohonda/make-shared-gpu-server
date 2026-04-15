# Getting Started (English)

Welcome to the lab GPU server. This guide walks first-time users through connecting, setting up Python, and using the GPUs.

> Japanese version: [getting-started.ja.md](getting-started.ja.md)

## 1. House rules

- The server is shared. **Do not hog GPUs** or kill other users' jobs.
- Put large datasets and models under `/shared`, not in your home directory.
- Always run long jobs inside `tmux` or `byobu` so they survive disconnection.
- See [faq.md](faq.md) when stuck.

## 2. SSH access

Access uses **Tailscale SSH**. No password, no SSH key — authentication is done via your tailnet identity (Google account, etc.).

### 2.1 Install Tailscale (your laptop)

Download from <https://tailscale.com/download> and install the app. Ask the admin for a tailnet invite.

After installation, log in for the first time:

- **Desktop app (Windows / macOS)**: launch the app — a browser opens for Google account login
- **Linux CLI**: run the command below and open the printed URL in a browser

```bash
tailscale login
```

After login, run `tailscale status`. If `<server-name>` shows up, you're ready.

```bash
tailscale status
```

### 2.2 Tailscale basics

Once logged in, a VPN tunnel is established automatically and you can reach the server. The server runs Tailscale 24/7, so **as long as Tailscale is running on your machine, you can SSH in**.

Common commands:

```bash
tailscale status          # list machines and connection state in the tailnet
tailscale ip -4           # show your Tailscale IPv4 address
tailscale login           # first-time login (opens browser for auth)
tailscale logout          # log out (requires login again to reconnect)
tailscale up              # start VPN (use after a disconnect)
tailscale down            # stop VPN (server becomes unreachable)
tailscale ping <server>   # check connectivity to a specific machine
```

- **On boot**: if the desktop app is set to auto-start, VPN is established at login
- **After `tailscale down`**: VPN stays off until you explicitly run `tailscale up`
- **Network changes** (Wi-Fi → Ethernet, etc.): Tailscale reconnects automatically

### 2.3 Get an account

Ask the admin to create your Linux account (e.g. `alice`) on the server. You don't need to send an SSH public key.

### 2.4 Connect

```bash
ssh <username>@<server-tailnet-name>
# e.g. ssh alice@gpu01
# You can also use the Tailscale IP: ssh alice@100.x.x.x
```

The first connection may open a browser for Tailscale auth (auto-approved if you're already logged in). No password / key prompt.

Optional `~/.ssh/config`:

```text
Host gpu01
    HostName gpu01              # tailnet machine name (see `tailscale status`)
    User <your-username>
    ServerAliveInterval 60
```

> ⚠️ Do NOT set `HostName` to a name that resolves to your own machine (would give `Connection refused`). Use the name from `tailscale status` or the IP from `tailscale ip -4` (e.g. `100.x.x.x`).

### 2.5 sudo / password

Regular users have no password (locked with `passwd -l`). If you ever need `sudo`, ask the admin to set a password for you.

## 3. VS Code Remote SSH

1. Install the **Remote - SSH** extension
2. Bottom-left blue button → **Remote-SSH: Connect to Host...**
3. Pick `gpu01`
4. First connect installs VS Code Server remotely (~30s)
5. `File → Open Folder` to browse your home

The integrated terminal runs on the server.

## 4. GitHub SSH key (on the server)

To `git push` from the server, generate a separate key there:

```bash
ssh-keygen -t ed25519 -C "<your-username>@gpu01" -f ~/.ssh/id_ed25519_github
cat ~/.ssh/id_ed25519_github.pub
```

Add the printed key at <https://github.com/settings/keys>.

`~/.ssh/config`:

```
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519_github
    IdentitiesOnly yes
```

Test: `ssh -T git@github.com`.

> 💡 Your home directory is mode 750 and owned by a private per-user group, so nobody else on the machine can read your files (including private keys).

## 5. Python environment (uv / pixi)

There is **no system CUDA Toolkit**. Use `uv` or `pixi` to install PyTorch with bundled CUDA.

### uv

```bash
mkdir myproject && cd myproject
uv init
uv python install 3.11
uv add torch torchvision
uv run python -c "import torch; print(torch.cuda.is_available())"
```

### pixi

```bash
pixi init myproject
cd myproject
pixi add python=3.11 pytorch
pixi run python my_script.py
```

## 6. Using GPUs

### Check usage

```bash
gs        # gpustat -cp (alias)
ns        # nvidia-smi (alias)
nsl       # watch -n 1 nvidia-smi
```

### Pin to specific GPUs

```bash
CUDA_VISIBLE_DEVICES=0    python train.py
CUDA_VISIBLE_DEVICES=1,3  python train.py
```

Always set this so you don't accidentally grab every GPU.

### tmux for long jobs

```bash
tmux new -s train
# launch training inside
# Ctrl+b then d to detach
tmux attach -t train
```

## 7. Shared resources

| Path | Purpose | Permissions |
|---|---|---|
| `/shared/datasets` | Datasets (read-only) | lab read |
| `/shared/models`   | Pretrained models     | lab read |
| `/shared/workspace`| Collaboration         | lab rw  |
| `/scratch`         | Scratch (may be cleaned after 30 days) | world rw, sticky |
| `/archive`         | Archive (admin writes)| lab read |

`HF_HOME` is set to `/shared/models/huggingface` system-wide, so HuggingFace downloads are cached for everyone automatically.

## 8. Docker

You're in the `docker` group, so **no sudo needed**.

```bash
docker run --rm hello-world
docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi
```

Example research image:

```bash
docker run --rm -it --gpus all \
    -v /shared/datasets:/data:ro \
    -v $HOME/work:/workspace \
    pytorch/pytorch:2.4.0-cuda12.1-cudnn9-runtime bash
```

## 9. Jupyter / GUI (optional)

Run Jupyter on the server, port-forward from your laptop:

```bash
# server
jupyter lab --no-browser --port 8888 --ip 127.0.0.1
```

```bash
# laptop
ssh -N -L 8888:localhost:8888 gpu01
# open http://localhost:8888
```

VS Code Remote SSH handles `.ipynb` natively. For full remote desktop, set up noVNC / x11vnc yourself over Tailscale (ask the admin first).

## 10. Grafana

If the monitoring stack is running, browse `http://<server>:3000` over Tailscale to see GPU utilization, temperature, memory and host load.
Log in with the username and password provided by your server administrator.

## 11. FAQ

See [faq.md](faq.md).
