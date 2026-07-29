# CLAUDE.md - dotfiles

## 概要

macOS / WSL2/Linux 両対応の dotfiles リポジトリ。
シェル、エディタ、ターミナル、開発ツールの設定を一元管理する。
Windows 側ターミナル (WezTerm 等) の設定はこのリポジトリでは管理せず、WSL 内の CLI 環境を対象にする。

## ディレクトリ構成

```
dotfiles/
├── agents/           # Claude Code / Codex 向け agent 共通資産
│   ├── claude/       # Claude Code 用ドキュメント
│   │   ├── global/CLAUDE.md      # 全プロジェクト共通の個人指示 (-> ~/.claude/CLAUDE.md)
│   │   └── org/<org>/CLAUDE.md   # org 単位の個人指示 (gitignore; -> ~/src/github.com/<org>/CLAUDE.md)
│   ├── codex/        # Codex 用ドキュメント (中身は claude/ 側と同一に保つ)
│   │   ├── global/AGENTS.md      # 全プロジェクト共通の個人指示 (-> ~/.codex/AGENTS.md)
│   │   └── org/<org>/AGENTS.md   # org 単位の個人指示 (gitignore; -> ~/src/github.com/<org>/AGENTS.md)
│   ├── skills/       # 個人 skills (`gh skill` で Claude Code / Codex に install)
│   │   └── manifest.tsv # skill ごとの install 先 agent 定義
│   ├── agents/       # Claude Code subagent 定義 (spec-planner-*, japan-{ehr,receipt}-* 等)
│   └── hooks/        # 個人 hooks (worktree-create.sh 等) ※ファイル単位で symlink
├── config/           # XDG_CONFIG_HOME 配下の設定
│   ├── git/ignore    # グローバル gitignore
│   ├── ccstatusline/settings.json # Claude Code ステータスライン (mise: npm:ccstatusline 経由)
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
│   ├── bootstrap.sh  # 初期セットアップ (symlink 作成、gh skill install 含む)
│   ├── claude-status # Claude Code ダッシュボード
│   ├── install-agent-skills.sh # `gh skill` による個人 skills インストール
│   ├── install-neovim.sh    # Neovim インストーラ
│   ├── macos.sh             # macOS 専用セットアップ (Homebrew, GUI app config 等)
│   ├── wsl.sh               # WSL2/Linux 専用セットアップ (apt, WSL 補助ツール等)
│   ├── install-tools-macos.sh # macos.sh への互換ラッパー
│   ├── git-wt-herdr-hook.sh # git-wt の herdr 連携 hook (作成/削除時に herdr tab 操作)
│   ├── git-wt-tmux-hook.sh  # git-wt の tmux 連携 hook (herdr 外のとき herdr hook から委譲される)
│   └── git-wtclean-all      # 全 ghq リポジトリ横断で git wtclean を実行 (git wtclean-all)
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

### WSL2
- Windows 側の WezTerm 設定は dotfiles 管理外。WSL 内の zsh/tmux/nvim/mise 等だけを管理する。
- repo は `/mnt/c` 配下ではなく WSL filesystem 配下に置く。
- clipboard は `win32yank.exe` があれば Neovim が優先利用し、なければ `clip.exe`/PowerShell に fallback する。

## 変更時の注意事項

- **OS 分岐**: `.zshrc` や `bootstrap.sh` に macOS/Linux の条件分岐あり。片方だけ壊さないよう注意
- **symlink**: 設定ファイルと Claude Code 用 agents/hooks は symlink で管理。skills は `gh skill` でコピーインストールする
- **agent docs**: `agents/claude/{global,org}` (CLAUDE.md) と `agents/codex/{global,org}` (AGENTS.md) は同一内容を保つ (エージェント固有指示が必要なときだけ分岐)。global は追跡、org は gitignore 対象。bootstrap で symlink される
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
- `git wt` コマンド: git worktree ヘルパー ([k1LoW/git-wt](https://github.com/k1LoW/git-wt)、mise で導入)。worktree 配置・multiplexer 連携・cd は git config (`wt.basedir`/`wt.hook`/`wt.deletehook`/`wt.nocd`) で制御。連携の実体は `script/git-wt-herdr-hook.sh` (herdr 外では `git-wt-tmux-hook.sh` へ委譲)。マージ済み/gone ブランチの掃除は `git wtclean` (= `gh poi` + `git worktree prune`)。全リポジトリ横断は `git wtclean-all` (`script/git-wtclean-all`; worktree を持つ repo だけ対象、`-n` で dry-run)

### Neovim
- lazy.nvim でプラグイン管理
- 2スペースインデント、true color、system clipboard 連携

## テスト方法

設定変更後の確認:
1. 新しいターミナルで herdr にアタッチし設定が反映されるか確認 (`herdr server reload-config` でも可)
2. `sheldon lock` がエラーなく完了するか確認
3. `mise doctor` で mise の状態を確認
