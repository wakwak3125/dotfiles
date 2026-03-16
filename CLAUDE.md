# CLAUDE.md - dotfiles

## 概要

macOS / Linux 両対応の dotfiles リポジトリ。
シェル、エディタ、ターミナル、開発ツールの設定を一元管理する。

## ディレクトリ構成

```
dotfiles/
├── config/           # XDG_CONFIG_HOME 配下の設定
│   ├── git/ignore    # グローバル gitignore
│   ├── karabiner/    # Karabiner-Elements 設定 (macOS)
│   ├── mise/config.toml    # ランタイム管理 (Go, Java, Node, Rust, CLI tools)
│   ├── sheldon/plugins.toml # zsh プラグイン管理
│   ├── starship.toml        # プロンプトテーマ
│   ├── terminator/   # Terminator 設定 (Linux)
│   └── tmux/tmux.conf       # tmux 設定 (prefix: Ctrl+T)
├── gitconfig         # Git グローバル設定
├── nvim/init.lua     # Neovim 設定 (lazy.nvim)
├── pbcopy            # pbcopy polyfill (Linux)
├── script/           # インストール・ユーティリティスクリプト
│   ├── bootstrap.sh  # 初期セットアップ (symlink 作成含む)
│   ├── claude-status # Claude Code ダッシュボード
│   ├── install-neovim.sh    # Neovim インストーラ
│   ├── install-tools-macos.sh # macOS ツールインストール
│   ├── mise.toml            # mise タスク定義
│   ├── tmux-file-select     # FZF ファイルセレクター
│   ├── tmux-git-switch      # FZF git ブランチスイッチャー
│   ├── tmux-repo-switch     # FZF ghq リポジトリスイッチャー
│   └── tmux-switcher        # FZF tmux ウィンドウスイッチャー
├── zsh/
│   ├── .zshrc        # メインシェル設定
│   └── functions/    # カスタム関数 (wt, tmux-auto-attach, _gh)
├── zshenv            # 環境変数
├── ideavimrc         # IntelliJ IdeaVim 設定
├── keymap/           # キーマップ設定
└── obsidian.vimrc    # Obsidian Vim モード設定
```

## セットアップ方法

```bash
# 初回セットアップ
./script/bootstrap.sh
```

bootstrap.sh が以下を実行:
1. Linux の場合: build-essential, openssl, fzf, ripgrep 等をインストール
2. Neovim インストール
3. 各設定ファイルの symlink 作成 (~/.zsh, ~/.config/nvim, tmux, sheldon, mise, starship)
4. スクリプトを ~/.local/bin にインストール

## 変更時の注意事項

- **OS 分岐**: `.zshrc` や `bootstrap.sh` に macOS/Linux の条件分岐あり。片方だけ壊さないよう注意
- **symlink**: 設定ファイルは symlink で管理。直接 `~/.config/` を編集しない
- **sheldon**: プラグイン変更後は `sheldon lock` が必要
- **mise**: ツール追加/変更後は `mise install` で反映

## 主要ツールと設定のポイント

### tmux
- prefix: `Ctrl+T`（デフォルトの Ctrl+B ではない）
- vi-mode キーバインド
- カスタムキー: `w`(FZF窓切替), `B`(ブランチ切替), `g`(ghq), `f`(ファイル検索), `F`(ツリー検索), `c`(Claude Code), `C`(新ウィンドウ)

### zsh
- FZF ウィジェット: `Ctrl+R`(履歴), `Ctrl+G`(ghq), `Ctrl+W`(worktree)
- `wt` 関数: git worktree + tmux 連携ヘルパー

### Neovim
- lazy.nvim でプラグイン管理
- 2スペースインデント、true color、system clipboard 連携

## テスト方法

設定変更後の確認:
1. 新しい tmux セッションを開いて設定が反映されるか確認
2. `sheldon lock` がエラーなく完了するか確認
3. `mise doctor` で mise の状態を確認
