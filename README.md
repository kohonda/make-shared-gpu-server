# make-shared-gpu-server

研究室の共有 GPU サーバー（gpu01, gpu02, ...）を再現可能にセットアップするためのスクリプトとドキュメント集。

## 特徴

- **冪等なセットアップスクリプト**（Ubuntu 22.04 / 24.04 対応）
- CUDA Toolkit はホストに入れず、`uv` / `pixi` 経由で PyTorch を使う運用
- NVIDIA ドライバは **手動インストール前提**（`setup.sh` は存在チェックのみ）
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
│   ├── monitoring/         # docker compose stack
│   └── ufw/
└── docs/
    ├── admin/              # 管理者向け
    └── user/               # 利用者向け（ja / en）
```

## クイックスタート（管理者）

```bash
# 1. 事前に NVIDIA ドライバを手動インストール
sudo apt install -y nvidia-driver-550 && sudo reboot
nvidia-smi   # 動作確認

# 2. リポジトリ取得
git clone <REPO_URL> /opt/lab-gpu-server
cd /opt/lab-gpu-server

# 3. メインセットアップ
sudo ./scripts/setup.sh

# 4. Tailscale
sudo ./scripts/setup-tailscale.sh
sudo tailscale up --ssh --hostname="$(hostname)"

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
