#! /bin/bash

# Neovimのインストールスクリプト
# Usage: ./install-neovim.sh
# Supports: macOS (x86_64, arm64) and Linux (x86_64)

set -e

echo "Installing Neovim..."

# OSとアーキテクチャを検出
OS=$(uname)
ARCH=$(uname -m)

if [ "$OS" == "Darwin" ]; then
  # macOSの場合
  if [ "$ARCH" == "arm64" ]; then
    NVIM_PACKAGE="nvim-macos-arm64.tar.gz"
    NVIM_DIR="nvim-macos-arm64"
  else
    NVIM_PACKAGE="nvim-macos-x86_64.tar.gz"
    NVIM_DIR="nvim-macos-x86_64"
  fi
else
  # Linuxの場合
  NVIM_PACKAGE="nvim-linux-x86_64.tar.gz"
  NVIM_DIR="nvim-linux-x86_64"
fi

# Neovimのダウンロードとインストール
curl -LO https://github.com/neovim/neovim/releases/latest/download/$NVIM_PACKAGE
sudo rm -rf /opt/$NVIM_DIR
sudo tar -C /opt -xzf $NVIM_PACKAGE
rm $NVIM_PACKAGE

# PATHの設定
if [ ! -f ~/.zsh/.zshrc_local ]; then
  mkdir -p ~/.zsh
  touch ~/.zsh/.zshrc_local
fi

NVIM_BIN_PATH="/opt/$NVIM_DIR/bin"
if ! grep -q "export PATH=$NVIM_BIN_PATH:\$PATH" ~/.zsh/.zshrc_local; then
  echo "export PATH=$NVIM_BIN_PATH:\$PATH" >> ~/.zsh/.zshrc_local
fi

# NeovimをVimのデフォルトに設定
NVIM_PATH="$NVIM_BIN_PATH/nvim"

if [ "$OS" == "Darwin" ]; then
  # macOSの場合はシンボリックリンクを作成
  sudo ln -sf $NVIM_PATH /usr/local/bin/vim
  sudo ln -sf $NVIM_PATH /usr/local/bin/vi
  sudo ln -sf $NVIM_PATH /usr/local/bin/nvim
else
  # Linuxの場合はupdate-alternativesを使用
  sudo update-alternatives --install /usr/bin/vim vim $NVIM_PATH 100
  sudo update-alternatives --install /usr/bin/vi vi $NVIM_PATH 100
  sudo update-alternatives --set vim $NVIM_PATH
  sudo update-alternatives --set vi $NVIM_PATH
fi

git config --global core.editor "nvim"

echo "Neovim installation completed successfully!"
echo "Installed at: $NVIM_PATH"
echo "Please restart your shell or run: source ~/.zshenv"
