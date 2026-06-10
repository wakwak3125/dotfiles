#! /bin/bash

cd `dirname $0`
ROOT=`dirname $(pwd)`
CONFIG_DIR='~/.config'

# ================================================
# sudo が必要な処理をまとめて最初に実行
# ================================================
if [ "$(uname)" != "Darwin" ]; then
  echo "==> Installing system packages (sudo required)..."
  sudo apt update
  sudo apt install -y \
    build-essential \
    openssl \
    libssl-dev \
    pkg-config \
    fzf \
    jq \
    ripgrep \
    xdg-utils
fi

# Neovimのインストール（sudo が必要）
$ROOT/script/install-neovim.sh

# ================================================
# シンボリックリンクの作成
# ================================================
ln -sfv $ROOT/ideavimrc $HOME/.ideavimrc
ln -sfv $ROOT/obsidian.vimrc $HOME/.obsidian.vimrc
# ディレクトリ向け symlink は -n を付けないと既存 link を辿って中にネストを作る
ln -sfnv $ROOT/zsh $HOME/.zsh
ln -sfv $ROOT/zshenv $HOME/.zshenv
ln -sfnv $ROOT/nvim $HOME/.config/nvim

if [ ! -d ~/.config/tmux ]; then
  mkdir -p ~/.config/tmux
  echo '~/.config/tmux was created'
fi

ln -sfv $ROOT/config/tmux/tmux.conf $HOME/.config/tmux/tmux.conf

# スクリプトをパスに追加
mkdir -p $HOME/.local/bin
ln -sfv $ROOT/script/claude-status $HOME/.local/bin/claude-status
ln -sfv $ROOT/script/tmux-switcher $HOME/.local/bin/tmux-switcher
ln -sfv $ROOT/script/tmux-git-switch $HOME/.local/bin/tmux-git-switch
ln -sfv $ROOT/script/tmux-repo-switch $HOME/.local/bin/tmux-repo-switch
ln -sfv $ROOT/script/tmux-worktree-switch $HOME/.local/bin/tmux-worktree-switch
ln -sfv $ROOT/script/tmux-file-select $HOME/.local/bin/tmux-file-select
ln -sfv $ROOT/script/tmux-toggle-pane $HOME/.local/bin/tmux-toggle-pane
ln -sfv $ROOT/script/git-wt-tmux-hook.sh $HOME/.local/bin/git-wt-tmux-hook.sh

if [ ! -d ~/.config/alacritty ]; then
  mkdir -p ~/.config/alacritty
  echo '~/.config/alacritty was created'
fi

ln -sfv $ROOT/config/alacritty/alacritty.yml $HOME/.config/alacritty/alacritty.yml

if [ ! -d ~/.config/sheldon ]; then
  mkdir -p ~/.config/sheldon
  echo '~/.config/sheldon was created'
fi

ln -sfv $ROOT/config/sheldon/plugins.toml $HOME/.config/sheldon/plugins.toml

if [ ! -d ~/.config/mise ]; then
  mkdir -p ~/.config/mise
  echo '~/.config/mise was created'
fi

ln -sfv $ROOT/config/mise/config.toml $HOME/.config/mise/config.toml

ln -sfv $ROOT/config/starship.toml $HOME/.config/starship.toml

if [ ! -d ~/.config/git ]; then
  mkdir -p ~/.config/git
  echo '~/.config/git was created'
fi

ln -sfv $ROOT/config/git/ignore $HOME/.config/git/ignore

# Claude Code 個人 skills
if [ ! -d ~/.claude ]; then
  mkdir -p ~/.claude
  echo '~/.claude was created'
fi

# `-n` を付けないと既存の symlink を辿って中にリンクを作ってしまう
if [ ! -L ~/.claude/skills ]; then
  rm -rf ~/.claude/skills
fi
ln -sfnv $ROOT/claude/skills $HOME/.claude/skills

# Claude Code 個人 agents
if [ ! -L ~/.claude/agents ]; then
  rm -rf ~/.claude/agents
fi
ln -sfnv $ROOT/claude/agents $HOME/.claude/agents

# Claude Code フックスクリプト (ディレクトリは symlink にしない: nono など外部ツールが配置するファイルと共存させる)
if [ ! -d ~/.claude/hooks ]; then
  mkdir -p ~/.claude/hooks
  echo '~/.claude/hooks was created'
fi
ln -sfv $ROOT/claude/hooks/worktree-create.sh $HOME/.claude/hooks/worktree-create.sh

# Claude Code org 単位の CLAUDE.md (claude/orgs/<org>.CLAUDE.md → ~/src/github.com/<org>/CLAUDE.md)
# claude/orgs/ は gitignore 対象 (会社固有情報を含むため)。ファイルがあるマシンでのみ symlink を張る
if [ -d "$ROOT/claude/orgs" ]; then
  for org_md in "$ROOT"/claude/orgs/*.CLAUDE.md; do
    [ -f "$org_md" ] || continue
    org=$(basename "$org_md" .CLAUDE.md)
    if [ -d "$HOME/src/github.com/$org" ]; then
      ln -sfv "$org_md" "$HOME/src/github.com/$org/CLAUDE.md"
    fi
  done
fi

# Claude Code settings.json に WorktreeCreate フック設定をマージ
# settings.json は API キー等の機密混在のため symlink せず、jq でこのキーだけ書き換える
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
if ! command -v jq &> /dev/null; then
  echo "==> WARN: jq not found, skipping settings.json merge. Install jq and re-run, or add the WorktreeCreate hook manually." >&2
else
  if [ ! -f "$CLAUDE_SETTINGS" ]; then
    echo '{}' > "$CLAUDE_SETTINGS"
    echo "$CLAUDE_SETTINGS was created"
  fi
  CLAUDE_SETTINGS_TMP=$(mktemp)
  jq '.hooks.WorktreeCreate = [{"hooks":[{"type":"command","command":"$HOME/.claude/hooks/worktree-create.sh"}]}]' \
    "$CLAUDE_SETTINGS" > "$CLAUDE_SETTINGS_TMP" \
    && mv "$CLAUDE_SETTINGS_TMP" "$CLAUDE_SETTINGS" \
    && echo "==> Merged WorktreeCreate hook into $CLAUDE_SETTINGS"
fi

if [ ! -d ~/.config/zed ]; then
  mkdir -p ~/.config/zed
  echo '~/.config/zed was created'
fi

ln -sfv $ROOT/config/zed/settings.json $HOME/.config/zed/settings.json

if [ "$(uname)" == "Darwin" ]; then
  if [ ! -d ~/.config/karabiner/assets/complex_modifications ]; then
    mkdir -p ~/.config/karabiner/assets/complex_modifications
    echo '~/.config/karabiner/assets/complex_modifications was created'
  fi

  ln -sfv $ROOT/config/karabiner/assets/complex_modifications/ghostty-ime-off-on-ctrl-t.json $HOME/.config/karabiner/assets/complex_modifications/ghostty-ime-off-on-ctrl-t.json
fi

# ================================================
# ツールのインストール
# ================================================
if ! command -v mise &> /dev/null; then
  curl https://mise.run | sh
fi

# tmux plugin manager
if [ ! -d ~/.tmux/plugins/tpm ]; then
  git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
fi

# 言語・ツールのインストール (config/mise/config.toml に定義済み)
mise install -y

# 旧 wt (自前 Go 製) は git-wt へ移行済み。残存バイナリがあれば削除する
rm -f $HOME/.local/bin/wt

# gitの設定
git config --global user.name "Ryo Sakaguchi"
git config --global user.email "rsakaguchi3125@gmail.com"
git config --global ghq.root $HOME/src

# git-wt (git worktree ヘルパー) のグローバル設定
# worktree 配置を <repo親>/worktree/<repo名>/<branch> に揃え、tmux 連携 hook を登録する。
# いずれも set (--add ではない) なので bootstrap 再実行でも重複しない。
git config --global wt.basedir "../worktree/{gitroot}"
git config --global wt.nocd create
git config --global wt.hook "$HOME/.local/bin/git-wt-tmux-hook.sh add"
git config --global wt.deletehook "$HOME/.local/bin/git-wt-tmux-hook.sh delete"
# マージ済み/gone ブランチの掃除 (旧 wt clean の代替): gh poi + worktree prune
git config --global alias.wtclean "!gh poi && git worktree prune"
