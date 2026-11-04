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

### 事前準備: ポリシーファイルの tagOwners

サーバーは `tag:server` タグ付きで登録します。タグを付けるには、tailnet のポリシーファイル（管理画面の Access controls: <https://login.tailscale.com/admin/acls/file>）の `tagOwners` にそのタグが定義されている必要があります。無いと `tailscale up --advertise-tags=tag:server` が失敗します。

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

表示される URL を開いて tailnet に登録します。`--advertise-tags=tag:server` により、ポリシーファイルの `ssh` ルールで `dst: ["tag:server"]` として参照できます。

### 方法B: Auth Key（ヘッドレス／ブラウザなしの場合）

1. 別のPCで Tailscale 管理画面 <https://login.tailscale.com/admin/settings/keys> を開く
2. **Generate auth key** をクリックしてキーを生成（Reusable にすると複数台に使い回せる）
3. サーバーで以下を実行:

```bash
TAILSCALE_AUTHKEY=tskey-auth-XXXX sudo -E ./scripts/setup-tailscale.sh
```

スクリプトが自動的に `tailscale up --ssh --advertise-tags=tag:server` を実行し、tailnet に参加します。すでに Running の状態で再実行した場合は `tailscale up` をスキップします。

### tailnet の管理

セットアップ後、Tailscale 管理画面 <https://login.tailscale.com/admin/machines> でマシンを確認してください。利用者は、このマシンを **Machines → 対象サーバー → Share** で利用者ごとに共有して受け入れます（tailnet には招待しません）。手順と、ポリシーファイルの `grants`（通信できる範囲）と `ssh`（ログインできるユーザー）の役割は [add-user.md](add-user.md) を参照してください。tailnet への招待（**Users → Invite users**）は、管理者を増やすときなどのオプションです。

### SSH 運用ポリシー

本サーバーの SSH アクセスは **Tailscale SSH オンリー** です。

- **ufw**: 22 番ポートは `tailscale0` インターフェースからのみ許可。LAN からの SSH も塞いでいます。
- **Tailscale SSH**: `tailscale up --ssh` により tailnet 経由の SSH 接続は Tailscale が直接処理します。認証は **tailnet のアイデンティティ**（Google 等）で行われ、Linux 側のパスワード・`authorized_keys` は参照されません。
- **sshd ハードニング**: 万一 Tailscale SSH が停止し LAN 経由を開けた場合でも平文パスワードで入れないよう、`/etc/ssh/sshd_config.d/00-lab.conf` で `PasswordAuthentication no` / `PermitRootLogin no` を強制しています。sshd は各設定項目について最初に読んだ値を使うため、`50-cloud-init.conf` より先に読まれる `00-` の名前にしています。`setup.sh` は旧 `99-lab.conf` を削除し、`sshd -t` で検証してから reload します。
- **結果**: 利用者の受け入れは「`add-user.sh` でアカウント作成 → サーバーを Share → ポリシーファイルの `ssh` にルールを追加（新しい利用者のときだけ）」で完了します。初期パスワードも公開鍵も不要です。

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

### 再起動後の自動起動

`setup-monitoring.sh` はスタックの起動に成功すると、`lab-monitoring.service` を `/etc/systemd/system/` に置いて enable します。一度実行すれば、以後の再起動では Grafana と Prometheus が自動で立ち上がります。

Grafana と Prometheus は Tailscale の IP にだけ bind するので、起動時に Tailscale の IP がまだ無いことがあります。そのときはこのユニットが失敗し、IP が取れるまで 15 秒ごとに `setup-monitoring.sh` を再試行します。

状態を確認するには、次を実行します。実行した直後は開始していないので `inactive (dead)` と表示され、`enabled` になっていれば問題ありません。再起動後は `active (exited)` になります。

```bash
systemctl status lab-monitoring
```

自動起動をやめてスタックも止めるには、次を実行します。`setup-monitoring.sh` を再度実行すると、自動起動も有効に戻ります。

```bash
sudo systemctl disable --now lab-monitoring
cd config/monitoring
sudo docker compose down
```

ユニットにはリポジトリの絶対パスが書き込まれます。リポジトリを移したら（別の管理者アカウントのホームへ移す場合も）、移した先で `sudo ./scripts/setup-monitoring.sh` を再実行してください。パスに空白や `%` などの記号が含まれると、警告を出してユニットを置きません。

## 6. 管理者の個人環境（任意）

管理者はサーバーにモニターをつないでデスクトップに直接ログインすることがあるため、管理者だけは日本語入力（変換キーで Mozc オン、無変換キーでオフ）と Claude Code / Codex を使えるようにしておくと便利です。これらは管理者の個人マシン用セットアップ [kohonda/make-ubuntu-setup](https://github.com/kohonda/make-ubuntu-setup) にすでにあるので（`60-fcitx5-mozc.sh`、`90-claude-code.sh`、`95-codex.sh`）、本リポジトリにはスクリプトを足さず、それを使います。

`setup.sh` の後に、**root ではなく管理者自身として**実行します（`install.sh` は root での実行を拒否し、必要なところだけ `sudo` します）。

```bash
git clone https://github.com/kohonda/make-ubuntu-setup ~/make-ubuntu-setup
cd ~/make-ubuntu-setup
bash install.sh --skip 30 --skip 80 --skip 85
```

skip の理由:

- **80（Docker）と 85（NVIDIA Container Toolkit）**: `setup.sh` がすでに入れているので外します。
- **30（Slack）**: 任意です。必要なら `--skip 30` を外してください。
- uv / pixi / gh は、すでに入っていればスキップされます。

影響範囲:

- インストール先は管理者のホーム（`~/.local/bin`、`~/.config/fcitx5`、`~/.claude`、`~/.codex`）なので、他のユーザーには影響しません（ホームは mode 750）。他のユーザーが Claude Code / Codex を使いたい場合は、各自が sudo なしの公式インストーラで入れて、自分のアカウントでログインしてください。
- `/etc/environment.d/99-fcitx5.conf` だけはシステム全体の設定ですが、デスクトップセッションの IME 用の環境変数なので、SSH で使う人には影響しません。
- 日本語入力が効くのは、サーバーのデスクトップに直接ログインしたときだけです。SSH 経由のときは手元の PC の IME が使われます。

終わったら一度ログアウトして、ログインし直してください。

## 7. 初回ユーザー追加

```bash
sudo ./scripts/add-user.sh alice
```

詳細は [add-user.md](add-user.md)。

> ⚠️ `add-user.sh` は利用者を `docker` グループに入れます。**docker グループは実質 root 相当**です（`docker run -v /:/host` でホスト全体を読み書きできる）。信頼できるメンバーだけを追加してください。

## 8. トラブルシューティング

| 症状                                | 対処                                                                                       |
| ----------------------------------- | ------------------------------------------------------------------------------------------ |
| `nvidia-smi` が無い / 動かない    | ドライバ未インストール。本ガイド §1 を実施                                                |
| Docker から GPU が見えない          | `sudo nvidia-ctk runtime configure --runtime=docker && sudo systemctl restart docker`    |
| ufw で締め出された                  | 物理コンソールから `sudo ufw disable` → ルール修正                                      |
| Grafana の admin パスワードを忘れた | コンテナ停止 →`grafana-data` ボリューム削除 → 再起動（メトリクスは Prometheus に残る） |
| 再起動後に Grafana / Prometheus が立ち上がらない | `journalctl -b -u lab-monitoring` で再試行の理由を確認。`Tailscale is not running` なら §3 の手順で Tailscale を起動すれば次の再試行で立ち上がる。`.env` が無い場合は §5 の手順で作る |
