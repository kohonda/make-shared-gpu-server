# ユーザー追加・削除手順

## 追加

```bash
sudo ./scripts/add-user.sh <username>
```

挙動:

- ホームディレクトリ作成（`/home/<user>`, mode `700`）
- グループ `labmembers`, `docker` に所属（Docker は sudo 不要で使えます）
- ランダム初期パスワードを生成して表示
- `chage -d 0` で初回ログイン時にパスワード変更を強制
- `~/.ssh/authorized_keys` を空で作成（mode 600）

### 公開鍵の登録

利用者から ssh 公開鍵 (`id_ed25519.pub` 等) を受け取り、追記します。

```bash
sudo -u <username> tee -a /home/<username>/.ssh/authorized_keys < user_pubkey.pub
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
