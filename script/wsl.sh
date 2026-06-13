#!/usr/bin/env bash

set -euo pipefail

is_wsl() {
  [[ -n "${WSL_DISTRO_NAME:-}" || -n "${WSL_INTEROP:-}" ]] && return 0
  [[ -r /proc/sys/kernel/osrelease ]] && grep -qiE 'microsoft|wsl' /proc/sys/kernel/osrelease
}

echo "==> WSL/Linux setup"

if command -v apt-get &>/dev/null; then
  base_packages=(
    build-essential
    ca-certificates
    curl
    direnv
    fzf
    git
    jq
    libssl-dev
    openssl
    pkg-config
    ripgrep
    tmux
    unzip
    xdg-utils
    zsh
  )

  packages=("${base_packages[@]}")
  if is_wsl; then
    packages+=(wslu)
  fi

  echo "==> Installing apt packages (sudo required)..."
  sudo apt-get update
  if ! sudo apt-get install -y "${packages[@]}"; then
    if is_wsl; then
      echo "==> WARN: apt install failed with WSL extras; retrying without wslu" >&2
      sudo apt-get install -y "${base_packages[@]}"
    else
      exit 1
    fi
  fi
else
  echo "==> WARN: apt-get not found, skipping system package install" >&2
fi

if is_wsl; then
  if ! command -v clip.exe &>/dev/null; then
    echo "==> WARN: clip.exe not found. Windows clipboard integration may be unavailable." >&2
  fi
  if ! command -v wslview &>/dev/null; then
    echo "==> WARN: wslview not found. Install wslu if browser/file opening from WSL is needed." >&2
  fi
fi

if command -v zsh &>/dev/null && [[ "$(basename "${SHELL:-}")" != "zsh" ]]; then
  echo "==> zsh is installed. To make it your login shell, run: chsh -s $(command -v zsh)"
fi

echo "==> WSL/Linux setup done"
