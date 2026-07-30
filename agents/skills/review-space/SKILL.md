---
name: review-space
description: "コードレビュー環境を herdr 上に一発構築する。repo の workspace (なければ作成) に review tab を追加し、hunk (diff 表示) と Claude Code を 2 pane で開いて、Claude Code に hunk セッションへのインラインレビューコメント記入まで自動で任せる。PR があれば PR diff、なければベースブランチとの diff (PR 作成前のセルフレビュー) を対象にする。「レビュー space 開いて」「PR #N をレビュー環境で見たい」「セルフレビューして」「PR 作る前に見ておいて」等で発火。dev-task 等の他 skill が PR 作成前後に呼び出すことも想定。herdr 内 (HERDR_ENV=1) でのみ動作する。"
---

# review-space

コードレビュー用の herdr tab を一発で組み立てる skill。

- 同じ repo の workspace (案A 規約: workspace = repo 名) があればそこへ、なければ workspace を作ってから、review tab を追加して focus する
- 左 pane: hunk で diff を表示
  - PR モード: `gh pr diff <PR> | hunk patch` (tab 名 `review:#<N>`)
  - diff モード (PR なし): `hunk diff --watch <merge-base>` でベースブランチ比較、未コミット・未追跡の変更も含み、コード変更は diff へ自動反映される (tab 名 `review:<base>..<branch>`)
- 右 pane: Claude Code を起動し、hunk セッションにインラインレビューコメントを書くプロンプトを投入
- ユーザーは左の hunk でコメントを眺めながらレビューできる

## 実行方法

このスキルのディレクトリにあるスクリプトを実行するだけでよい:

```bash
bash <skill-dir>/scripts/open-review-space.sh [-C <repo-dir>] [PR番号]
```

- `PR番号` 省略時はカレントブランチの PR を `gh pr view` で解決し、なければ diff モードに自動で切り替わる
- `-C <repo-dir>`: 対象リポジトリ (worktree) の外から呼ぶときに指定する
- 再実行は冪等: 同名のレビュアー agent が生きていればその pane に focus するだけで作り直さない (判定はレビュー対象から決定的に生成する agent 名で行う)

実行後はスクリプトの出力 (workspace / tab / pane / agent 名) をそのままユーザーに報告して終了する。**レビュー完了を待たないこと** — レビュアー agent はバックグラウンドで動き続ける。

## 前提条件

- herdr 内で実行していること (`HERDR_ENV=1`)。満たさない場合はその旨を伝えて止まる
- `herdr` / `jq` / `gh` / `hunk` が PATH にあること

## 他の skill / agent からの呼び出し

PR 作成前後のフックとして呼ぶ場合も同じスクリプトを実行するだけでよい:

```bash
bash ~/.claude/skills/review-space/scripts/open-review-space.sh -C /path/to/worktree [<PR番号>]
```

呼び出し元の cwd が対象リポジトリでない場合は `-C` を必ず渡すこと。PR を作った直後に呼ぶなら PR 番号も明示的に渡すのが確実 (ベースブランチ側の cwd では自動解決できないため)。

## 進捗確認・トラブルシュート

- レビューの進み具合: `herdr agent get <agent名>` / `herdr agent read <agent名> --source recent-unwrapped --lines 80`
- レビュアーが承認待ちで止まっている (`blocked`) 場合は `herdr agent read` で状況を確認してからユーザーに知らせる
- hunk セッションが見つからないとレビュアーが報告してきた場合は、左 pane の起動失敗を疑い `herdr pane read <hunk pane>` を確認する
- tab を作り直したいときは `herdr tab close <tab_id>` してから再実行する
