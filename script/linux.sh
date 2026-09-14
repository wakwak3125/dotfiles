#!/usr/bin/env bash

# Ubuntu (ネイティブ) / WSL2 共通の Linux セットアップ。
# macOS の script/macos.sh (Homebrew) に相当する処理を apt 等で行う。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

is_wsl() {
  [[ -n "${WSL_DISTRO_NAME:-}" || -n "${WSL_INTEROP:-}" ]] && return 0
  [[ -r /proc/sys/kernel/osrelease ]] && grep -qiE 'microsoft|wsl' /proc/sys/kernel/osrelease
}

# GUI セッションを持つマシンか (ssh 経由で bootstrap しても判定できるよう環境変数ではなく session 定義で見る)
has_desktop() {
  is_wsl && return 1
  [[ -d /usr/share/wayland-sessions || -d /usr/share/xsessions ]]
}

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

echo "==> Linux setup"

if command -v apt-get &>/dev/null; then
  # node/npm・gh 等は apt では入れない (mise 管理: config/mise/config.toml)。
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
    rsync
    tmux
    unzip
    xdg-utils
    zsh
  )

  packages=("${base_packages[@]}")
  if is_wsl; then
    packages+=(wslu)
  fi
  if has_desktop; then
    # Neovim (clipboard=unnamedplus) と pbcopy/pbpaste polyfill のクリップボード連携用
    packages+=(wl-clipboard xclip)
  fi

  echo "==> Installing apt packages (sudo required)..."
  sudo apt-get update
  if ! sudo apt-get install -y "${packages[@]}"; then
    if [[ "${#packages[@]}" -ne "${#base_packages[@]}" ]]; then
      echo "==> WARN: apt install failed with extras; retrying with base packages only" >&2
      sudo apt-get install -y "${base_packages[@]}"
    else
      exit 1
    fi
  fi
else
  echo "==> WARN: apt-get not found, skipping system package install" >&2
fi

# sheldon: .zshrc は mise activate より前に sheldon を読むため mise ではなく
# ~/.local/bin へ公式 installer で入れる (apt にパッケージが無い)
if ! command -v sheldon &>/dev/null && [[ ! -x "$HOME/.local/bin/sheldon" ]]; then
  echo "==> Installing sheldon..."
  ensure_dir "$HOME/.local/bin"
  curl --proto '=https' -fLsS https://rossmacarthur.github.io/install/crate.sh \
    | bash -s -- --repo rossmacarthur/sheldon --to "$HOME/.local/bin"
else
  echo "==> sheldon already installed"
fi

if has_desktop; then
  # macOS と共通で使える GUI アプリ設定 (アプリ本体は snap 等で別途導入)
  link_file "$ROOT/config/ghostty/config" "$HOME/.config/ghostty/config"
  link_file "$ROOT/config/zed/settings.json" "$HOME/.config/zed/settings.json"
  link_file "$ROOT/config/terminator/config" "$HOME/.config/terminator/config"
fi

# GNOME: 入力ソース (英語 <-> Mozc) の切り替えを Ctrl+Space にする (既定は Super+Space)
if ! is_wsl && command -v gsettings &>/dev/null \
  && gsettings list-keys org.gnome.desktop.wm.keybindings 2>/dev/null | grep -qx switch-input-source; then
  echo "==> Setting GNOME input source switch to Ctrl+Space"
  gsettings set org.gnome.desktop.wm.keybindings switch-input-source "['<Control>space', 'XF86Keyboard']"
  gsettings set org.gnome.desktop.wm.keybindings switch-input-source-backward "['<Shift><Control>space', '<Shift>XF86Keyboard']"
fi

# Mozc: 入力ソース切り替え直後から直接入力ではなくひらがな入力にする。
# ibus_config.textproto は Mozc が初回起動時に生成し他の項目も持つため、symlink せず該当行だけ書き換える
mozc_ibus_config="$HOME/.config/mozc/ibus_config.textproto"
if [[ -f "$mozc_ibus_config" ]] && grep -qx 'active_on_launch: False' "$mozc_ibus_config"; then
  echo "==> Setting Mozc active_on_launch to True"
  sed -i 's/^active_on_launch: False$/active_on_launch: True/' "$mozc_ibus_config"
  command -v ibus &>/dev/null && ibus write-cache && ibus restart
fi

if is_wsl; then
  if ! command -v clip.exe &>/dev/null; then
    echo "==> WARN: clip.exe not found. Windows clipboard integration may be unavailable." >&2
  fi
  if ! command -v wslview &>/dev/null; then
    echo "==> WARN: wslview not found. Install wslu if browser/file opening from WSL is needed." >&2
  fi
fi

# ログインシェルを zsh にする (macOS は既定で zsh)
zsh_bin="$(command -v zsh || true)"
if [[ -n "$zsh_bin" ]] && [[ "$(getent passwd "$USER" | cut -d: -f7)" != "$zsh_bin" ]]; then
  echo "==> Changing login shell to $zsh_bin (sudo required)..."
  if ! sudo chsh -s "$zsh_bin" "$USER"; then
    echo "==> WARN: failed to change login shell. Run manually: chsh -s $zsh_bin" >&2
  fi
fi

echo "==> Linux setup done"
