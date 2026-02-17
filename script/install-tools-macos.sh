#!/bin/bash
set -e

echo "==> macOS tool installer"

# Homebrew
if ! command -v brew &>/dev/null; then
  echo "==> Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv)"
else
  echo "==> Homebrew already installed"
fi

# Homebrew packages
echo "==> Installing Homebrew packages..."
brew install \
  tmux \
  fzf \
  ripgrep \
  direnv \
  sheldon \
  jq

# macism (IME switcher for Neovim)
echo "==> Installing macism..."
brew tap laishulu/homebrew 2>/dev/null || true
brew install macism 2>/dev/null || echo "macism already installed"

# tmux plugin manager
if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
  echo "==> Installing tmux plugin manager (tpm)..."
  git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
else
  echo "==> tpm already installed"
fi

# mise
if ! command -v mise &>/dev/null && [ ! -f "$HOME/.local/bin/mise" ]; then
  echo "==> Installing mise..."
  curl https://mise.run | sh
else
  echo "==> mise already installed"
fi

# mise で管理する言語・ツール (config/mise/config.toml に定義済み)
echo "==> Installing languages and tools via mise..."
export PATH="$HOME/.local/bin:$PATH"
mise install -y

echo ""
echo "==> Done! All macOS tools installed."
echo "    Next: run ./bootstrap.sh to create symlinks."
