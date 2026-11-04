#!/usr/bin/env bash
# ~/.claude/agents に dotfiles と agent-private の subagent 定義を張る。

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AGENT_PRIVATE_DIR="${AGENT_PRIVATE_DIR:-$HOME/src/github.com/wakwak3125/agent-private}"
DEST="$HOME/.claude/agents"

link_agents() {
  local src
  for src in "$1"/*.md; do
    [[ -e "$src" ]] || continue
    ln -sfv "$src" "$DEST/$(basename "$src")"
  done
}

# ディレクトリごとの symlink にしない。会社固有の定義は公開の dotfiles に置けず、agent-private のファイルと並べる必要があるため
if [[ -L "$DEST" ]]; then
  rm "$DEST"
fi
mkdir -p "$DEST"

link_agents "$ROOT/agents/agents"

# org 指示と同じく、その org のリポジトリを clone しているマシンでだけ張る
if [[ -d "$AGENT_PRIVATE_DIR/org" ]]; then
  for org_dir in "$AGENT_PRIVATE_DIR"/org/*/; do
    org="$(basename "$org_dir")"
    if [[ -d "$HOME/src/github.com/$org" && -d "${org_dir}agents" ]]; then
      link_agents "${org_dir}agents"
    fi
  done
fi

# 壊れたリンクだけを消す。手で置いた実ファイルの subagent まで消さないため
for link in "$DEST"/*.md; do
  if [[ -L "$link" && ! -e "$link" ]]; then
    rm -v "$link"
  fi
done
