# Lab GPU Server Setup - Implementation Spec

## Overview

研究室のGPUサーバー（gpu01, gpu02, ...）の初期セットアップを自動化するスクリプト群と、利用者向けドキュメントを作成する。

前提条件:
- Ubuntu 22.04 or 24.04 がインストール済み
- CUDA Toolkitはネイティブにインストールしない（uv/pixi経由でPyTorchを使う運用）
- NVIDIAドライバとNVIDIA Container Toolkitはシステムレベルでインストールする

## Repository Structure

```
lab-gpu-server/
├── scripts/
│   ├── setup.sh              # メインセットアップスクリプト (root実行)
│   ├── add-user.sh           # ユーザー追加スクリプト (root実行)
│   ├── setup-tailscale.sh    # Tailscaleセットアップ
│   ├── setup-monitoring.sh   # Prometheus/Grafana/exporter (docker-compose)
│   └── lib/
│       └── common.sh         # 共通関数 (ログ出力、OS判定、冪等チェック等)
├── config/
│   ├── motd/
│   │   └── 99-server-status  # ログイン時にGPU・ディスク状況を表示するスクリプト
│   ├── profile.d/
│   │   └── lab-defaults.sh   # 共有環境変数 (HF_HOME等)
│   ├── skel/                 # /etc/skel に配置する新規ユーザー用dotfiles
│   │   ├── .bashrc
│   │   └── .tmux.conf
│   ├── monitoring/
│   │   ├── docker-compose.yml  # Prometheus + Grafana + dcgm-exporter
│   │   ├── prometheus.yml
│   │   └── grafana/
│   │       └── dashboards/
│   │           └── gpu-overview.json
│   └── ufw/
│       └── rules.sh          # ファイアウォール設定
├── docs/
│   ├── admin/
│   │   ├── setup-guide.md      # 管理者向けセットアップ手順
│   │   └── add-user.md         # ユーザー追加手順
│   └── user/
│       ├── getting-started.ja.md  # 利用開始ガイド (日本語)
│       ├── getting-started.en.md  # 利用開始ガイド (English)
│       └── faq.md
└── README.md
```

## 1. `scripts/setup.sh` - Main Setup Script

root権限で実行する。冪等であること（何度実行しても安全）。

### 1.1 Install Packages

以下をapt経由でインストール:

- build-essential, cmake, git, curl, wget, unzip
- tmux, byobu, htop, ncdu, tree, jq
- gpustat (`pip install gpustat --break-system-packages`)
- ufw

### 1.2 NVIDIA Driver

- `ubuntu-drivers` を使って推奨ドライバを自動インストール
- インストール後に `nvidia-smi` で動作確認
- NVIDIA Container Toolkit もインストール

### 1.3 Docker

- Docker Engine を公式リポジトリからインストール
- `docker` グループを作成し、ユーザー追加時にこのグループに入れることでsudo不要にする
- NVIDIA Container Toolkit の Docker 連携を設定 (`nvidia-docker2` or CDI)

### 1.4 uv

- 公式インストーラで `/usr/local/bin/uv` にインストール (全ユーザーが使えるように)

### 1.5 pixi

- 公式インストーラでインストール

### 1.6 Directory Structure

```bash
mkdir -p /shared/datasets /shared/models /shared/workspace
mkdir -p /archive
mkdir -p /scratch
```

パーミッション:
- `/shared/datasets`, `/shared/models`: グループ `labmembers` に読み取り権限。書き込みはadminのみ。
- `/shared/workspace`: グループ `labmembers` に読み書き権限。setgidビットを設定して新規ファイルがグループ所有になるようにする。
- `/scratch`: 全ユーザー読み書き可。sticky bit設定。定期削除用のcronジョブ（30日以上前のファイルを削除）をコメントアウト状態で追加。
- `/archive`: adminのみ書き込み、グループ読み取り可。

### 1.7 Shared Environment Variables

`/etc/profile.d/lab-defaults.sh` を配置:

```bash
export HF_HOME=/shared/models/huggingface
export TORCH_HOME=/shared/models/torch
export XDG_CACHE_HOME=${XDG_CACHE_HOME:-$HOME/.cache}
```

### 1.8 Firewall (ufw)

- デフォルト deny incoming
- Tailscale インターフェース (`tailscale0`) からのSSHを許可
- ローカルネットワーク (例: 192.168.0.0/16) からのSSHを許可
- Grafana (3000), Prometheus (9090) はTailscale経由のみ許可

### 1.9 Unattended Upgrades

- `unattended-upgrades` をインストール・有効化
- セキュリティアップデートのみ自動適用

### 1.10 MOTD (Message of the Day)

ログイン時に以下を表示するスクリプトを `/etc/update-motd.d/99-server-status` に配置:

- ホスト名・IPアドレス
- GPU使用状況 (`nvidia-smi` or `gpustat` の簡易出力)
- ディスク使用量 (`/home`, `/shared`, `/scratch` の使用率)
- 注意事項（利用ルール等、簡潔に）

### 1.11 skel

`/etc/skel/` に以下を配置（新規ユーザー作成時に自動コピーされる）:

- `.bashrc`: uv/pixiのPATH設定、エイリアス（`gs` = `gpustat -cp`, `ns` = `nvidia-smi`）等
- `.tmux.conf`: 基本的な使いやすい設定

## 2. `scripts/add-user.sh` - Add User Script

引数: `add-user.sh <username>`

処理:
1. ユーザー作成 (`useradd -m -s /bin/bash -G labmembers,docker <username>`)
2. 初期パスワード設定（ランダム生成して表示、初回ログイン時に変更を強制）
3. `/home/<username>` のパーミッションを `700` に設定
4. SSH公開鍵の配置ディレクトリ作成 (`/home/<username>/.ssh/`, パーミッション `700`)
5. 作成結果のサマリーを表示

## 3. `scripts/setup-tailscale.sh`

- Tailscale をインストール
- `tailscale up` の実行手順を表示（認証はインタラクティブに行う必要があるため）
- SSH over Tailscale の設定ガイダンスを表示

## 4. `scripts/setup-monitoring.sh`

- `config/monitoring/docker-compose.yml` を使って以下を起動:
  - **Prometheus**: メトリクス収集
  - **Grafana**: ダッシュボード (初期パスワード設定、GPUダッシュボードをプロビジョニング)
  - **dcgm-exporter**: NVIDIA GPU メトリクスの Prometheus exporter
  - **node-exporter**: CPU/メモリ/ディスク等のシステムメトリクス
- Grafanaダッシュボードには以下を含む:
  - GPU使用率・メモリ使用量（カード別）
  - GPU温度
  - CPU/メモリ/ディスク使用率
  - ユーザー別プロセス情報（可能であれば）

## 5. Documentation

### 5.1 `docs/admin/setup-guide.md`

管理者がサーバーを初期セットアップする手順。以下を含む:

1. Ubuntuインストール後の初期手順
2. このリポジトリのclone方法
3. `setup.sh` の実行方法とオプション説明
4. Tailscaleの設定
5. 監視システムの立ち上げ
6. 初回ユーザー追加
7. トラブルシューティング

### 5.2 `docs/admin/add-user.md`

ユーザー追加・削除の手順書。

### 5.3 `docs/user/getting-started.ja.md` / `getting-started.en.md`

利用者向けの親切なドキュメント。日本語と英語の両方を作成。以下のセクションを含む:

1. **はじめに**: サーバーの概要、利用ルール
2. **SSH接続**:
   - Tailscaleのインストール（クライアント側）と接続方法
   - SSH鍵の生成と管理者への提出方法
   - `~/.ssh/config` の設定例
3. **VS Code Remote SSH**:
   - Remote-SSH拡張機能のインストール
   - 接続設定の手順（スクリーンショット的な説明を文章で丁寧に）
4. **GitHub SSH鍵の設定**:
   - サーバー上でSSH鍵を生成
   - GitHubに公開鍵を登録
   - `~/.ssh/config` でGitHub用の鍵を設定
   - 鍵のパーミッション（`/home/<user>` が `700` なので他ユーザーから見えない）
5. **Python環境**:
   - uv を使ったプロジェクト作成・パッケージ管理の基本
   - PyTorch + CUDA の使い方（`uv pip install torch` で完結することの説明）
   - pixi の基本的な使い方
6. **GPU利用**:
   - `gpustat` / `nvidia-smi` での空きGPU確認
   - `CUDA_VISIBLE_DEVICES` の使い方
   - 長時間学習は `tmux` / `byobu` を使うこと
7. **共有リソース**:
   - `/shared/datasets`, `/shared/models` の使い方
   - HuggingFace モデルは共有キャッシュ (`HF_HOME`) を使うこと
   - `/scratch` は一時ファイル用で定期削除される可能性があること
8. **Docker利用**:
   - sudo不要で使えること
   - GPUをDocker内で使う方法 (`--gpus all`)
   - 基本的な使い方
9. **GUIアクセス** (Optional):
   - ブラウザベースのリモートデスクトップ（例: noVNC or Tailscale経由のVNC）の使い方
   - Jupyter Lab をサーバーで起動してクライアントのブラウザからアクセスする方法
10. **Grafanaダッシュボード**: アクセス方法と見方
11. **トラブルシューティング / FAQ**

### 5.4 `docs/user/faq.md`

よくある質問。日英併記でOK。

## Implementation Notes

- すべてのスクリプトは `set -euo pipefail` を使用する
- ログ出力は統一フォーマット: `[INFO]`, `[WARN]`, `[ERROR]` + タイムスタンプ
- 冪等性: 既にインストール済みのものはスキップする（`command -v` や `dpkg -l` でチェック）
- Ubuntu 22.04 と 24.04 の両方をサポートする（`lsb_release` で判定）
- スクリプト内のハードコードを避け、設定は変数としてスクリプト冒頭にまとめる
- ShellCheck で lint が通ること