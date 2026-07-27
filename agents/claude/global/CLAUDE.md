# CLAUDE.md (User-Level)

このファイルは全プロジェクト共通の個人用エージェント指示です。
CLAUDE.md (Claude Code) と AGENTS.md (Codex) は同一内容を保つこと。エージェント固有の指示が必要なときだけ分岐させる。

## 大事なこと

ユーザーのことはワクさんと呼ぶこと

## 基本方針

- 応答は日本語。コード・識別子は英語。コードコメントは日本語。
- コミットメッセージ・PR タイトルは日本語、conventional commits スタイルで書く
- 簡潔で実用的な回答を優先する。冗長な説明は不要
- コード変更時は既存のコードスタイル・パターンに従う
- Linear / Notion / 社内ブログなど日本語の設計ドキュメント・技術文書を書く/推敲するときは、必ず japanese-tech-writing skill を使うこと

## 開発環境

- **OS**: macOS (一部 Linux 対応あり)
- **エディタ**: Neovim (lazy.nvim, 2スペースインデント)
- **シェル**: zsh + sheldon (プラグイン管理)
- **ターミナル**: herdr (prefix: Ctrl+T; tmux から移行中)
- **ランタイム管理**: mise (Go, Java 21, Node.js, Rust)
- **プロンプト**: Starship

## Git ワークフロー

- 作業前に origin のベースブランチで rebase すること
- ブランチ名は wakwak3125/ を prefix とし、ケバブケースで命名すること (例: wakwak3125/awsome-feature)。org のリポジトリでチケット ID 起点の命名規約がある場合は org 設定に従う
- **worktree ベース開発**: `git wt` ([k1LoW/git-wt](https://github.com/k1LoW/git-wt)) で管理。worktree は `<org>/worktree/<repo>/` に格納 (例: `wakwak3125/worktree/dotfiles/`)。マージ済み/gone ブランチの掃除は `git wtclean`
- **PR 作成**: `gh pr create` を使用
- push する際、origin のベースブランチと比較し、rebase が必要な場合は必ず rebase の上 push すること

## Auto memory 運用方針 (Claude Code 固有)

標準の memory 指示 (MEMORY.md は目次、既存エントリとの統合、リポジトリから導出できる情報は保存しない) に加えて:

- 保存対象は「コードと公式ドキュメントから導出できないこと」だけ: 再現に時間がかかったバグの根本原因と回避策 / ユーザーが明示的に訂正した好み・規約 (訂正された事実ごと記録) / ドキュメント化されていない環境・ビルドの罠
- 未確認の推測は保存しない。迷ったら保存しない

## org 固有設定

組織・会社固有の設定は `~/src/github.com/<org>/CLAUDE.md` および `AGENTS.md` に置く (dotfiles の `agents/claude/org/<org>/CLAUDE.md` / `agents/codex/org/<org>/AGENTS.md` から symlink、gitignore 対象)。その org 配下のリポジトリ・worktree で作業するときだけ読み込まれる。

## 注意事項

- `.claude/settings.local.json` は git ignore 対象 (秘匿情報を含む可能性)
