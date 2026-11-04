# ユーザー追加・削除手順

本サーバーは **Tailscale SSH** をアクセス経路としているため、Linux 側のパスワードや `authorized_keys` は通常運用では使いません。利用者を受け入れる流れは:

1. サーバーに Linux アカウントを作る（`add-user.sh`）
2. Tailscale 管理画面の **Machines → 対象サーバー → Share** で、利用者のメールアドレスに共有する
3. 利用者が共有を承認する
4. ポリシーファイルの `ssh` セクションにその利用者のルールを足す（新しい利用者のときだけ）
5. 利用者は FQDN（`<host>.<tailnet>.ts.net`）か Tailscale IP（`100.x.x.x`）で `ssh <username>@...` する。短い名前（`gpu01`）では届かない

パスワードも SSH 鍵も手渡し不要です。利用者は自分の tailnet のまま使え、見えるのは共有されたサーバーだけです。tailnet のユーザー数も消費しません。一般の利用者はこの Share だけで受け入れます。lab の tailnet への招待は、管理者を増やすときや特別なユーザー向けのオプションです（「[オプション: tailnet に招待する（管理者・特別なユーザー向け）](#オプション-tailnet-に招待する管理者特別なユーザー向け)」）。

> **新しい GPU サーバーを足したとき**: そのサーバーを使わせる利用者ごとに、新しいサーバー上で `add-user.sh` を実行し、新しいサーバーを Share します。ポリシーファイルの `ssh` ルールは足さなくてよいです。新しいサーバーにも `tag:server` が付くので、既存のルールの対象に入ります（`ssh` ルールを足すのは新しい利用者を追加するときだけ）。

## 用語: ポリシーファイルの `grants` と `ssh`

Tailscale 管理画面の **Access controls**（<https://login.tailscale.com/admin/acls/file>）で編集するのは、tailnet の**ポリシーファイル全体**です。このうち、本手順に関わるのは次の2つのセクションです。

- **`grants`**: 「どこからどこへ通信できるか」（ネットワーク到達）を決めます。旧来の `acls` セクションの後継で、Tailscale は grants を推奨しています（[grants のドキュメント](https://tailscale.com/kb/1324/grants): "The recommended best practice is to favor grants for most use cases"）。本 repo の例では `acls` は使わず、`grants` を使います
- **`ssh`**: 「誰がどのサーバーに、どの Linux ユーザーとしてログインできるか」（Tailscale SSH のログイン可否）を決める別のセクションです。`grants` で通信が許されていても、`ssh` にルールが無ければ Tailscale SSH ではログインできません

本ドキュメントで「`ssh` ルール」と書いているのは、このポリシーファイルの `ssh` セクションのエントリのことです。`tagOwners`（どのタグを誰が付けられるか）も同じポリシーファイルにあります（[setup-guide §3](setup-guide.md)）。

## 追加

> **ユーザー名は名+姓の小文字にします**（例: `taroyamada`。全サーバー共通。[命名規則](setup-guide.md#命名規則とアカウント構成)を参照）。メールアドレスとユーザー名の対応は `ssh` ルールで持つので、両者を揃える必要はありません。
> アカウントを作っただけではログインできません。Tailscale のデフォルトの SSH ルールは `autogroup:self`（自分が所有するデバイスへの接続）向けで、`tag:server` 付きのサーバーには当たりません。ユーザーごとに、下の「ポリシーファイルの `ssh` セクションにルールを追加」の明示ルールが必要です。
> `ssh` ルールの `users` に書くのは、**`add-user.sh` に渡した名前そのもの**です。

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

作成後、下の「Share でサーバーを共有し、`ssh` ルールを追加（標準）」に進んでください。

## sudo を使わせたい場合

Tailscale SSH 経由ではパスワードが設定されていないため、そのままでは `sudo` を使えません。必要な管理者候補にだけ、個別にパスワードを設定します。

```bash
sudo passwd <username>          # パスワードを設定（ロック解除）
sudo usermod -aG sudo <username>
```

以後、そのユーザーは `sudo` コマンド入力時にパスワードを求められます。

## Share でサーバーを共有し、`ssh` ルールを追加（標準）

### 1. サーバーを共有する

- 管理画面: <https://login.tailscale.com/admin/machines>
- **Machines → 対象サーバー → Share** を開き、利用者の Tailscale アカウントのメールアドレスに共有する
- 利用者が共有を承認すると、利用者の tailnet にそのサーバーが現れる

### 2. ポリシーファイルの `ssh` セクションにルールを追加

共有しただけでは SSH できません。ポリシーファイルの `ssh` セクションに、その利用者のログイン許可ルールも追加します（新しい利用者のときだけ。既存の利用者に別のサーバーを共有するときは不要です）。

ポリシーファイルの編集画面（Access controls）: <https://login.tailscale.com/admin/acls/file>

`ssh` セクションに以下のようなエントリを追加してください:

```jsonc
"ssh": [
    // ... 既存のルール ...
    {
        "action": "accept",
        "src":    ["newuser_1@gmail.com"],      // Tailscale アカウントのメールアドレス
        "dst":    ["tag:server"],              // サーバーのタグ（tailscale up --advertise-tags=tag:server で設定）
        "users":  ["newuser_1"]                  // add-user.sh に渡した Linux ユーザー名
    },
    // !!!! ユーザーごとに別の{}ブロックで追加していくこと !!!!!
    {
        "action": "accept",
        "src":    ["newuser_2@gmail.com"],      // Tailscale アカウントのメールアドレス
        "dst":    ["tag:server"],              // サーバーのタグ（tailscale up --advertise-tags=tag:server で設定）
        "users":  ["newuser_2"]                  // add-user.sh に渡した Linux ユーザー名
    }
]
```

- `src`: ユーザーの Tailscale アカウント（メールアドレス）
- `dst`: 接続先サーバーのタグ。サーバーは `tag:server` で登録されています
- `users`: サーバー上の Linux ユーザー名。**`add-user.sh` に渡した名前そのもの**を書きます

### 3. 接続先を伝える

`add-user.sh` の完了サマリーの SSH CONNECTION をそのまま利用者に伝えます。共有されたサーバーには **FQDN（`<host>.<tailnet>.ts.net`）か Tailscale IP（`100.x.x.x`）でしか届きません**。`gpu01` のような短い名前では届きません。

接続確認（サーバー側）:

```bash
tailscale status
```

### Share の注意点

- **FQDN が必須**: 共有先からは短い名前が解決されません。FQDN か 100.x の IP で接続してもらいます
- **サーバーごとの共有**: 共有はマシン単位です。GPU サーバーを増やしたら、利用者ごとに共有し直してください
- **`ssh` ルールの `dst` は `tag:server` のままでよい**: 実際に届くのは共有されたマシンだけなので、アクセス範囲は Share で決まります
- **両方の tailnet のポリシー**: 利用者側の tailnet でも、そのサーバーへの接続が許されている必要があります（デフォルトのポリシーなら許可されています）。管理者側の `grants` も、共有先ユーザーからの接続を許していること（`src` が `*` か `autogroup:shared`）を確認してください
- **利用終了時**: Share の解除（Machines → 対象サーバー → Share から共有を外す）と、ポリシーファイルの `ssh` ルールの削除の両方を行います

## オプション: tailnet に招待する（管理者・特別なユーザー向け）

管理者を増やすときや、特別なユーザーを lab の tailnet のメンバーとして招待する方法です。**一般の利用者には使わず、上の Share で受け入れてください。**

> ⚠️ **今の `grants` が `* → *`（`"src": ["*"], "dst": ["*"]`）のままだと、招待した人は tailnet の全マシンに届きます。** GPU サーバー以外の管理者のマシンにも接続できる状態になるので、招待する前にこの点を理解しておいてください。

1. 管理画面 <https://login.tailscale.com/admin/users> を開く
2. **Users → Invite users** から、利用者のメールアドレスで招待する
3. 利用者が招待を承認し、lab の tailnet にログインする
4. 上の「2. ポリシーファイルの `ssh` セクションにルールを追加」と同じルールを足す（書き方は Share の場合と同じ）

招待した場合は、tailnet 内の短い名前（`ssh <username>@gpu01`）でも接続できます。

招待した人が個人の tailnet も使っている場合は、Tailscale アプリで lab の tailnet に切り替えてもらう必要があります。利用者ガイドの「管理者から tailnet に招待された場合（Fast User Switching）」（[ja](../user/getting-started.ja.md) / [en](../user/getting-started.en.md)）を案内してください。

## 削除

```bash
# プロセスを終了させてから
sudo pkill -u <username>
# ホームごと削除する場合
sudo userdel -r <username>
# ホームを残す場合
sudo userdel <username>
```

Tailscale 側からも当該ユーザーを外すのを忘れずに（Share の場合は共有の解除、招待した場合は tailnet からの削除。どちらの場合もポリシーファイルの `ssh` ルールを消す）。

削除は自動では検知されないので、管理者メモ（[setup-guide §7](setup-guide.md)）のユーザー一覧を手動で更新します。

```bash
sudo ./scripts/update-admin-notes.sh
```

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
