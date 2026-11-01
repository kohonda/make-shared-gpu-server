# ユーザー追加・削除手順

本サーバーは **Tailscale SSH** をアクセス経路としているため、Linux 側のパスワードや `authorized_keys` は通常運用では使いません。利用者を受け入れる流れは:

1. サーバーに Linux アカウントを作る（`add-user.sh`）
2. 利用者を **lab の tailnet に招待**（Tailscale 管理画面）
3. 利用者は自分の PC で Tailscale にログインし、`ssh <username>@<server>` するだけ

パスワードも SSH 鍵も手渡し不要です。

## 追加

> **ユーザー名は Tailscale アカウントのメール prefix に合わせておくと管理が楽です**（例: `alice@example.com` → Linux ユーザー `alice`）。
> ただし、名前を合わせただけではログインできません。Tailscale のデフォルトの SSH ルールは `autogroup:self`（自分が所有するデバイスへの接続）向けで、`tag:server` 付きのサーバーには当たりません。ユーザーごとに下の「ACL に SSH ルールを追加」の明示ルールが必要です。

```bash
sudo ./scripts/add-user.sh <username>
```

挙動:

- ホームディレクトリ作成（`/home/<user>`, mode `750`）
- グループ `labmembers`, `docker` に所属（Docker は sudo 不要で使えます。グループ名 `labmembers` は環境変数 `SHARED_GROUP` で変更可）
- Tailscale が未インストール・停止中でも最後まで実行され、サマリーを表示します

> ⚠️ **docker グループは実質 root 相当です。** `docker run -v /:/host ...` でホストの任意のファイルを読み書きでき、sudo が無くても root と同じことができます。「一般ユーザーは sudo を持たない」という前提はこのグループには当てはまりません。**信頼できるメンバーだけ**を追加してください。
- **パスワードは `passwd -l` でロック**（Tailscale SSH 経由でのみログイン可）
- `authorized_keys` は作成しません

作成後、Tailscale 管理画面から当該メンバーを tailnet に招待してください。

## sudo を使わせたい場合

Tailscale SSH 経由ではパスワードが設定されていないため、そのままでは `sudo` を使えません。必要な管理者候補にだけ、個別にパスワードを設定します。

```bash
sudo passwd <username>          # パスワードを設定（ロック解除）
sudo usermod -aG sudo <username>
```

以後、そのユーザーは `sudo` コマンド入力時にパスワードを求められます。

## Tailscale 招待 & ACL 登録

### 1. tailnet への招待

- 管理画面: <https://login.tailscale.com/admin/machines>
- メンバー招待: **Users → Machines → Share** からメールアドレスで招待

### 2. ACL に SSH ルールを追加

ユーザーを追加したら、Tailscale の Access Controls にも SSH 許可ルールを追加する必要があります。

ACL 編集画面: <https://login.tailscale.com/admin/acls/file>

`ssh` セクションに以下のようなエントリを追加してください:

```jsonc
"ssh": [
    // ... 既存のルール ...
    {
        "action": "accept",
        "src":    ["newuser_1@gmail.com"],      // Tailscale アカウントのメールアドレス
        "dst":    ["tag:server"],              // サーバーのタグ（tailscale up --advertise-tags=tag:server で設定）
        "users":  ["newuser_1"]                  // Linux ユーザー名
    },
    // !!!! ユーザーごとに別の{}ブロックで追加していくこと !!!!!
    {
        "action": "accept",
        "src":    ["newuser_2@gmail.com"],      // Tailscale アカウントのメールアドレス
        "dst":    ["tag:server"],              // サーバーのタグ（tailscale up --advertise-tags=tag:server で設定）
        "users":  ["newuser_2"]                  // Linux ユーザー名
    }
]
```

- `src`: ユーザーの Tailscale アカウント（メールアドレス）
- `dst`: 接続先サーバーのタグ。サーバーは `tag:server` で登録されています
- `users`: サーバー上の Linux ユーザー名（`add-user.sh` で作成した名前=Tailscale アカウントのメールアドレスの `@` より前の部分）

### 3. 接続確認

接続確認（サーバー側）:

```bash
tailscale status
```

## 削除

```bash
# プロセスを終了させてから
sudo pkill -u <username>
# ホームごと削除する場合
sudo userdel -r <username>
# ホームを残す場合
sudo userdel <username>
```

Tailscale 側からも当該ユーザーを tailnet から外すのを忘れずに。

## 一時的な無効化

```bash
sudo usermod -L <username>      # ロック
sudo usermod -U <username>      # 解除
```

## 新規ユーザーのホームに入って作業したい

home は mode 750 なので、管理者自身のアカウントから `cd /home/<user>` しても **Permission denied** になります（`sudo cd` は shell builtin なので効きません）。次のどちらかを使います。

```bash
# そのユーザーとしてログインシェルを開く
sudo -i -u <username>

# 単発コマンドだけ実行
sudo -u <username> ls -la ~/.ssh
```

## 付録: LAN 経由 SSH 運用に戻したい場合

通常は不要ですが、Tailscale を使わずローカル LAN から SSH させたい場合は:

1. `config/ufw/rules.sh` を編集し、LAN CIDR からの 22 番許可を再追加
2. `sudo ./scripts/add-user.sh` では鍵登録まで行わないので、以下で authorized_keys を配置:

   ```bash
   sudo install -d -o <user> -g <user> -m 700 /home/<user>/.ssh
   sudo install -o <user> -g <user> -m 600 pubkey.pub /home/<user>/.ssh/authorized_keys
   ```

3. `config/ssh/00-lab.conf` は `PasswordAuthentication no` のままにしておくことを推奨
