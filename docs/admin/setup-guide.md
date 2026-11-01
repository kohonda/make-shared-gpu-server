# 管理者向けセットアップガイド

研究室GPUサーバー（gpu01, gpu02, ...）の初期セットアップ手順。

## 0. 前提

- Ubuntu **22.04** または **24.04** がインストール済み
- root もしくは sudo 権限のあるアカウント
- インターネット接続あり

## 1. NVIDIAドライバの手動インストール

`setup.sh` は **ドライバを自動インストールしません**（過去にトラブルが多いため）。事前に手動で入れてください。

```bash
# 推奨ドライバを確認
ubuntu-drivers devices

# 推奨版をインストール（例: nvidia-driver-550）
sudo apt update
sudo apt install -y nvidia-driver-550

# 再起動
sudo reboot

# 起動後に確認
nvidia-smi
```

`nvidia-smi` で GPU 一覧が表示されれば OK。`setup.sh` はこの存在をチェックし、無ければエラー終了します。

## 2. リポジトリの取得

置き場所はどこでも構いません（スクリプトは自身のパスを `$BASH_SOURCE` から解決するので、`cd` して `sudo ./scripts/setup.sh` を実行できる場所ならよい）。管理者のホーム配下に置くのが一番楽です。

```bash
sudo apt install -y git
git clone git@github.com:kohonda/make-shared-gpu-server.git
cd make-shared-gpu-server
```

> 📝 初期セットアップ後もリポジトリは残しておいてください。設定を更新したいときは `git pull` して `sudo ./scripts/setup.sh` を再実行すれば冪等に反映されます（`/etc/` 等への配布物はリポジトリ内の `config/` が元ネタになっています）。
>
> `/opt/` や `/usr/local/src/` に置いても動きますが、必須ではありません。書き込み権限の都合でむしろ管理者ホームの方が扱いやすいことが多いです。

## 3. Tailscale のセットアップ（setup.sh より先に）

`setup.sh` の ufw 設定は SSH を `tailscale0` からしか許可しません。そのため **Tailscale を先に上げます**。`setup-tailscale.sh` は `setup.sh` に依存しません。`tailscale0` が無い状態で `setup.sh` を実行した場合、ufw は変更されず（有効化もリセットもされず）WARN が出ます。その場合は Tailscale を上げてから `setup.sh` を再実行してください。

### 事前準備: ACL の tagOwners

サーバーは `tag:server` タグ付きで登録します。タグを付けるには、ACL（<https://login.tailscale.com/admin/acls/file>）の `tagOwners` にそのタグが定義されている必要があります。無いと `tailscale up --advertise-tags=tag:server` が失敗します。

```jsonc
"tagOwners": {
    "tag:server": ["autogroup:admin"],
},
```

タグ名は環境変数 `TAILSCALE_TAGS` で変えられます（既定 `tag:server`）。

### 方法A: 対話式（ブラウザが使える場合）

```bash
sudo ./scripts/setup-tailscale.sh
sudo tailscale up --ssh --hostname="$(hostname)" --advertise-tags=tag:server
```

表示される URL を開いて tailnet に登録します。`--advertise-tags=tag:server` により、ACL の SSH ルールで `dst: ["tag:server"]` として参照できます。

### 方法B: Auth Key（ヘッドレス／ブラウザなしの場合）

1. 別のPCで Tailscale 管理画面 <https://login.tailscale.com/admin/settings/keys> を開く
2. **Generate auth key** をクリックしてキーを生成（Reusable にすると複数台に使い回せる）
3. サーバーで以下を実行:

```bash
TAILSCALE_AUTHKEY=tskey-auth-XXXX sudo -E ./scripts/setup-tailscale.sh
```

スクリプトが自動的に `tailscale up --ssh --advertise-tags=tag:server` を実行し、tailnet に参加します。すでに Running の状態で再実行した場合は `tailscale up` をスキップします。

### tailnet の管理

セットアップ後、Tailscale 管理画面 <https://login.tailscale.com/admin/machines> でマシンを確認し、lab メンバーを **Users → Invite users** で招待してください。必要に応じて ACL で SSH 権限を絞ります。

### SSH 運用ポリシー

本サーバーの SSH アクセスは **Tailscale SSH オンリー** です。

- **ufw**: 22 番ポートは `tailscale0` インターフェースからのみ許可。LAN からの SSH も塞いでいます。
- **Tailscale SSH**: `tailscale up --ssh` により tailnet 経由の SSH 接続は Tailscale が直接処理します。認証は **tailnet のアイデンティティ**（Google 等）で行われ、Linux 側のパスワード・`authorized_keys` は参照されません。
- **sshd ハードニング**: 万一 Tailscale SSH が停止し LAN 経由を開けた場合でも平文パスワードで入れないよう、`/etc/ssh/sshd_config.d/00-lab.conf` で `PasswordAuthentication no` / `PermitRootLogin no` を強制しています。sshd は各設定項目について最初に読んだ値を使うため、`50-cloud-init.conf` より先に読まれる `00-` の名前にしています。`setup.sh` は旧 `99-lab.conf` を削除し、`sshd -t` で検証してから reload します。
- **結果**: 利用者の受け入れは「`add-user.sh` でアカウント作成 → tailnet に招待」だけで完了します。初期パスワードも公開鍵も不要です。

## 4. メインセットアップの実行

```bash
sudo ./scripts/setup.sh
```

実行内容:

1. 基本パッケージ（build-essential, tmux, htop, acl, openssh-server 等）と全利用者向けの CLI ツール（ffmpeg, nvtop, git-lfs, rsync, vim, zip, p7zip-full, pigz, aria2）、sshd ハードニング（`PasswordAuthentication no` 他）
2. GitHub CLI（`gh`、公式 apt リポジトリから最新版）
3. NVIDIA ドライバ存在チェック
4. Docker Engine
5. NVIDIA Container Toolkit
6. uv（`/usr/local/bin` に配置）
7. gpustat（`uv tool install`。環境は `/opt/uv-tools`、コマンドは `/usr/local/bin`）
8. pixi（`/usr/local/bin` に配置）
9. グループ `labmembers`、共有ディレクトリ（`/shared/{datasets,models,workspace}`, `/shared/cache/{huggingface/hub,torch}`, `/scratch`, `/archive`）。`/shared/workspace` と `/shared/cache/*` は setgid と default ACL で、他人が作ったファイルも共同編集できます
10. 共有環境変数 (`/etc/profile.d/lab-defaults.sh`。`HF_HUB_CACHE` / `TORCH_HOME` を `/shared/cache` に向ける。`HF_HOME` はトークンを含むので各自のホームのまま)
11. `/etc/skel/` の dotfiles
12. ufw 設定（SSH は tailscale0 のみ許可。tailscale0 が無ければ変更せず WARN）
13. unattended-upgrades（セキュリティ更新。NVIDIA 関連パッケージは blacklist で除外）
14. MOTD
15. `/scratch` クリーンアップ用 cron（コメントアウト状態）

> NVIDIA ドライバは手動管理です。unattended-upgrades は `nvidia-*` / `libnvidia-*` / `linux-modules-nvidia-*` を更新しません（ユーザー空間ライブラリだけが上がると "Driver/library version mismatch" になるため）。ドライバの更新は §1 の手順で手動で行い、再起動してください。

冪等です。何度実行しても安全。

パッケージ構成は管理者の個人マシン用セットアップ [kohonda/make-ubuntu-setup](https://github.com/kohonda/make-ubuntu-setup) を参考にしています（サーバーからは clone も呼び出しもしません）。

### 環境変数で挙動を調整

スクリプト冒頭の変数は環境変数で上書きできます。

```bash
SHARED_GROUP=mylab ARCHIVE_DIR=/mnt/archive sudo -E ./scripts/setup.sh
# SHARED_GROUP を変えた場合は add-user.sh にも同じ値を渡す
SHARED_GROUP=mylab sudo -E ./scripts/add-user.sh alice
```

## 5. 監視スタック（Prometheus + Grafana）

任意。GPU/ホストメトリクスを Grafana で見たい場合に起動します。

```bash
cd config/monitoring
cp .env.example .env
# GF_SECURITY_ADMIN_PASSWORD を編集
cd ../..
sudo ./scripts/setup-monitoring.sh
```

`setup-monitoring.sh` は `tailscale ip -4` の値を `.env` の `MON_BIND_ADDR` に書き込み、Grafana / Prometheus をその Tailscale IP にだけ bind します（Docker の公開ポートは ufw を通らないため、0.0.0.0 には公開しません）。Tailscale が停止中ならエラー終了します。dcgm-exporter はホストにポートを公開せず、Prometheus が compose ネットワーク経由で scrape します。

アクセス（Tailscale 経由のみ）:

- Grafana: `http://<tailscale-ip>:3000`
- Prometheus: `http://<tailscale-ip>:9090`

Grafana の初期ログイン情報は `.env` の `GF_SECURITY_ADMIN_USER` / `GF_SECURITY_ADMIN_PASSWORD` で設定した値です。

## 6. 初回ユーザー追加

```bash
sudo ./scripts/add-user.sh alice
```

詳細は [add-user.md](add-user.md)。

> ⚠️ `add-user.sh` は利用者を `docker` グループに入れます。**docker グループは実質 root 相当**です（`docker run -v /:/host` でホスト全体を読み書きできる）。信頼できるメンバーだけを追加してください。

## 7. トラブルシューティング

| 症状                                | 対処                                                                                       |
| ----------------------------------- | ------------------------------------------------------------------------------------------ |
| `nvidia-smi` が無い / 動かない    | ドライバ未インストール。本ガイド §1 を実施                                                |
| Docker から GPU が見えない          | `sudo nvidia-ctk runtime configure --runtime=docker && sudo systemctl restart docker`    |
| ufw で締め出された                  | 物理コンソールから `sudo ufw disable` → ルール修正                                      |
| Grafana の admin パスワードを忘れた | コンテナ停止 →`grafana-data` ボリューム削除 → 再起動（メトリクスは Prometheus に残る） |
