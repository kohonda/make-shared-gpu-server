# 管理者向けセットアップガイド

研究室GPUサーバー（gpu01, gpu02, ...）の初期セットアップ手順。

## 0. 前提

- Ubuntu **22.04** または **24.04** がインストール済み
- root もしくは sudo 権限のあるアカウント
- インターネット接続あり

## 命名規則とアカウント構成

複数台のサーバーで同じ運用にするための決まりです。既存のサーバーをこの規則に合わせる手順は [§9](#9-既存サーバーを命名規則に合わせる) にあります。

### ホスト名

- 形式は `gpu<番号>-<GPU種類>` です（例: `gpu01-b6000`, `gpu02-b200`）。小文字・数字・ハイフンだけを使います。
- 番号は GPU の種類をまたいだゼロ埋めの通し番号で、再利用しません。
- GPU を換装したら、種類の部分を [§9.1](#91-ホスト名を変更する) の手順で変えます（番号は変えません）。
- 種類が混在するサーバーは主な GPU で名付け、細かいスペックは別の一覧表で管理します。
- 本ドキュメント群の `gpu01` は例なので、実際のホスト名に読み替えてください。

### ユーザー名

- 名+姓の小文字にします（例: `taroyamada`）。全サーバーで共通の名前を使い、再利用しません。
- `add-user.sh` の検証により、大文字を含む名前（`KoheiHonda`）と数字で始まる名前は使えません。
- `add-user.sh` は UID を指定しないので、全サーバーで同じ順番でユーザーを追加します（将来の NFS やディスク移設に備えるため）。

### 管理者のアカウント

- **管理者アカウント（`admin-<名+姓>`）**: 例: `admin-taroyamada`。Ubuntu インストール時に作る最初のユーザーです。管理作業とデスクトップログインに使い、実験はしません。
- **個人名アカウント**: 実験は個人名のアカウントで行います。管理者本人の分も `add-user.sh` で作る一般ユーザーです。このため docker グループに入り、実質 root 相当の権限は残ります。外すなら `sudo gpasswd -d <user> docker` ですが、その場合は Docker を使えません。
- **管理者が増える場合**: 管理者アカウントは共用せず、同じ規則で1人1つ作ります（[§9.2](#92-管理者アカウントを追加する)を参照）。

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

### 事前準備: ホスト名を設定する

Tailscale を上げる前に、[命名規則](#命名規則とアカウント構成)どおりのホスト名を設定します。`setup-tailscale.sh` は `$(hostname)` をそのまま Tailscale に登録するので、後から変えると Share の利用者の接続先（FQDN）が変わります。

```bash
sudo hostnamectl set-hostname gpu01-b6000
sudoedit /etc/hosts                     # 127.0.1.1 の行を gpu01-b6000 に直す
```

> ⚠️ **再インストールするときは、古いマシンを管理画面（<https://login.tailscale.com/admin/machines>）から先に削除してください。** 残っていると、`gpu01-b6000-1` のように別名で登録されることがあります。

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

### 管理者アカウント用の `ssh` ルール

管理者アカウントは sudo を持つので、ポリシーファイルの `ssh` セクションに再認証を求める `check` モードのルールを追加します。Tailscale のアイデンティティで再認証するまで接続できません（既定では 12 時間ごと。`checkPeriod` で変えられます）。

```jsonc
"ssh": [
    // ... 既存のルール ...
    {
        "action": "check",                 // 接続時に再認証を求める
        "src":    ["you@example.com"],     // 管理者の Tailscale アカウントのメールアドレス
        "dst":    ["tag:server"],
        "users":  ["admin-taroyamada"]     // 管理者アカウントの Linux ユーザー名
    }
]
```

管理者本人の個人名アカウントのルールは、一般の利用者と同じです（[add-user.md](add-user.md)）。

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

## 6. 管理者の個人環境（任意）

管理者はサーバーにモニターをつないでデスクトップに直接ログインすることがあるため、管理者だけは日本語入力（変換キーで Mozc オン、無変換キーでオフ）と Claude Code / Codex を使えるようにしておくと便利です。これらは管理者の個人マシン用セットアップ [kohonda/make-ubuntu-setup](https://github.com/kohonda/make-ubuntu-setup) にすでにあるので（`60-fcitx5-mozc.sh`、`90-claude-code.sh`、`95-codex.sh`）、本リポジトリにはスクリプトを足さず、それを使います。

`setup.sh` の後に、**root でも個人名アカウントでもなく管理者アカウント（`admin-<名+姓>`）として**実行します。`install.sh` は root での実行を拒否し、必要なところだけ `sudo` します。`60-fcitx5-mozc.sh` は sudo が必要で、`add-user.sh` で作るアカウントはパスワードがロックされていてデスクトップにログインできないため、管理者アカウントで実行します。

Claude Code / Codex を実験用の個人名アカウントでも使うときは、下の「影響範囲」にある sudo なしの公式インストーラで、そのアカウントに入れてください。

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

- インストール先は管理者アカウントのホーム（`~/.local/bin`、`~/.config/fcitx5`、`~/.claude`、`~/.codex`）なので、他のユーザーには影響しません（ホームは mode 750）。他のユーザーが Claude Code / Codex を使いたい場合は、各自が sudo なしの公式インストーラで入れて、自分のアカウントでログインしてください。
- `/etc/environment.d/99-fcitx5.conf` だけはシステム全体の設定ですが、デスクトップセッションの IME 用の環境変数なので、SSH で使う人には影響しません。
- 日本語入力が効くのは、サーバーのデスクトップに直接ログインしたときだけです。SSH 経由のときは手元の PC の IME が使われます。

終わったら一度ログアウトして、ログインし直してください。

## 7. 初回ユーザー追加

最初に追加するのは、管理者本人の個人名アカウントです（[命名規則](#命名規則とアカウント構成)を参照）。

```bash
sudo ./scripts/add-user.sh taroyamada
```

詳細は [add-user.md](add-user.md)。

> ⚠️ `add-user.sh` は利用者を `docker` グループに入れます。**docker グループは実質 root 相当**です（`docker run -v /:/host` でホスト全体を読み書きできる）。信頼できるメンバーだけを追加してください。

### 管理者メモ

接続情報、Grafana の情報、ユーザーの情報、鍵の保管場所を、管理者アカウントの Desktop にテキストで残せます。運用時と障害時に確認するためのものです。

```bash
sudo ./scripts/update-admin-notes.sh
```

実行した管理者アカウントの Desktop（`xdg-user-dir DESKTOP`。日本語環境なら `デスクトップ`。取れなければ `~/Desktop`）の下の `server-admin-notes/` に、次の2つのファイルができます。フォルダは 700、ファイルは 600 で、所有者は実行した管理者アカウントです。`sudo` を使わず root で直接実行するとエラーになります。

| ファイル | 自動の部分 | 手書きの部分（ひな形） |
| --- | --- | --- |
| `admin.txt` | ホスト名、FQDN、Tailscale IP、管理者の `ssh` コマンド、Tailscale 管理画面の URL、Grafana と Prometheus の URL、Grafana のユーザーとパスワード、状態確認のコマンド、更新コマンド | 鍵ごとの用途、保管場所、再発行手順（Tailscale 認証キー、GitHub トークン、`sudo` パスワードなど） |
| `users.txt` | `labmembers` と `sudo` の各ユーザーの名前、UID、グループ、ホーム、`ssh` コマンド | 本名、Tailscale のメールアドレス、追加日など |

- **更新**: 各ファイルの「ここから下は手書き（更新しても消えません）」という区切り行より上だけを作り直します。区切り行が見つからないファイルは上書きせず、警告して飛ばします。元に戻すには、ファイルを別の場所へ移してから再実行し、できたひな形に手書きの内容を写します。
- **自動更新**: `add-user.sh` を `sudo` で実行すると、最後にそのアカウントのメモも更新します。更新に失敗してもユーザーの作成は成功扱いのままで、警告だけが出ます。
- **未設定の項目**: Tailscale が動いていないときや `config/monitoring/.env` がないときは、その項目を「未設定」と書きます。監視の URL は、`.env` があれば監視スタックが止まっていても表示します。
- **複数の管理者**: 更新されるのは実行した管理者アカウントのメモだけです。

鍵の実際の値はパスワードマネージャーに置き、メモには用途、保管場所、再発行手順だけを書いてください。メモには次の性質があるためです。

- **docker グループの利用者には読めます。** ファイルが 600 でも、docker グループは実質 root 相当なので読めます。
- **メモはサーバーと一緒に失われます。** サーバーが壊れたときに必要な鍵の値を、サーバーの上にだけ置かないでください。

Grafana のパスワードだけは値を書きます。同じサーバーの `config/monitoring/.env` にすでにあり、読める人が増えないためです。

## 8. トラブルシューティング

| 症状                                | 対処                                                                                       |
| ----------------------------------- | ------------------------------------------------------------------------------------------ |
| `nvidia-smi` が無い / 動かない    | ドライバ未インストール。本ガイド §1 を実施                                                |
| Docker から GPU が見えない          | `sudo nvidia-ctk runtime configure --runtime=docker && sudo systemctl restart docker`    |
| ufw で締め出された                  | 物理コンソールから `sudo ufw disable` → ルール修正                                      |
| Grafana の admin パスワードを忘れた | コンテナ停止 →`grafana-data` ボリューム削除 → 再起動（メトリクスは Prometheus に残る） |

## 9. 既存サーバーを命名規則に合わせる

すでに動いているサーバーを[命名規則](#命名規則とアカウント構成)に合わせる手順です。**9.1 → 9.2 → 9.3 の順に**進めます。

### 9.1 ホスト名を変更する

```bash
sudo hostnamectl set-hostname gpu01-b6000
sudoedit /etc/hosts                     # 127.0.1.1 の行を gpu01-b6000 に直す
sudo tailscale set --hostname=gpu01-b6000
hostnamectl --static; tailscale status  # 確認
```

- FQDN が変わるので、Share の利用者に新しい接続先を伝えます（`~/.ssh/config` の `HostName` も変更が必要です）。
- 管理画面でマシン名を手動で変えている場合は、自動では追従しないので管理画面で直します。
- クラウドイメージで cloud-init が動いている場合は、再起動で戻らないように `preserve_hostname: true` を設定します。
- 監視スタックの設定と MOTD はホスト名を固定で持っていないので、変更は不要です。

### 9.2 管理者アカウントを追加する

```bash
getent passwd admin-taroyamada; getent group admin-taroyamada   # 既にないことを確認
sudo adduser --gecos "" admin-taroyamada                        # sudo とデスクトップログイン用のパスワードを設定
sudo usermod -aG sudo admin-taroyamada
```

- [§3 の管理者アカウント用 `ssh` ルール](#管理者アカウント用の-ssh-ルール)をポリシーファイルに追加します。
- **今のセッションを閉じずに**、別の端末から `ssh admin-taroyamada@<FQDN>` で入り、`sudo -v` が通ることを確認します。

### 9.3 既存ユーザーを削除する（必要な場合）

**9.2 の確認が終わるまで削除しないでください**（締め出し防止）。削除は元に戻せないので、先に残すものを確認します。

```bash
# 管理者アカウントで実行する
who; ps -u <old>                                  # ログイン中のセッションとプロセス
sudo crontab -u <old> -l                          # cron
sudo find / -xdev -user <old> -not -path '/home/<old>/*' -ls   # ホーム外の所有ファイル
sudo du -sh /home/<old>                           # 残すデータの量
```

- 実験データや、§2 で管理者のホームに clone した本リポジトリを、新しいアカウントに移します。
- ホーム外に残すファイルは、先に新しい所有者へ `chown` します。残したまま削除すると UID だけの所有者になり、後で同じ UID を割り当てられたユーザーが所有者になるおそれがあります。
- `sudo pkill -u <old>` と `sudo userdel -r <old>` を実行します（[add-user.md の「削除」](add-user.md#削除)を参照）。迷ったらホームを残す `userdel`（`-r` なし）か、ロックのみの `sudo usermod -L <old>` にとどめます。
- ポリシーファイルの `<old>` の `ssh` ルールを消し、`ssh <old>@<FQDN>` で入れないことを確認します。
