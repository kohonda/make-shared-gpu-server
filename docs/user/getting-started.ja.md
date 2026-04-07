# 利用開始ガイド (日本語)

研究室GPUサーバーへようこそ。このガイドは初めて使う人向けに、接続方法から Python 環境構築、GPU の使い方までを順を追って説明します。

> English version: [getting-started.en.md](getting-started.en.md)

## 1. はじめに

- サーバーは複数人で共有しています。**他の人のジョブを止めない / GPU を独占しない** ことを意識してください。
- 大きなモデルやデータセットは `/shared` 配下を使い、各自のホームに重複して置かないでください。
- 長時間ジョブは必ず `tmux` か `byobu` 内で実行してください。SSH が切れても継続します。
- 困ったら [faq.md](faq.md) と管理者に。

## 2. SSH 接続

サーバーへのアクセスは **Tailscale 経由 + SSH 鍵認証** が標準です。

### 2.1 Tailscale を入れる（クライアント側）

[公式サイト](https://tailscale.com/download) からアプリをインストールし、研究室の tailnet にログインします（招待は管理者から受け取ってください）。

### 2.2 SSH 鍵を生成

まだ鍵が無ければ、ローカル PC で生成します。

```bash
ssh-keygen -t ed25519 -C "your-name@your-machine"
```

`~/.ssh/id_ed25519` (秘密鍵) と `~/.ssh/id_ed25519.pub` (公開鍵) ができます。**公開鍵 (`.pub`)** を管理者に送ってください。アカウントが作られ次第、ログインできるようになります。

### 2.3 `~/.ssh/config` の設定例

```
Host gpu01
    HostName gpu01           # tailnet 内の名前または IP
    User <your-username>
    IdentityFile ~/.ssh/id_ed25519
    ServerAliveInterval 60
```

接続:

```bash
ssh gpu01
```

初回ログイン時はパスワード変更を求められます（管理者が伝えた初期パスワードを入力 → 新しいパスワードを設定）。

## 3. VS Code Remote SSH

ローカルの VS Code から、サーバー上のファイルを直接編集・実行できます。

1. VS Code の拡張 `Remote - SSH` をインストール
2. 左下の青いボタン → **Remote-SSH: Connect to Host...**
3. 一覧に `gpu01`（`~/.ssh/config` に書いた名前）が出るので選択
4. 初回はリモート側に VS Code Server がインストールされます（数十秒）
5. 完了後、`File → Open Folder` でホームディレクトリを開けます

ターミナル (`Ctrl+\``) もそのままサーバー上で動きます。

## 4. GitHub に SSH 鍵を登録（サーバー側）

サーバー上で git push したい場合は、サーバー側でも SSH 鍵を作って GitHub に登録します。

```bash
# サーバー上で実行
ssh-keygen -t ed25519 -C "<your-username>@gpu01" -f ~/.ssh/id_ed25519_github
cat ~/.ssh/id_ed25519_github.pub
```

表示された公開鍵を [GitHub → Settings → SSH and GPG keys → New SSH key](https://github.com/settings/keys) に貼り付けます。

`~/.ssh/config` を作成:

```
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519_github
    IdentitiesOnly yes
```

確認:

```bash
ssh -T git@github.com
# Hi <your-username>! You've successfully authenticated...
```

> 💡 ホームディレクトリは mode 700 なので、他のユーザーから秘密鍵は見えません。安心してください。

## 5. Python 環境（uv / pixi）

このサーバーでは **CUDA Toolkit をネイティブにインストールしていません**。`uv` または `pixi` 経由で PyTorch（CUDA 同梱）を入れてください。

### 5.1 uv の基本

```bash
# プロジェクトを作成
mkdir myproject && cd myproject
uv init

# Python のバージョンを指定（自動でダウンロードされます）
uv python install 3.11

# パッケージを追加
uv add torch torchvision

# 実行
uv run python -c "import torch; print(torch.cuda.is_available())"
```

`uv add torch` だけで CUDA 対応 PyTorch が入ります（ホストに CUDA Toolkit は不要）。

### 5.2 pixi の基本

`pixi` は conda エコシステムを使いたいときに便利です。

```bash
pixi init myproject
cd myproject
pixi add python=3.11 pytorch
pixi run python my_script.py
```

## 6. GPU の使い方

### 6.1 空き状況を見る

```bash
gs        # gpustat -cp のエイリアス（おすすめ）
ns        # nvidia-smi のエイリアス
nsl       # watch -n 1 nvidia-smi
```

### 6.2 使う GPU を指定する

```bash
# GPU 0 番だけ使う
CUDA_VISIBLE_DEVICES=0 python train.py

# GPU 1, 3 番を使う
CUDA_VISIBLE_DEVICES=1,3 python train.py
```

何も指定しないと **全 GPU が見えてしまう** ので、必ず指定してください。

### 6.3 長時間ジョブは tmux で

```bash
tmux new -s train
# ↑この中で学習を起動
# Ctrl+b → d でデタッチ（ジョブは継続）
tmux attach -t train     # 戻る
```

## 7. 共有リソース

| パス | 用途 | 権限 |
|---|---|---|
| `/shared/datasets` | データセット（読み取り専用） | labmembers 読み |
| `/shared/models` | 学習済みモデル等 | labmembers 読み |
| `/shared/workspace` | 共同作業用 | labmembers 読み書き |
| `/scratch` | 一時ファイル | 全員 読み書き、**30日で削除されることがあります** |
| `/archive` | アーカイブ（管理者が書く） | labmembers 読み |

### HuggingFace モデルの共有キャッシュ

`HF_HOME` が `/shared/models/huggingface` に設定済みです。`from_pretrained()` で初回ダウンロードした重みは自動的に共有キャッシュに保存され、他の人もダウンロード不要で使えます。

**追加の設定は不要です。**

## 8. Docker

`docker` グループに入っているので **sudo 不要** です。

```bash
docker run --rm hello-world
```

GPU を使う場合:

```bash
docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi
```

研究用のイメージを動かす例:

```bash
docker run --rm -it --gpus all \
    -v /shared/datasets:/data:ro \
    -v $HOME/work:/workspace \
    pytorch/pytorch:2.4.0-cuda12.1-cudnn9-runtime bash
```

## 9. GUI / Jupyter (Optional)

GUI 必須のツールはなるべく避けてほしいですが、Jupyter を使いたい場合はサーバーで起動してローカルからポートフォワードします。

```bash
# サーバー側
jupyter lab --no-browser --port 8888 --ip 127.0.0.1
```

```bash
# ローカル側
ssh -N -L 8888:localhost:8888 gpu01
# → http://localhost:8888 をブラウザで開く
```

VS Code Remote SSH なら、`.ipynb` をそのまま開くだけで Jupyter サーバーは自動で立ち上がります。

リモートデスクトップが必要な場合は、Tailscale 経由で各自 noVNC / x11vnc 等をセットアップしてください（管理者にも相談を）。

## 10. Grafana ダッシュボード

監視スタックが起動していれば、Tailscale 経由で `http://<server>:3000` にアクセスできます。GPU 使用率、温度、メモリ、ホスト負荷を確認できます。

## 11. トラブルシュート / FAQ

[faq.md](faq.md) を参照してください。
