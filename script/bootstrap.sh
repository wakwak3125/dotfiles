#! /bin/bash

cd `dirname $0`
ROOT=`dirname $(pwd)`
CONFIG_DIR='~/.config'

ln -sfv $ROOT/vimrc $HOME/.vimrc
ln -sfv $ROOT/ideavimrc $HOME/.ideavimrc
ln -sfv $ROOT/obsidian.vimrc $HOME/.obsidian.vimrc
ln -sfv $ROOT/zsh $HOME/.zsh
ln -sfv $ROOT/zshenv $HOME/.zshenv
ln -sfv $ROOT/nvim $CONFIG_DIR/nvim

if [ ! -d ~/.config/tmux ]; then
  mkdir -p ~/.config/tmux
  echo '~/.config/tmux was created'
fi

ln -sfv $ROOT/config/tmux/tmux.conf $HOME/.tmux.conf

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
  # TODO: Homebrewのインストールも行う
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
  curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz
  sudo rm -rf /opt/nvim-linux-x86_64
  sudo tar -C /opt -xzf nvim-linux-x86_64.tar.gz
  echo 'export PATH=/opt/nvim-linux-x86_64/bin:$PATH' >> ~/.zsh/.zshrc_local

  # NeovimをVimのデフォルトに設定
  NVIM_PATH="/opt/nvim-linux-x86_64/bin/nvim"
  sudo update-alternatives --install /usr/bin/vim vim $NVIM_PATH 100
  sudo update-alternatives --install /usr/bin/vi vi $NVIM_PATH 100
  sudo update-alternatives --set vim $NVIM_PATH
  sudo update-alternatives --set vi $NVIM_PATH
fi

# 言語のインストール
mise use -g rust
mise use -g go

# ツールのインストール
mise use ghq

# gitの設定
git config --global user.name "Ryo Sakaguchi"
git config --global user.email "rsakaguchi3125@gmail.com"
git config --global ghq.root $HOME/src
git config --global core.editor "nvim"
