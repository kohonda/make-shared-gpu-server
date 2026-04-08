# FAQ

> 日本語 / English mixed.

## Q. `torch.cuda.is_available()` が False / returns False

- Did you install torch via `uv add torch` (or `pixi add pytorch`)? The host has no system CUDA.
- `nvidia-smi` is working? `gs` でも何も出ないなら GPU 自体が落ちている可能性 → 管理者に連絡。
- venv をホスト Python から作っていませんか？ uv プロジェクト内では `uv run` を使ってください。

## Q. `Permission denied` で `/shared/workspace` に書けない

- `id` で `labmembers` グループに入っているか確認。新規ユーザーは入っているはずです。
- 入っていない場合は管理者に連絡。

## Q. 自分のホームの空き容量がない

- HuggingFace モデルや torch チェックポイントが `~/.cache` を圧迫していませんか？
- `HF_HOME` は `/shared/models/huggingface` を指しているので、`from_pretrained()` の重みは共有側に行きます。手動で `~/.cache/huggingface` にキャッシュした分は削除してください。
- `du -sh ~/.cache/* | sort -h` で確認。

## Q. 他の人が GPU を使い切っていて学習できない

- まず `gs` で空き状況を確認。
- 1 GPU だけ使う設定 (`CUDA_VISIBLE_DEVICES=N`) で詰めます。
- 完全に塞がっている場合は Slack などで他のメンバーと調整してください。

## Q. SSH 接続が頻繁に切れる

- `~/.ssh/config` に `ServerAliveInterval 60` を入れる。
- 学習は `tmux` 内で。

## Q. Docker から GPU が見えない

- `docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi` で確認。
- 出ない場合は管理者に。`nvidia-ctk runtime configure --runtime=docker` の再実行で直ることがあります。

## Q. /scratch のファイルが消えた

- `/scratch` は一時領域で、30 日経過したファイルは自動削除される場合があります（cron で設定可能）。
- 長期保存したいものは `/shared/workspace` か `/archive` に移してください。

## Q. パスワードを変えたい / 忘れた

- 通常、一般ユーザーはパスワードを持っていません（Tailscale SSH 経由でログインするため）。
- `sudo` を使う必要が出てパスワードが必要になった場合は、**管理者に設定を依頼**してください。
- すでに自分でパスワードを設定している場合は `passwd` で変更できます。

## Q. sudo したい

- 一般ユーザーは sudo 権限を持ちません。必要なソフトは `uv` / `pixi` / `docker` で完結させてください。
- 本当に必要なら管理者に相談。
