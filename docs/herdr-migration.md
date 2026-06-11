# tmux → herdr 移行メモ

マルチプレクサを tmux から [herdr.dev](https://herdr.dev/)（agent-aware な永続セッション TUI）へ移行するための設計・進捗メモ。

- **最終更新**: 2026-06-11
- **ステータス**: 設定移行 完了（tmux は併存期間中のみ残る）/ 実機での初回アタッチ確認が残り
- **進め方**: 段階的。G1 検証 ✅ → config 翻訳 ✅ → widget/hook 移行 ✅ → 実機確認 → tmux 完全廃止

---

## 目的

tmux を、tmux 互換の永続セッションに **エージェント状態追跡・sidebar・通知・組み込み worktree** を足した herdr へ置き換える。`hiroppy/tmux-agent-sidebar` + `claude-status` で自作していたエージェント可視化が、herdr のコア機能で標準化される点が主な動機。

## herdr の概念モデル

tmux より 1 段深い 4 層構造。各層の意味も tmux とは異なる。

```
tmux :  session(作業群)      → window(ビュー)   → pane
herdr:  session(分離namespace) → workspace(1 repo/task) → tab(役割ビュー) → pane
```

- **session**: 完全分離された runtime namespace（socket・ストアが別）。公式は「完全分離が要る時だけ named session、それ以外は workspace を使え」と明記
- **workspace**: 「1 repo / 1 task / 1 investigation」のプロジェクト container
- **tab**: workspace 内の役割別ビュー（agents / logs / servers）
- **pane**: 実ターミナル
- 設定: `~/.config/herdr/config.toml`（TOML）、theme に `nord` 組込み
- sidebar が agent 状態（idle / working / blocked / done）を rollup 表示
- PTY はサーバ常駐で detach しても生存
- CLI: `herdr workspace/tab/pane/agent/session/worktree/config/notification/wait ...`

## 採用した設計 — 案A「1 段スライド」

tmux の役割をそのまま 1 段ずつ下げる。session は**単一 default**（named session は使わない）。

| 現状(tmux) | → | 移行後(herdr) |
|---|---|---|
| session = repo | → | **workspace = repo** |
| window = branch/worktree | → | **tab = branch/worktree** |
| pane = 作業 | → | pane（変えない） |
| `main` session | → | default session の workspace |
| `session-closed` hook（main 死守） | → | **廃止**（サーバ常駐で「消える」概念が薄い） |
| auto-attach | → | `herdr-auto-attach` に書き換え済み |
| agent 可視化（tmux-agent-sidebar + claude-status） | → | **herdr sidebar が標準吸収** |

## G1 実機検証の結果（2026-06-11 確定 / herdr v0.6.9）

**G1 成立。** pane 内シェルに以下の env が常設されることを実機確認した:

| env | 用途 | tmux 相当 |
|---|---|---|
| `HERDR_ENV=1` | herdr 内検出（内外分岐は `[[ -n "$HERDR_ENV" ]]`） | `$TMUX` |
| `HERDR_PANE_ID=p_N` | pane 識別（legacy 形式。`herdr pane get` が受理） | `$TMUX_PANE` |
| `HERDR_SOCKET_PATH` | API socket パス | — |

確認済みの CLI 経路:

- `herdr pane get "$HERDR_PANE_ID"` → JSON で `tab_id` / `workspace_id` を逆引き可。
  存在しない pane id には非ゼロ exit（claude-status の生存判定に利用）
- `herdr tab rename/list/create/focus/close/get`、`herdr workspace list/create/focus/get`
  （`create` の `--focus`/`--no-focus` 含む）が JSON を返す（jq でパース）
- `herdr status server --json` → top-level の `.running` でサーバ稼働判定
- herdr CLI はサーバ非稼働時に失敗する → widget/hook はすべて best-effort（失敗しても本体操作を妨げない）

**重要な発見**: `herdr worktree open` は worktree を **workspace として**開く（案B 相当のモデル）。
案A「worktree = tab」とは不整合のため、worktree tab の生成は
`herdr tab create --workspace <repo-ws-id> --cwd <worktree-path> --label <branch>` で自前実装し、
`herdr worktree` サブコマンドは使わない。
workspace の特定は label = repo basename（`.`→`_` 置換。tmux 時代の session 名規約を踏襲）で
`herdr workspace list` からマッチさせる。

## switcher 系は全廃（実施済み）

| 対象 | 処遇 | 理由 |
|---|---|---|
| tmux-switcher（`w`）/ repo-switch（`g`）/ worktree-switch（`W`）/ toggle-pane | **削除済み** | 移動・俯瞰は herdr **sidebar が上位互換**。生成導線は zshrc の `^]`(ghq) / `^w`(worktree) ZLE widget に集約 |
| tmux-git-switch（`B`）/ tmux-file-select（`f`/`F`） | **削除済み** | ほぼ未使用。必要になれば multiplexer 非依存の ZLE widget で復元 |

## 実装内容（2026-06-11 完了）

| # | 対象 | 内容 |
|---|---|---|
| 1 | `config/herdr/config.toml` | 新規。tmux.conf の案A 翻訳。prefix=Ctrl+T / theme=nord / pane 移動 Shift+矢印 / tab 移動 Alt+←→ / workspace 移動 Alt+↑↓ / toast=herdr |
| 2 | `zsh/.zshrc` | precmd の branch 名 rename を herdr tab rename 対応（tab_id キャッシュ + 差分時のみ送信）。`^]` widget → workspace focus/create、`^w` widget → tab focus/create。herdr → tmux → cd の優先分岐 |
| 3 | `zsh/functions/herdr-auto-attach` | 新規（tmux-auto-attach は削除）。ログインシェルで `exec herdr`。IDE 除外は踏襲、`AUTO_HERDR=false` で無効化 |
| 4 | `script/git-wt-herdr-hook.sh` | 新規。wt.hook/wt.deletehook の herdr 版（tab create/close）。herdr 外では `git-wt-tmux-hook.sh` へ委譲するので併存期間も両対応 |
| 5 | `script/claude-status` | pane/session 識別を `HERDR_PANE_ID` 優先に。pane 生存判定・workspace/tab label 取得を herdr CLI 対応（サーバ非稼働時は生存扱いで誤削除防止） |
| 6 | `script/bootstrap.sh` | config/herdr symlink 追加、switcher 系 symlink 削除（残存掃除込み）、tpm clone 削除、wt.hook → herdr hook |
| 7 | `config/tmux/tmux.conf` | switcher 系 bind (`w`/`B`/`g`/`W`/`f`/`F`) 削除、tpm 読み込みを存在ガード付きに（併存期間用の最小変更） |

## 残作業

1. **実機での初回アタッチ確認**: `herdr` でアタッチし、キーバインド（特に direct binding の Shift+矢印 / Alt+矢印は端末依存）と theme を確認する。herdr は不正なキー構文を**警告なしで無視する**ため、効かないバインドがあれば構文を見直す
2. **`herdr integration install claude`**: Claude Code の agent 状態を sidebar に出す組み込み統合。`~/.claude/settings.json` に手を入れる可能性があるため bootstrap には入れず手動で実行する
3. **tmux 完全廃止**（herdr 安定運用後）: tmux.conf / git-wt-tmux-hook.sh / `.zshrc` の tmux 分岐 / tmux-kill-all / mise の tmux を削除

## 未解決の前提・割り切り

- **G2（割り切り）**: ステータスバーの自由カスタマイズ不可。現状の Powerline / ブランチ名 / battery / prefix-highlight / 日付 / ホスト名表示は喪失し、`[theme] name = "nord"` 止まり
- tab 名の branch 自動 rename は precmd 駆動のため、同一 tab に複数 pane があると最後にプロンプトを表示した pane が勝つ（tmux 時代と同じ仕様）

## 導入情報

| 項目 | 内容 |
|---|---|
| バージョン | herdr **v0.6.9** |
| 導入方法 | mise。registry 未登録のため backend 指定 `"github:ogulcancelik/herdr" = "latest"` を `config/mise/config.toml` に追記 |
| 検証 | SLSA provenance 検証通過、shim 生成済み、`herdr --version` 確認済み |
| repo | herdr.dev 公式の `ogulcancelik/herdr`（★5.3k, Rust） |

他マシンでの再現は `mise install`（`install-tools-macos.sh` が呼ぶ）で効くため、install スクリプトの変更は不要。
