# CLAUDE.md - dotfiles

## 概要

macOS / WSL2/Linux 両対応の dotfiles リポジトリ。
シェル、エディタ、ターミナル、開発ツールの設定を一元管理する。
Windows 側ターミナル (WezTerm 等) の設定はこのリポジトリでは管理せず、WSL 内の CLI 環境を対象にする。

## ディレクトリ構成

```
dotfiles/
├── claude/           # Claude Code 関連 (~/.claude/ 配下に symlink)
│   ├── skills/       # 個人 skills (spec-planner-plan, spec-planner-revise 等)
│   ├── agents/       # 個人 subagent 定義 (spec-planner-*, japan-{ehr,receipt}-* 等)
│   └── hooks/        # 個人 hooks (worktree-create.sh 等) ※ファイル単位で symlink
├── config/           # XDG_CONFIG_HOME 配下の設定
│   ├── git/ignore    # グローバル gitignore
│   ├── herdr/config.toml    # herdr 設定 (prefix: Ctrl+T; tmux からの移行先)
│   ├── karabiner/    # Karabiner-Elements 設定 (macOS)
│   ├── mise/config.toml    # ランタイム管理 (Go, Java, Node, Rust, CLI tools)
│   ├── sheldon/plugins.toml # zsh プラグイン管理
│   ├── starship.toml        # プロンプトテーマ
│   ├── terminator/   # Terminator 設定 (Linux)
│   ├── tmux/tmux.conf       # tmux 設定 (併存期間中のみ。herdr へ移行中)
│   └── zed/settings.json    # Zed エディタ設定 (macOS)
├── docs/             # 設計・移行メモ (herdr-migration.md 等)
├── gitconfig         # Git グローバル設定
├── nvim/init.lua     # Neovim 設定 (lazy.nvim)
├── pbcopy            # pbcopy polyfill (Linux/WSL)
├── pbpaste           # pbpaste polyfill (Linux/WSL)
├── script/           # インストール・ユーティリティスクリプト
│   ├── bootstrap.sh  # 初期セットアップ (symlink 作成含む)
│   ├── claude-status # Claude Code ダッシュボード
│   ├── install-neovim.sh    # Neovim インストーラ
│   ├── macos.sh             # macOS 専用セットアップ (Homebrew, GUI app config 等)
│   ├── wsl.sh               # WSL2/Linux 専用セットアップ (apt, WSL 補助ツール等)
│   ├── install-tools-macos.sh # macos.sh への互換ラッパー
│   ├── mise.toml            # mise タスク定義 (ghq等; メイン設定は config/mise/config.toml)
│   ├── git-wt-herdr-hook.sh # git-wt の herdr 連携 hook (作成/削除時に herdr tab 操作)
│   └── git-wt-tmux-hook.sh  # git-wt の tmux 連携 hook (herdr 外のとき herdr hook から委譲される)
├── zsh/
│   ├── .zshrc        # メインシェル設定
│   ├── .zshrc_local  # マシン固有設定 (gitignore対象; Homebrew PATH, gcloud等)
│   └── functions/    # カスタム関数 (herdr-auto-attach, yolo, _gh)
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
1. OS 判定後、macOS は `script/macos.sh`、WSL2/Linux は `script/wsl.sh` を実行
2. Neovim インストール
3. 各設定ファイルの symlink 作成 (~/.zsh, ~/.config/nvim, herdr, tmux, sheldon, mise, starship)
4. スクリプトを ~/.local/bin にインストール

### WSL2
- Windows 側の WezTerm 設定は dotfiles 管理外。WSL 内の zsh/tmux/nvim/mise 等だけを管理する。
- repo は `/mnt/c` 配下ではなく WSL filesystem 配下に置く。
- clipboard は `win32yank.exe` があれば Neovim が優先利用し、なければ `clip.exe`/PowerShell に fallback する。
- WSL では Windows 側ターミナル起動時の失敗を避けるため `herdr` auto attach はデフォルト無効。必要なら `~/.zsh/.zshrc_local` に `AUTO_HERDR=true` を置く。

## 変更時の注意事項

- **OS 分岐**: `.zshrc` や `bootstrap.sh` に macOS/Linux の条件分岐あり。片方だけ壊さないよう注意
- **symlink**: 設定ファイルは symlink で管理。直接 `~/.config/` を編集しない
- **sheldon**: プラグイン変更後は `sheldon lock` が必要
- **mise**: ツール追加/変更後は `mise install` で反映
- **zshrc_local**: マシン固有設定（gitignore対象）。シェルデバッグ時は `.zshrc` から読み込まれることに注意

## 主要ツールと設定のポイント

### herdr (マルチプレクサ。tmux から移行中: docs/herdr-migration.md)
- prefix: `Ctrl+T`（tmux 時代を踏襲）
- 案A「1段スライド」: workspace = repo / tab = branch・worktree / pane = 作業
- pane 移動: Shift+矢印 / tab 移動: Alt+←→ / workspace 移動: Alt+↑↓
- herdr 内検出は `$HERDR_ENV`、pane 識別は `$HERDR_PANE_ID`（widget/hook が利用）
- tmux は併存期間中のみ残る（switcher 系スクリプトは全廃済み）

### zsh
- FZF ウィジェット: `Ctrl+R`(履歴), `Ctrl+]`(ghq → herdr workspace), `Ctrl+W`(worktree → herdr tab)
- `git wt` コマンド: git worktree ヘルパー ([k1LoW/git-wt](https://github.com/k1LoW/git-wt)、mise で導入)。worktree 配置・multiplexer 連携・cd は git config (`wt.basedir`/`wt.hook`/`wt.deletehook`/`wt.nocd`) で制御。連携の実体は `script/git-wt-herdr-hook.sh` (herdr 外では `git-wt-tmux-hook.sh` へ委譲)。マージ済み/gone ブランチの掃除は `git wtclean` (= `gh poi` + `git worktree prune`)

### Neovim
- lazy.nvim でプラグイン管理
- 2スペースインデント、true color、system clipboard 連携

## テスト方法

設定変更後の確認:
1. 新しいターミナルで herdr にアタッチし設定が反映されるか確認 (`herdr server reload-config` でも可)
2. `sheldon lock` がエラーなく完了するか確認
3. `mise doctor` で mise の状態を確認
