#! /bin/bash

# Neovimのインストールスクリプト（冪等）
# Usage: ./install-neovim.sh
# Supports: macOS (x86_64, arm64) and Linux (x86_64)

set -e

# OSとアーキテクチャを検出
OS=$(uname)
ARCH=$(uname -m)

if [ "$OS" == "Darwin" ]; then
  if [ "$ARCH" == "arm64" ]; then
    NVIM_PACKAGE="nvim-macos-arm64.tar.gz"
    NVIM_DIR="nvim-macos-arm64"
  else
    NVIM_PACKAGE="nvim-macos-x86_64.tar.gz"
    NVIM_DIR="nvim-macos-x86_64"
  fi
else
  NVIM_PACKAGE="nvim-linux-x86_64.tar.gz"
  NVIM_DIR="nvim-linux-x86_64"
fi

NVIM_BIN_PATH="/opt/$NVIM_DIR/bin"
NVIM_PATH="$NVIM_BIN_PATH/nvim"

# 既存インストール済みバージョンと latest tag を比較し、一致すれば curl/展開を skip
LATEST_TAG=$(curl -sIL https://github.com/neovim/neovim/releases/latest \
  | awk 'BEGIN{IGNORECASE=1} /^location:/ {print $2}' \
  | tail -1 \
  | awk -F'/' '{print $NF}' \
  | tr -d '\r\n')

INSTALLED_TAG=""
if [ -x "$NVIM_PATH" ]; then
  INSTALLED_TAG=$("$NVIM_PATH" --version | head -1 | awk '{print $2}')
fi

if [ -n "$LATEST_TAG" ] && [ "$LATEST_TAG" = "$INSTALLED_TAG" ]; then
  echo "Neovim $INSTALLED_TAG is already up to date at $NVIM_PATH"
else
  echo "Installing Neovim ($INSTALLED_TAG -> ${LATEST_TAG:-latest})..."
  # 途中で失敗してもダウンロード済みアーカイブを残さない
  trap 'rm -f "$NVIM_PACKAGE"' EXIT
  curl -LO https://github.com/neovim/neovim/releases/latest/download/$NVIM_PACKAGE
  sudo rm -rf /opt/$NVIM_DIR
  sudo tar -C /opt -xzf $NVIM_PACKAGE
  rm $NVIM_PACKAGE
  trap - EXIT
fi

# PATHの設定
if [ ! -f ~/.zsh/.zshrc_local ]; then
  mkdir -p ~/.zsh
  touch ~/.zsh/.zshrc_local
fi

if ! grep -q "export PATH=$NVIM_BIN_PATH:\$PATH" ~/.zsh/.zshrc_local; then
  echo "export PATH=$NVIM_BIN_PATH:\$PATH" >> ~/.zsh/.zshrc_local
fi

# NeovimをVimのデフォルトに設定
if [ "$OS" == "Darwin" ]; then
  # macOS では alias を .zshrc_local に追記（重複防止のため grep でガード）
  if ! grep -qF 'alias vim="nvim"' ~/.zsh/.zshrc_local; then
    echo 'alias vim="nvim"' >> ~/.zsh/.zshrc_local
  fi
  if ! grep -qF 'alias vi="nvim"' ~/.zsh/.zshrc_local; then
    echo 'alias vi="nvim"' >> ~/.zsh/.zshrc_local
  fi
else
  # Linux では update-alternatives（同一 priority/path での再登録は冪等）
  sudo update-alternatives --install /usr/bin/vim vim $NVIM_PATH 100
  sudo update-alternatives --install /usr/bin/vi vi $NVIM_PATH 100
  sudo update-alternatives --set vim $NVIM_PATH
  sudo update-alternatives --set vi $NVIM_PATH
fi

git config --global core.editor "nvim"

echo "Installed at: $NVIM_PATH"
