# make-shared-gpu-server

研究室の共有 GPU サーバー（gpu01, gpu02, ...）を再現可能にセットアップするためのスクリプトとドキュメント集。

## 特徴

- **冪等なセットアップスクリプト**（Ubuntu 22.04 / 24.04 対応）
- CUDA Toolkit はホストに入れず、`uv` / `pixi` 経由で PyTorch を使う運用
- NVIDIA ドライバは **手動インストール前提**（`setup.sh` は存在チェックのみ）
- 全利用者が使える CLI ツール（`gh`（公式 apt リポジトリの最新版）, ffmpeg, nvtop, git-lfs, rsync, vim, zip, p7zip-full, pigz, aria2）。構成は [kohonda/make-ubuntu-setup](https://github.com/kohonda/make-ubuntu-setup) を参考にしている
- Docker + NVIDIA Container Toolkit
- Tailscale + ufw による安全なリモートアクセス
- Prometheus + Grafana + dcgm-exporter による監視（任意起動）
- 利用者向けの日英ドキュメント

## ディレクトリ構成

```text
.
├── scripts/                # セットアップスクリプト
│   ├── setup.sh            # メイン
│   ├── add-user.sh         # ユーザー追加
│   ├── setup-tailscale.sh
│   ├── setup-monitoring.sh
│   └── lib/common.sh
├── config/                 # 配布する設定ファイル
│   ├── motd/
│   ├── profile.d/
│   ├── skel/
│   ├── ssh/                # sshd ハードニング (00-lab.conf)
│   ├── apt/                # unattended-upgrades の NVIDIA blacklist
│   ├── monitoring/         # docker compose stack
│   └── ufw/
└── docs/
    ├── admin/              # 管理者向け
    └── user/               # 利用者向け（ja / en）
```

## クイックスタート（管理者）

```bash
# 1. 事前に NVIDIA ドライバを手動インストール
# https://ubuntu.com/server/docs/how-to/graphics/install-nvidia-drivers/
sudo ubuntu-drivers list
sudo ubuntu-drivers install
reboot
nvidia-smi   # 動作確認

# 2. リポジトリ取得（置き場所は任意。管理者ホーム配下で OK）
git clone <REPO_URL> ~/make-shared-gpu-server
cd ~/make-shared-gpu-server

# 3. Tailscale（setup.sh より先に。ufw は SSH を tailscale0 からしか通さない）
#    事前に ACL の tagOwners に tag:server を定義しておく（setup-guide §3）
sudo ./scripts/setup-tailscale.sh
sudo tailscale up --ssh --hostname="$(hostname)" --advertise-tags=tag:server
# ヘッドレスなら: TAILSCALE_AUTHKEY=tskey-auth-XXXX sudo -E ./scripts/setup-tailscale.sh

# 4. メインセットアップ
sudo ./scripts/setup.sh

# 5. 監視（任意）
cp config/monitoring/.env.example config/monitoring/.env
$EDITOR config/monitoring/.env
sudo ./scripts/setup-monitoring.sh

# 6. ユーザー追加
sudo ./scripts/add-user.sh alice
```

詳細は [docs/admin/setup-guide.md](docs/admin/setup-guide.md)。

## ドキュメント

- 管理者: [setup-guide.md](docs/admin/setup-guide.md), [add-user.md](docs/admin/add-user.md)
- 利用者: [getting-started.ja.md](docs/user/getting-started.ja.md) / [getting-started.en.md](docs/user/getting-started.en.md), [faq.md](docs/user/faq.md)
