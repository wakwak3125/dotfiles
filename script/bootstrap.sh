#!/bin/bash
set -e

cd "$(dirname "$0")"
ROOT="$(dirname "$(pwd)")"

# OS判定関数
is_macos() { [[ "$(uname -s)" == "Darwin" ]]; }
is_linux() { [[ "$(uname -s)" == "Linux" ]]; }
is_wsl()   { [[ -n "$WSL_DISTRO_NAME" ]] || grep -qi microsoft /proc/version 2>/dev/null; }

# 冪等なシンボリックリンク作成関数
link_file() {
  local src="$1" dst="$2"
  local dst_dir
  dst_dir="$(dirname "$dst")"
  if [[ ! -d "$dst_dir" ]]; then
    mkdir -p "$dst_dir"
    echo "Created directory: $dst_dir"
  fi
  ln -sfv "$src" "$dst"
}

echo "==> Creating symlinks..."

# 共通シンボリックリンク
link_file "$ROOT/ideavimrc" "$HOME/.ideavimrc"
link_file "$ROOT/obsidian.vimrc" "$HOME/.obsidian.vimrc"
link_file "$ROOT/zsh" "$HOME/.zsh"
link_file "$ROOT/zshenv" "$HOME/.zshenv"
link_file "$ROOT/nvim" "$HOME/.config/nvim"
link_file "$ROOT/config/tmux/tmux.conf" "$HOME/.config/tmux/tmux.conf"
link_file "$ROOT/config/sheldon/plugins.toml" "$HOME/.config/sheldon/plugins.toml"
link_file "$ROOT/config/mise/config.toml" "$HOME/.config/mise/config.toml"
link_file "$ROOT/config/starship.toml" "$HOME/.config/starship.toml"
link_file "$ROOT/config/git/ignore" "$HOME/.config/git/ignore"
link_file "$ROOT/gitconfig" "$HOME/.config/git/config"

# ユーティリティスクリプト
mkdir -p "$HOME/.local/bin"
link_file "$ROOT/script/claude-status" "$HOME/.local/bin/claude-status"
link_file "$ROOT/script/tmux-switcher" "$HOME/.local/bin/tmux-switcher"

# macOS専用シンボリックリンク
if is_macos; then
  link_file "$ROOT/config/karabiner/assets/complex_modifications/ghostty-ime-off-on-ctrl-t.json" \
    "$HOME/.config/karabiner/assets/complex_modifications/ghostty-ime-off-on-ctrl-t.json"
fi

# Linux/WSL2専用シンボリックリンク
if is_linux; then
  link_file "$ROOT/config/terminator/config" "$HOME/.config/terminator/config"
  link_file "$ROOT/keymap/Xmodmap" "$HOME/.Xmodmap"
fi

echo ""
echo "==> Installing packages..."

# miseのインストール
if ! command -v mise &> /dev/null && [[ ! -f "$HOME/.local/bin/mise" ]]; then
  curl https://mise.run | sh
fi

# OS別パッケージインストール
if is_macos; then
  "$ROOT/script/install-tools-macos.sh"
else
  # Linux共通パッケージ
  sudo apt update
  sudo apt install -y \
    build-essential \
    openssl \
    libssl-dev \
    pkg-config \
    fzf \
    ripgrep \
    tmux \
    direnv \
    jq

  # sheldon (Linuxではcargoでインストール)
  if ! command -v sheldon &> /dev/null; then
    if command -v cargo &> /dev/null; then
      cargo install sheldon
    else
      echo "Warning: cargo not found. Install Rust first to get sheldon."
    fi
  fi

  # tpm (tmux plugin manager)
  if [[ ! -d "$HOME/.tmux/plugins/tpm" ]]; then
    git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
  fi

  # delta
  if ! command -v delta &> /dev/null; then
    echo "Note: Install git-delta manually: https://dandavison.github.io/delta/installation.html"
  fi

  # WSL2固有のセットアップ
  if is_wsl; then
    sudo apt install -y wslu
  fi

  # Neovimのインストール
  "$ROOT/script/install-neovim.sh"
fi

# 言語・ツールのインストール (config/mise/config.toml に定義済み)
export PATH="$HOME/.local/bin:$PATH"
mise install -y

# gitの設定 (gitconfigでカバーされない設定)
git config --global ghq.root "$HOME/src"

echo ""
echo "==> Bootstrap complete!"
echo "    Please restart your shell or run: source ~/.zshenv"
