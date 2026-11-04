# Getting Started (English)

Welcome to the lab GPU server. This guide walks first-time users through connecting, setting up Python, and using the GPUs.

> Japanese version: [getting-started.ja.md](getting-started.ja.md)

## 1. House rules

- The server is shared. **Do not hog GPUs** or kill other users' jobs.
- Put large datasets and models under `/shared`, not in your home directory.
- Always run long jobs inside `tmux` or `byobu` so they survive disconnection.
- See [faq.md](faq.md) when stuck.

## 2. SSH access

Access uses **Tailscale SSH**. No password, no SSH key — authentication is done via the account you are logged in to Tailscale with (Google account, etc.).

### 2.1 Install Tailscale (your laptop)

Download from <https://tailscale.com/download> and install the app. Receive the machine share (Share) invitation from the admin and accept it. You keep using your own tailnet, and only the shared server becomes visible.

After installation, log in for the first time:

- **Desktop app (Windows / macOS)**: launch the app — a browser opens for Google account login
- **Linux CLI**: run the command below and open the printed URL in a browser (it changes the state of tailscaled, so it needs `sudo`)

```bash
sudo tailscale login
```

After login, once you have accepted the share, the shared server (e.g. `gpu01`) appears in the `tailscale status` list. If it shows up, you're ready.

```bash
tailscale status
```

#### If the admin invited you to the lab tailnet (Fast User Switching)

**You do not need this if you were onboarded via a share (Share).** It is only for people the admin invited to the lab tailnet itself who also use their own personal tailnet. The Tailscale client can hold several accounts and switch between them (source: [Fast user switching](https://tailscale.com/kb/1225/fast-user-switching)).

- **Add an account**
  - macOS: Tailscale icon in the menu bar → **Settings** → **Accounts** → **Add Account**
  - Windows: Tailscale icon in the system tray → the current account → **Add another account**
  - Linux: `sudo tailscale login` (log in, in the browser that opens, with the account invited to the lab tailnet)
- **Switch**
  - macOS / Windows: pick the account from the menu above
  - Linux: `sudo tailscale switch <account>`
- **List accounts**: `tailscale switch --list` (`*` marks the active account; on Linux add `sudo`)

> ⚠️ Only **one account can be active at a time**. While you are switched to your personal tailnet, the lab servers are unreachable. Switch back to the lab tailnet to use them.

### 2.2 Tailscale basics

Once logged in, a VPN tunnel is established automatically and you can reach the server. The server runs Tailscale 24/7, so **as long as Tailscale is running on your machine, you can SSH in**.

Common commands:

```bash
tailscale status                     # list your tailnet's machines and machines shared with you, with connection state
tailscale ip -4                      # show your Tailscale IPv4 address
sudo tailscale login                 # first-time login (opens browser for auth)
sudo tailscale logout                # log out (requires login again to reconnect)
sudo tailscale up                    # start VPN (use after a disconnect)
sudo tailscale down                  # stop VPN (server becomes unreachable)
tailscale ping <host>.<tailnet>.ts.net   # check connectivity to a specific machine (use the FQDN or IP for a shared server)
```

On the Linux CLI only the commands that change the state of tailscaled (`login` / `logout` / `up` / `down`) need `sudo`. `status` / `ip` / `ping` work without it. The desktop apps (Windows / macOS) offer the same actions in their menu.

- **On boot**: if the desktop app is set to auto-start, VPN is established at login
- **After `sudo tailscale down`**: VPN stays off until you explicitly run `sudo tailscale up`
- **Network changes** (Wi-Fi → Ethernet, etc.): Tailscale reconnects automatically

### 2.3 Get an account

Ask the admin to create your Linux account (e.g. `alice`) on the server. You don't need to send an SSH public key.

### 2.4 Connect

```bash
ssh <username>@<host>.<tailnet>.ts.net
# e.g. ssh alice@gpu01.<tailnet>.ts.net
# You can also use the Tailscale IP: ssh alice@100.x.x.x
```

If you were onboarded via a share (Share), the server is reachable **only by its FQDN (`<host>.<tailnet>.ts.net`) or its Tailscale IP**. Use the exact FQDN from the connection details the admin gives you.

> 💡 People invited to the lab tailnet (tailnet members) can also connect with a short name such as `ssh alice@gpu01`.

The first connection may open a browser for Tailscale auth (auto-approved if you're already logged in). No password / key prompt.

Optional `~/.ssh/config`:

```text
Host gpu01
    HostName gpu01.<tailnet>.ts.net   # the server's FQDN (see `tailscale status`)
    User <your-username>
    ServerAliveInterval 60
```

> ⚠️ Set `HostName` to the server's **FQDN (`<host>.<tailnet>.ts.net`) or Tailscale IP (e.g. `100.x.x.x`)** from the admin. The short name shown in `tailscale status` (`gpu01`) does not reach the server if you were onboarded via a share. Also, do NOT set it to a name that resolves to your own machine (would give `Connection refused`).

### 2.5 sudo / password

Regular users have no password (locked with `passwd -l`). If you ever need `sudo`, ask the admin to set a password for you.

## 3. VS Code Remote SSH

1. Install the **Remote - SSH** extension
2. Bottom-left blue button → **Remote-SSH: Connect to Host...**
3. Pick `gpu01` (the name in your `~/.ssh/config`, whose `HostName` is the FQDN or Tailscale IP). Without a `~/.ssh/config` entry, type `alice@gpu01.<tailnet>.ts.net` directly
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

### Sharing GPUs with others

- Check free GPUs with `gs` before launching, and stay off GPUs someone else is using
- Always restrict your job with `CUDA_VISIBLE_DEVICES` (above)
- Do not fill a GPU's memory; when sharing a GPU, keep usage down (batch size, or PyTorch's `torch.cuda.set_per_process_memory_fraction`)
- Stop finished jobs and idle Jupyter kernels so the GPU is released

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
| `/shared/workspace`| Collaboration         | lab rw (including files others created) |
| `/shared/cache`    | Shared HuggingFace hub / Torch caches (`$HF_HUB_CACHE`, `$TORCH_HOME`) | lab rw |
| `/scratch`         | Scratch (may be cleaned after 30 days) | world rw, sticky |
| `/archive`         | Archive (admin writes)| lab read |

`HF_HUB_CACHE` is set to `/shared/cache/huggingface/hub` (and `TORCH_HOME` to `/shared/cache/torch`) system-wide, so HuggingFace downloads are cached for everyone automatically. `HF_HOME` stays in your home (`~/.cache/huggingface`), so a token saved by `hf auth login` is yours alone.

## 8. Docker

Docker requires permission from an admin. Ask an admin if you need it. Once allowed, you can use it **without sudo** from your next login.

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
# laptop (gpu01 is the ~/.ssh/config alias; without it use alice@gpu01.<tailnet>.ts.net)
ssh -N -L 8888:localhost:8888 gpu01
# open http://localhost:8888
```

VS Code Remote SSH handles `.ipynb` natively. For full remote desktop, set up noVNC / x11vnc yourself over Tailscale (ask the admin first).

## 10. Grafana

If the monitoring stack is running, browse `http://<host>.<tailnet>.ts.net:3000` (or `http://<Tailscale IP>:3000`) over Tailscale to see GPU utilization, temperature, memory and host load.
No login is needed. You can view the dashboards but not edit them.

Use it to check which GPUs are free before you start a job.

## 11. FAQ

See [faq.md](faq.md).
