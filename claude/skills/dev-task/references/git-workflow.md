# ブランチ・worktree 自動作成 (フェーズ 7-1)

デフォルトブランチ (`master` / `main` / `develop`) 上で dev-task の実装が完了した場合に、直接コミットを避けて機能ブランチ + worktree を自動作成する手順。

## ブランチ名

いずれも `wakwak3125/` プレフィックス + タスク内容を表す kebab-case の短い slug:

- **Linear チケットモード** → `wakwak3125/<チケット ID>-<slug>` (例: `wakwak3125/EMRK-123-add-dark-mode`)
- **自然言語モード** → `wakwak3125/<slug>` (例: `wakwak3125/add-dark-mode`)

## worktree 作成手順

worktree は別ディレクトリに新規に切るため、現在の作業ツリーにある未コミット変更を stash で退避して持ち越す。worktree の配置はリポジトリの既存慣例に合わせる (`git worktree list` で既存の配置を確認。例: `<repo-parent>/worktree/<repo>/<slug>`):

```bash
wt_path=<repo-parent>/worktree/<repo>/<slug>
git stash push -u -m dev-task-autobranch
git worktree add -b <branch> "$wt_path" <default-branch>
git -C "$wt_path" stash pop
```

- `wt` (インタラクティブ zsh 関数) は非対話シェルから呼べないため、`git worktree add` を直接使う
- 以降の commit / push はこの worktree 内で行う (`git -C "$wt_path" ...` または `wt_path` を cwd にする)
