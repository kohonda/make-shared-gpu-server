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
- `HF_HUB_CACHE` は `/shared/cache/huggingface/hub` を指しているので、`from_pretrained()` の重みは共有側に行きます。`~/.cache/huggingface/hub` に古いキャッシュが残っていれば削除してください（`~/.cache/huggingface/token` はログイン情報なので消さない）。
- `du -sh ~/.cache/* | sort -h` で確認。

## Q. 他の人が GPU を使い切っていて学習できない

- まず `gs` で空き状況を確認。
- 1 GPU だけ使う設定 (`CUDA_VISIBLE_DEVICES=N`) で詰めます。
- 完全に塞がっている場合は Slack などで他のメンバーと調整してください。

## Q. SSH で繋がらない / `Could not resolve hostname` / cannot connect

- Share（マシンの共有）で受け入れられた場合、サーバーには **FQDN（`<host>.<tailnet>.ts.net`）か Tailscale IP（`100.x.x.x`）でしか届きません**。`ssh alice@gpu01` のような短い名前や、`~/.ssh/config` の `HostName gpu01` では届きません。管理者から伝えられた FQDN を使ってください。
  If you were onboarded via a share, use the FQDN or the Tailscale IP; a short name such as `gpu01` does not resolve.
- 共有を承認したか確認してください。承認していれば `tailscale status` に共有されたサーバーが出ます。 / Check that you accepted the share: the shared server then appears in `tailscale status`.
- 自分の PC で Tailscale が動いているか確認してください（Linux なら `sudo tailscale up`）。 / Make sure Tailscale is running on your machine (`sudo tailscale up` on Linux).
- lab の tailnet に招待されていて、Fast User Switching で個人の tailnet に切り替えたままになっていませんか？同時にアクティブなのは1アカウントだけです（[getting-started.ja.md](getting-started.ja.md) / [en](getting-started.en.md) の Fast User Switching 節）。 / If you were invited to the lab tailnet, check you have not switched to your personal tailnet: only one account is active at a time.

## Q. SSH 接続が頻繁に切れる

- `~/.ssh/config` に `ServerAliveInterval 60` を入れる。
- 学習は `tmux` 内で（[6.4 長時間ジョブを止めない](getting-started.ja.md#64-長時間ジョブを止めないtmux--herdr) / [Keep long jobs running](getting-started.en.md#keep-long-jobs-running-tmux--herdr)）。

## Q. SSH が切れたらプログラムが止まった / My program stopped when SSH disconnected

- SSH 直下で起動したプログラムは、切断で止まることがあります。VS Code のターミナルでも同じです。 / A program started directly in an SSH session can stop when the connection drops, in the VS Code terminal too.
- 次回からは `tmux` か `herdr` の中で起動してください（[6.4 長時間ジョブを止めない](getting-started.ja.md#64-長時間ジョブを止めないtmux--herdr) / [Keep long jobs running](getting-started.en.md#keep-long-jobs-running-tmux--herdr)）。 / Next time, start it inside `tmux` or `herdr`.

## Q. Docker から GPU が見えない

- Docker を使うには管理者の許可が必要です。`permission denied` と出る場合は、管理者に許可を依頼してください。許可後は、次回ログインから `sudo` なしで使えます。
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

- 一般ユーザーは sudo 権限を持ちません。必要なソフトは `uv` / `pixi` で完結させてください。Docker は管理者の許可制です。
- 本当に必要なら管理者に相談。
