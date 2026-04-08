# ユーザー追加・削除手順

## 追加

推奨フロー: 利用者から受け取った公開鍵ファイルを第2引数に渡して一発で完了させます。

```bash
sudo ./scripts/add-user.sh <username> path/to/pubkey.pub
```

公開鍵が未着の場合は省略可能（後から登録）:

```bash
sudo ./scripts/add-user.sh <username>
```

挙動:

- ホームディレクトリ作成（`/home/<user>`, mode `750`）
- グループ `labmembers`, `docker` に所属（Docker は sudo 不要で使えます）
- ランダム初期パスワードを生成して表示
- `chage -d 0` で初回ログイン時にパスワード変更を強制
- `~/.ssh/` を mode 700 で作成、`authorized_keys` を mode 600 で配置
  - 公開鍵を渡していれば `ssh-keygen -l` で妥当性チェックしてから `install` でコピー
  - 渡していなければ空ファイルを作成

### 公開鍵の後付け登録

`add-user.sh` 実行時に鍵を渡しそびれた場合は、**root で** 直接コピーするのが確実です（`sudo -u <user>` だと降格後に管理者側の pubkey を読めず失敗します）。

```bash
# 上書き
sudo install -o <username> -g <username> -m 600 pubkey.pub \
    /home/<username>/.ssh/authorized_keys

# 追記
sudo tee -a /home/<username>/.ssh/authorized_keys < pubkey.pub >/dev/null
```

### 新規ユーザーのホームに入って作業したい

home は mode 750 なので、管理者自身のアカウントから `cd /home/<user>` しても **Permission denied** になります（`sudo cd` は shell builtin なので効きません）。次のどちらかを使います。

```bash
# そのユーザーとしてログインシェルを開く
sudo -i -u <username>

# 単発コマンドだけ実行
sudo -u <username> ls -la ~/.ssh
```

### 既存ユーザー（旧スクリプトで mode 700 になっているもの）

以前のバージョンの `add-user.sh` は home を mode 700 にしていました。必要なら:

```bash
sudo chmod 750 /home/<username>
```

### 初期パスワードの伝達

スクリプトが表示する初期パスワードは **安全な経路（暗号化チャット等）** で本人にのみ伝えてください。

## 削除

```bash
# プロセスを終了させてから
sudo pkill -u <username>
# ホームごと削除する場合
sudo userdel -r <username>
# ホームを残す場合
sudo userdel <username>
```

## 一時的な無効化

```bash
sudo usermod -L <username>      # ロック
sudo usermod -U <username>      # 解除
```

## グループ変更

例: 管理者権限を付与する。

```bash
sudo usermod -aG sudo <username>
```
