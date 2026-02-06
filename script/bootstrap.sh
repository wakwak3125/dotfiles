#! /bin/bash

cd `dirname $0`
ROOT=`dirname $(pwd)`
CONFIG_DIR='~/.config'

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

# claude-status コマンドをパスに追加
mkdir -p $HOME/.local/bin
ln -sfv $ROOT/script/claude-status $HOME/.local/bin/claude-status
ln -sfv $ROOT/script/tmux-switcher $HOME/.local/bin/tmux-switcher

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

# 必要なパッケージをインストールする

if ! command -v mise &> /dev/null; then
  curl https://mise.run | sh
fi

# LinuxかmacOSかを分岐してパッケージをインストールする
if [ "$(uname)" == "Darwin" ]; then
  # macOSの場合
  $ROOT/script/install-neovim.sh
else
  # Linuxの場合
  sudo apt update
  sudo apt install -y \
    build-essential \
    openssl \
    libssl-dev \
    pkg-config \
    fzf \
    ripgrep
  # Neovimのインストール
  $ROOT/script/install-neovim.sh
fi

# 言語のインストール
mise use -g rust
mise use -g go
mise use -g node

# ツールのインストール
mise use ghq

# gitの設定
git config --global user.name "Ryo Sakaguchi"
git config --global user.email "rsakaguchi3125@gmail.com"
git config --global ghq.root $HOME/src
