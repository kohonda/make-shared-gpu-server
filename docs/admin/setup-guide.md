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
cd /make-shared-gpu-server
```


> 📝 初期セットアップ後もリポジトリは残しておいてください。設定を更新したいときは `git pull` して `sudo ./scripts/setup.sh` を再実行すれば冪等に反映されます（`/etc/` 等への配布物はリポジトリ内の `config/` が元ネタになっています）。
>
> `/opt/` や `/usr/local/src/` に置いても動きますが、必須ではありません。書き込み権限の都合でむしろ管理者ホームの方が扱いやすいことが多いです。

## 3. メインセットアップの実行

```bash
sudo ./scripts/setup.sh
```

実行内容:

1. 基本パッケージ（build-essential, tmux, htop, gpustat, openssh-server 等）
2. sshd ハードニング（`PasswordAuthentication no` 他）
3. NVIDIA ドライバ存在チェック
4. Docker Engine
5. NVIDIA Container Toolkit
6. uv / pixi（`/usr/local/bin` に配置）
7. グループ `labmembers`、共有ディレクトリ（`/shared/{datasets,models,workspace}`, `/scratch`, `/archive`）
8. 共有環境変数 (`/etc/profile.d/lab-defaults.sh`)
9. `/etc/skel/` の dotfiles
10. ufw 設定（SSH は tailscale0 のみ許可）
11. unattended-upgrades（セキュリティのみ）
12. MOTD
13. `/scratch` クリーンアップ用 cron（コメントアウト状態）

冪等です。何度実行しても安全。

### 環境変数で挙動を調整

スクリプト冒頭の変数は環境変数で上書きできます。

```bash
LAB_LOCAL_CIDR=10.0.0.0/8 sudo -E ./scripts/setup.sh
```

## 4. Tailscale のセットアップ

```bash
sudo ./scripts/setup-tailscale.sh
sudo tailscale up --ssh --hostname="$(hostname)"
```

表示される URL を開いて tailnet に登録します。そのあと、Tailscale 管理画面 <https://login.tailscale.com/admin/machines> でマシンを確認し、lab メンバーを **Users → Invite users** で招待してください。必要に応じて ACL で SSH 権限を絞ります。

### SSH 運用ポリシー

本サーバーの SSH アクセスは **Tailscale SSH オンリー** です。

- **ufw**: 22 番ポートは `tailscale0` インターフェースからのみ許可。LAN からの SSH も塞いでいます。
- **Tailscale SSH**: `tailscale up --ssh` により tailnet 経由の SSH 接続は Tailscale が直接処理します。認証は **tailnet のアイデンティティ**（Google 等）で行われ、Linux 側のパスワード・`authorized_keys` は参照されません。
- **sshd ハードニング**: 万一 Tailscale SSH が停止し LAN 経由を開けた場合でも平文パスワードで入れないよう、`/etc/ssh/sshd_config.d/99-lab.conf` で `PasswordAuthentication no` / `PermitRootLogin no` を強制しています。
- **結果**: 利用者の受け入れは「`add-user.sh` でアカウント作成 → tailnet に招待」だけで完了します。初期パスワードも公開鍵も不要です。

## 5. 監視スタック（Prometheus + Grafana）

任意。GPU/ホストメトリクスを Grafana で見たい場合に起動します。

```bash
cd config/monitoring
cp .env.example .env
# GF_SECURITY_ADMIN_PASSWORD を編集
cd ../..
sudo ./scripts/setup-monitoring.sh
```

アクセス（Tailscale 経由のみ ufw で許可）:

- Grafana: `http://<tailscale-ip>:3000`
- Prometheus: `http://<tailscale-ip>:9090`

Grafana の初期ログイン情報は `.env` の `GF_SECURITY_ADMIN_USER` / `GF_SECURITY_ADMIN_PASSWORD` で設定した値です。

## 6. 初回ユーザー追加

```bash
sudo ./scripts/add-user.sh alice
```

詳細は [add-user.md](add-user.md)。

## 7. トラブルシューティング

| 症状                                | 対処                                                                                       |
| ----------------------------------- | ------------------------------------------------------------------------------------------ |
| `nvidia-smi` が無い / 動かない    | ドライバ未インストール。本ガイド §1 を実施                                                |
| Docker から GPU が見えない          | `sudo nvidia-ctk runtime configure --runtime=docker && sudo systemctl restart docker`    |
| ufw で締め出された                  | 物理コンソールから `sudo ufw disable` → ルール修正                                      |
| Grafana の admin パスワードを忘れた | コンテナ停止 →`grafana-data` ボリューム削除 → 再起動（メトリクスは Prometheus に残る） |
