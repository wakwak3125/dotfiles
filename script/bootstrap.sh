#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OS="$(uname -s)"

is_wsl() {
  [[ -n "${WSL_DISTRO_NAME:-}" || -n "${WSL_INTEROP:-}" ]] && return 0
  [[ -r /proc/sys/kernel/osrelease ]] && grep -qiE 'microsoft|wsl' /proc/sys/kernel/osrelease
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

link_dir() {
  local src="$1"
  local dest="$2"
  if [[ ! -d "$src" ]]; then
    echo "==> WARN: $src not found, skipping $dest" >&2
    return 0
  fi
  ensure_dir "$(dirname "$dest")"
  ln -sfnv "$src" "$dest"
}

run_platform_setup() {
  case "$OS" in
    Darwin)
      bash "$ROOT/script/macos.sh"
      ;;
    Linux)
      if is_wsl; then
        bash "$ROOT/script/wsl.sh"
      else
        echo "==> Linux detected outside WSL; applying WSL-compatible Linux setup"
        bash "$ROOT/script/wsl.sh"
      fi
      ;;
    *)
      echo "==> WARN: unsupported OS: $OS. Running common setup only." >&2
      ;;
  esac
}

run_platform_setup

# ================================================
# 共通 symlink
# ================================================
link_file "$ROOT/ideavimrc" "$HOME/.ideavimrc"
link_file "$ROOT/obsidian.vimrc" "$HOME/.obsidian.vimrc"
link_dir "$ROOT/zsh" "$HOME/.zsh"
link_file "$ROOT/zshenv" "$HOME/.zshenv"
link_dir "$ROOT/nvim" "$HOME/.config/nvim"

link_file "$ROOT/config/tmux/tmux.conf" "$HOME/.config/tmux/tmux.conf"
link_file "$ROOT/config/herdr/config.toml" "$HOME/.config/herdr/config.toml"
link_file "$ROOT/config/sheldon/plugins.toml" "$HOME/.config/sheldon/plugins.toml"
link_file "$ROOT/config/mise/config.toml" "$HOME/.config/mise/config.toml"
link_file "$ROOT/config/starship.toml" "$HOME/.config/starship.toml"
link_file "$ROOT/config/git/ignore" "$HOME/.config/git/ignore"

# Linux/WSL 用 pbcopy/pbpaste polyfill。macOS の /usr/bin/pbcopy は上書きしない。
if [[ "$OS" != "Darwin" ]]; then
  ensure_dir "$HOME/.local/bin"
  link_file "$ROOT/pbcopy" "$HOME/.local/bin/pbcopy"
  link_file "$ROOT/pbpaste" "$HOME/.local/bin/pbpaste"
fi

# スクリプトをパスに追加
ensure_dir "$HOME/.local/bin"
link_file "$ROOT/script/claude-status" "$HOME/.local/bin/claude-status"
link_file "$ROOT/script/git-wt-tmux-hook.sh" "$HOME/.local/bin/git-wt-tmux-hook.sh"
link_file "$ROOT/script/git-wt-herdr-hook.sh" "$HOME/.local/bin/git-wt-herdr-hook.sh"

# 廃止した tmux switcher 系の残存 symlink を掃除 (herdr 移行で全廃)
rm -f "$HOME/.local/bin/tmux-switcher" \
      "$HOME/.local/bin/tmux-git-switch" \
      "$HOME/.local/bin/tmux-repo-switch" \
      "$HOME/.local/bin/tmux-worktree-switch" \
      "$HOME/.local/bin/tmux-file-select" \
      "$HOME/.local/bin/tmux-toggle-pane"

# ================================================
# Claude Code 個人設定
# ================================================
ensure_dir "$HOME/.claude"

# `-n` を付けないと既存の symlink を辿って中にリンクを作ってしまう
if [[ ! -L "$HOME/.claude/skills" ]]; then
  rm -rf "$HOME/.claude/skills"
fi
link_dir "$ROOT/claude/skills" "$HOME/.claude/skills"

if [[ ! -L "$HOME/.claude/agents" ]]; then
  rm -rf "$HOME/.claude/agents"
fi
link_dir "$ROOT/claude/agents" "$HOME/.claude/agents"

# Claude Code フックスクリプト (ディレクトリは symlink にしない: nono など外部ツールが配置するファイルと共存させる)
ensure_dir "$HOME/.claude/hooks"
link_file "$ROOT/claude/hooks/worktree-create.sh" "$HOME/.claude/hooks/worktree-create.sh"

# Claude Code org 単位の CLAUDE.md (claude/orgs/<org>.CLAUDE.md -> ~/src/github.com/<org>/CLAUDE.md)
# claude/orgs/ は gitignore 対象 (会社固有情報を含むため)。ファイルがあるマシンでのみ symlink を張る
if [[ -d "$ROOT/claude/orgs" ]]; then
  for org_md in "$ROOT"/claude/orgs/*.CLAUDE.md; do
    [[ -f "$org_md" ]] || continue
    org="$(basename "$org_md" .CLAUDE.md)"
    if [[ -d "$HOME/src/github.com/$org" ]]; then
      link_file "$org_md" "$HOME/src/github.com/$org/CLAUDE.md"
    fi
  done
fi

# Claude Code settings.json に WorktreeCreate フック設定をマージ
# settings.json は API キー等の機密混在のため symlink せず、jq でこのキーだけ書き換える
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
if ! command -v jq &>/dev/null; then
  echo "==> WARN: jq not found, skipping settings.json merge. Install jq and re-run, or add the WorktreeCreate hook manually." >&2
else
  if [[ ! -f "$CLAUDE_SETTINGS" ]]; then
    echo '{}' > "$CLAUDE_SETTINGS"
    echo "$CLAUDE_SETTINGS was created"
  fi
  CLAUDE_SETTINGS_TMP="$(mktemp)"
  jq '.hooks.WorktreeCreate = [{"hooks":[{"type":"command","command":"$HOME/.claude/hooks/worktree-create.sh"}]}]' \
    "$CLAUDE_SETTINGS" > "$CLAUDE_SETTINGS_TMP" \
    && mv "$CLAUDE_SETTINGS_TMP" "$CLAUDE_SETTINGS" \
    && echo "==> Merged WorktreeCreate hook into $CLAUDE_SETTINGS"
fi

# ================================================
# ツールのインストール
# ================================================
bash "$ROOT/script/install-neovim.sh"

if ! command -v mise &>/dev/null && [[ ! -x "$HOME/.local/bin/mise" ]]; then
  curl https://mise.run | sh
fi

MISE_BIN="$(command -v mise || true)"
if [[ -z "$MISE_BIN" && -x "$HOME/.local/bin/mise" ]]; then
  MISE_BIN="$HOME/.local/bin/mise"
fi

if [[ -n "$MISE_BIN" ]]; then
  "$MISE_BIN" install -y
else
  echo "==> WARN: mise not found, skipping mise install" >&2
fi

# 旧 wt (自前 Go 製) は git-wt へ移行済み。残存バイナリがあれば削除する
rm -f "$HOME/.local/bin/wt"

# gitの設定
git config --global user.name "Ryo Sakaguchi"
git config --global user.email "rsakaguchi3125@gmail.com"
git config --global ghq.root "$HOME/src"

# git-wt (git worktree ヘルパー) のグローバル設定
# worktree 配置を <repo親>/worktree/<repo名> に揃え、herdr 連携 hook を登録する。
# (herdr hook は herdr 外だと tmux hook へ委譲するので併存期間も両対応)
# いずれも set (--add ではない) なので bootstrap 再実行でも重複しない。
git config --global wt.basedir "../worktree/{gitroot}"
git config --global wt.nocd create
git config --global wt.hook "$HOME/.local/bin/git-wt-herdr-hook.sh add"
git config --global wt.deletehook "$HOME/.local/bin/git-wt-herdr-hook.sh delete"
# マージ済み/gone ブランチの掃除 (旧 wt clean の代替): gh poi + worktree prune
git config --global alias.wtclean "!gh poi && git worktree prune"
