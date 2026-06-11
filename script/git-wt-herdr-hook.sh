#!/usr/bin/env bash
# git-wt の herdr 連携 hook。
#   wt.hook       -> "git-wt-herdr-hook.sh add"    : 新 worktree 作成後 ($PWD = 新 worktree)
#   wt.deletehook -> "git-wt-herdr-hook.sh delete" : worktree 削除前 ($PWD = 対象 worktree)
# 案A「1段スライド」: workspace = repo / tab = branch。herdr 組み込みの `herdr worktree` は
# worktree を workspace として開くモデル (案B 相当) のため使わず、tab create/close で再現する。
# herdr 操作は best-effort: 失敗しても worktree 操作本体を妨げないよう set -e は使わず最後に exit 0 する。

set -uo pipefail

mode="${1:-}"

# herdr 外では旧 tmux hook に委譲する (移行完了までの併存)
if [[ -z "${HERDR_ENV:-}" ]]; then
  tmux_hook="$HOME/.local/bin/git-wt-tmux-hook.sh"
  [[ -x "$tmux_hook" ]] && exec "$tmux_hook" "$mode"
  exit 0
fi

command -v herdr >/dev/null 2>&1 || exit 0
command -v jq >/dev/null 2>&1 || exit 0

# workspace 名 = メイン worktree のディレクトリ名 ('.' -> '_')。tmux 時代の session 名規約を踏襲
repo_root="$(git worktree list 2>/dev/null | head -1 | awk '{print $1}')"
[[ -z "$repo_root" ]] && exit 0
workspace="$(basename "$repo_root" | tr '.' '_')"

# tab 名 = ブランチ名の basename。tmux 時代の window 名規約を踏襲
branch="$(git branch --show-current 2>/dev/null)"
tab="${branch##*/}"
[[ -z "$tab" ]] && tab="$(basename "$PWD")"

ws_id="$(herdr workspace list 2>/dev/null | jq -r --arg l "$workspace" '.result.workspaces[] | select(.label == $l) | .workspace_id' 2>/dev/null | head -1)"

case "$mode" in
  add)
    if [[ -z "$ws_id" ]]; then
      ws_id="$(herdr workspace create --cwd "$repo_root" --label "$workspace" --no-focus 2>/dev/null | jq -r '.result.workspace.workspace_id // empty' 2>/dev/null)"
    fi
    [[ -z "$ws_id" ]] && exit 0
    herdr tab create --workspace "$ws_id" --cwd "$PWD" --label "$tab" --focus >/dev/null 2>&1
    ;;
  delete)
    [[ -z "$ws_id" ]] && exit 0
    tab_id="$(herdr tab list --workspace "$ws_id" 2>/dev/null | jq -r --arg l "$tab" '.result.tabs[] | select(.label == $l) | .tab_id' 2>/dev/null | head -1)"
    [[ -z "$tab_id" ]] && exit 0
    current_tab="$(herdr pane get "${HERDR_PANE_ID:-}" 2>/dev/null | jq -r '.result.pane.tab_id // empty' 2>/dev/null)"
    if [[ "$tab_id" == "$current_tab" ]]; then
      # 現在の tab を即 close すると pane/cwd が消えて git-wt の remove が中断する。
      # hook 終了後に効くよう遅延 close する。
      ( sleep 0.3; herdr tab close "$tab_id" >/dev/null 2>&1 ) &
    else
      herdr tab close "$tab_id" >/dev/null 2>&1
    fi
    ;;
  *)
    echo "usage: git-wt-herdr-hook.sh <add|delete>" >&2
    exit 1
    ;;
esac

exit 0
