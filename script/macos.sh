#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ensure_dir() {
  local dir="$1"
  if [[ ! -d "$dir" ]]; then
    mkdir -p "$dir"
    echo "$dir was created"
  fi
}

link_file() {
  local src="$1"
  local dest="$2"
  if [[ ! -e "$src" ]]; then
    echo "==> WARN: $src not found, skipping $dest" >&2
    return 0
  fi
  ensure_dir "$(dirname "$dest")"
  ln -sfv "$src" "$dest"
}

echo "==> macOS setup"

# Homebrew
if ! command -v brew &>/dev/null; then
  echo "==> Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
else
  echo "==> Homebrew already installed"
fi

echo "==> Installing Homebrew packages..."
brew install \
  tmux \
  fzf \
  ripgrep \
  direnv \
  sheldon \
  jq \
  secretive

# macism (IME switcher for Neovim)
echo "==> Installing macism..."
brew tap laishulu/homebrew 2>/dev/null || true
brew install macism 2>/dev/null || echo "macism already installed"

# tmux plugin manager
if [[ ! -d "$HOME/.tmux/plugins/tpm" ]]; then
  echo "==> Installing tmux plugin manager (tpm)..."
  git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
else
  echo "==> tpm already installed"
fi

# macOS GUI app configs
link_file "$ROOT/config/zed/settings.json" "$HOME/.config/zed/settings.json"
link_file "$ROOT/config/ghostty/config" "$HOME/.config/ghostty/config"
link_file "$ROOT/config/karabiner/assets/complex_modifications/ghostty-ime-off-on-ctrl-t.json" \
  "$HOME/.config/karabiner/assets/complex_modifications/ghostty-ime-off-on-ctrl-t.json"

echo "==> macOS setup done"
