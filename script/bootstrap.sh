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
ln -sfv $ROOT/zsh $HOME/.zsh
ln -sfv $ROOT/zshenv $HOME/.zshenv
ln -sfv $ROOT/nvim $HOME/.config/nvim

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
ln -sfv $ROOT/script/tmux-file-select $HOME/.local/bin/tmux-file-select

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

# gitの設定
git config --global user.name "Ryo Sakaguchi"
git config --global user.email "rsakaguchi3125@gmail.com"
git config --global ghq.root $HOME/src
