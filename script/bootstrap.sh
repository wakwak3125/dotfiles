#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OS="$(uname -s)"

BOOTSTRAP_SUCCEEDED=()
BOOTSTRAP_FAILED=()
BOOTSTRAP_CURRENT_STEP=""
BOOTSTRAP_FAILURE_RECORDED=0

record_failure() {
  local status="$1"
  local label="${BOOTSTRAP_CURRENT_STEP:-$BASH_COMMAND}"

  if [[ "$BOOTSTRAP_FAILURE_RECORDED" -eq 0 ]]; then
    BOOTSTRAP_FAILED+=("$label (exit $status)")
    BOOTSTRAP_FAILURE_RECORDED=1
  fi
}

print_summary() {
  local status=$?
  trap - EXIT

  echo
  echo "==> Bootstrap summary"

  if ((${#BOOTSTRAP_SUCCEEDED[@]} > 0)); then
    echo "Succeeded:"
    printf '  - %s\n' "${BOOTSTRAP_SUCCEEDED[@]}"
  else
    echo "Succeeded: none"
  fi

  if ((${#BOOTSTRAP_FAILED[@]} > 0)); then
    echo "Failed:"
    printf '  - %s\n' "${BOOTSTRAP_FAILED[@]}"
  else
    echo "Failed: none"
  fi

  exit "$status"
}

trap 'record_failure "$?"' ERR
trap print_summary EXIT

run_step() {
  local label="$1"
  shift

  BOOTSTRAP_CURRENT_STEP="$label"
  echo "==> $label"
  "$@"
  BOOTSTRAP_SUCCEEDED+=("$label")
  BOOTSTRAP_CURRENT_STEP=""
}

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

link_common_config() {
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
  link_file "$ROOT/config/ccstatusline/settings.json" "$HOME/.config/ccstatusline/settings.json"
  link_file "$ROOT/config/git/ignore" "$HOME/.config/git/ignore"
}

link_linux_clipboard_tools() {
  [[ "$OS" != "Darwin" ]] || return 0

  ensure_dir "$HOME/.local/bin"
  link_file "$ROOT/pbcopy" "$HOME/.local/bin/pbcopy"
  link_file "$ROOT/pbpaste" "$HOME/.local/bin/pbpaste"
}

link_local_scripts() {
  ensure_dir "$HOME/.local/bin"
  link_file "$ROOT/script/claude-status" "$HOME/.local/bin/claude-status"
  link_file "$ROOT/script/git-wt-tmux-hook.sh" "$HOME/.local/bin/git-wt-tmux-hook.sh"
  link_file "$ROOT/script/git-wt-herdr-hook.sh" "$HOME/.local/bin/git-wt-herdr-hook.sh"
}

cleanup_removed_tmux_switchers() {
  rm -f "$HOME/.local/bin/tmux-switcher" \
        "$HOME/.local/bin/tmux-git-switch" \
        "$HOME/.local/bin/tmux-repo-switch" \
        "$HOME/.local/bin/tmux-worktree-switch" \
        "$HOME/.local/bin/tmux-file-select" \
        "$HOME/.local/bin/tmux-toggle-pane"
}

link_claude_config() {
  ensure_dir "$HOME/.claude"

  if [[ ! -L "$HOME/.claude/agents" ]]; then
    rm -rf "$HOME/.claude/agents"
  fi
  link_dir "$ROOT/claude/agents" "$HOME/.claude/agents"

  # Claude Code フックスクリプト (ディレクトリは symlink にしない: nono など外部ツールが配置するファイルと共存させる)
  ensure_dir "$HOME/.claude/hooks"
  link_file "$ROOT/claude/hooks/worktree-create.sh" "$HOME/.claude/hooks/worktree-create.sh"
}

link_claude_org_docs() {
  # Org 単位の agent docs (claude/orgs/<org>.AGENTS.md -> ~/src/github.com/<org>/AGENTS.md)
  # Claude Code 互換の参照 stub は <org>.CLAUDE.md -> ~/src/github.com/<org>/CLAUDE.md として置く。
  # claude/orgs/ は gitignore 対象 (会社固有情報を含むため)。ファイルがあるマシンでのみ symlink を張る
  if [[ -d "$ROOT/claude/orgs" ]]; then
    local org_md org

    for org_md in "$ROOT"/claude/orgs/*.AGENTS.md; do
      [[ -f "$org_md" ]] || continue
      org="$(basename "$org_md" .AGENTS.md)"
      if [[ -d "$HOME/src/github.com/$org" ]]; then
        link_file "$org_md" "$HOME/src/github.com/$org/AGENTS.md"
      fi
    done

    for org_md in "$ROOT"/claude/orgs/*.CLAUDE.md; do
      [[ -f "$org_md" ]] || continue
      org="$(basename "$org_md" .CLAUDE.md)"
      if [[ -d "$HOME/src/github.com/$org" ]]; then
        link_file "$org_md" "$HOME/src/github.com/$org/CLAUDE.md"
      fi
    done
  fi
}

merge_claude_settings() {
  local claude_settings="$HOME/.claude/settings.json"
  local claude_settings_tmp

  # Claude Code settings.json に WorktreeCreate フック設定をマージ
  # settings.json は API キー等の機密混在のため symlink せず、jq でこのキーだけ書き換える
  if ! command -v jq &>/dev/null; then
    echo "==> WARN: jq not found, skipping settings.json merge. Install jq and re-run, or add the WorktreeCreate hook manually." >&2
    return 0
  fi

  if [[ ! -f "$claude_settings" ]]; then
    echo '{}' > "$claude_settings"
    echo "$claude_settings was created"
  fi
  claude_settings_tmp="$(mktemp)"
  # WorktreeCreate フックと ccstatusline (mise shim 経由) のステータスラインをマージ
  jq '.hooks.WorktreeCreate = [{"hooks":[{"type":"command","command":"$HOME/.claude/hooks/worktree-create.sh"}]}]
      | .statusLine = {"type":"command","command":"$HOME/.local/share/mise/shims/ccstatusline","padding":0}' \
    "$claude_settings" > "$claude_settings_tmp"
  mv "$claude_settings_tmp" "$claude_settings"
  echo "==> Merged WorktreeCreate hook and ccstatusline statusLine into $claude_settings"
}

install_agent_skills() {
  bash "$ROOT/script/install-agent-skills.sh"
}

install_mise() {
  if ! command -v mise &>/dev/null && [[ ! -x "$HOME/.local/bin/mise" ]]; then
    curl https://mise.run | sh
  fi
}

run_mise_install() {
  local mise_bin

  mise_bin="$(command -v mise || true)"
  if [[ -z "$mise_bin" && -x "$HOME/.local/bin/mise" ]]; then
    mise_bin="$HOME/.local/bin/mise"
  fi

  if [[ -n "$mise_bin" ]]; then
    "$mise_bin" install -y
  else
    echo "==> WARN: mise not found, skipping mise install" >&2
  fi
}

cleanup_legacy_wt() {
  rm -f "$HOME/.local/bin/wt"
}

configure_git() {
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
}

run_step "Platform setup" run_platform_setup

# ================================================
# 共通 symlink
# ================================================
run_step "Common config symlinks" link_common_config

# Linux/WSL 用 pbcopy/pbpaste polyfill。macOS の /usr/bin/pbcopy は上書きしない。
run_step "Linux clipboard tools" link_linux_clipboard_tools

# スクリプトをパスに追加
run_step "Local script symlinks" link_local_scripts

# 廃止した tmux switcher 系の残存 symlink を掃除 (herdr 移行で全廃)
run_step "Removed tmux switcher cleanup" cleanup_removed_tmux_switchers

# ================================================
# Claude Code 個人設定
# ================================================
run_step "Claude runtime config symlinks" link_claude_config
run_step "Claude org docs symlinks" link_claude_org_docs
run_step "Claude settings merge" merge_claude_settings
run_step "Agent skill install" install_agent_skills

# ================================================
# ツールのインストール
# ================================================
run_step "Neovim install" bash "$ROOT/script/install-neovim.sh"
run_step "mise install bootstrap" install_mise
run_step "mise tool install" run_mise_install

# 旧 wt (自前 Go 製) は git-wt へ移行済み。残存バイナリがあれば削除する
run_step "Legacy wt cleanup" cleanup_legacy_wt

run_step "Git config" configure_git
