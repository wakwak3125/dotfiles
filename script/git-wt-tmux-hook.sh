#!/usr/bin/env bash
# git-wt の tmux 連携 hook。
#   wt.hook       -> "git-wt-tmux-hook.sh add"    : 新 worktree 作成後 ($PWD = 新 worktree)
#   wt.deletehook -> "git-wt-tmux-hook.sh delete" : worktree 削除前 ($PWD = 対象 worktree)
# 旧自前 `wt` (script/wt/main.go) の tmux 連携を git-wt 上で再現する。
# tmux 操作は best-effort: 失敗しても worktree 操作本体を妨げないよう set -e は使わず最後に exit 0 する。

set -uo pipefail

mode="${1:-}"

# tmux 外では何もしない
[[ -z "${TMUX:-}" ]] && exit 0

# session 名 = メイン worktree のディレクトリ名 ('.' -> '_')。旧 wt の loadRepoInfo と同じ
repo_root="$(git worktree list 2>/dev/null | head -1 | awk '{print $1}')"
[[ -z "$repo_root" ]] && exit 0
session="$(basename "$repo_root" | tr '.' '_')"

# window 名 = ブランチ名の basename。旧 wt の branchBasename と同じ
branch="$(git branch --show-current 2>/dev/null)"
window="${branch##*/}"
[[ -z "$window" ]] && window="$(basename "$PWD")"

target="${session}:${window}"

case "$mode" in
  add)
    if ! tmux has-session -t "$session" 2>/dev/null; then
      tmux new-session -d -s "$session" -c "$PWD" -n "$window" 2>/dev/null
      tmux switch-client -t "$target" 2>/dev/null
    else
      tmux new-window -t "$session" -n "$window" -c "$PWD" 2>/dev/null
      if [[ "$(tmux display-message -p '#S' 2>/dev/null)" != "$session" ]]; then
        tmux switch-client -t "$target" 2>/dev/null
      else
        tmux select-window -t "$target" 2>/dev/null
      fi
    fi
    ;;
  delete)
    tmux has-session -t "$session" 2>/dev/null || exit 0
    if [[ "$(tmux display-message -p '#W' 2>/dev/null)" == "$window" ]]; then
      # 現在の window を即 kill すると pane/cwd が消えて git-wt の remove が中断する。
      # hook 終了後に効くよう遅延 kill する。
      ( sleep 0.3; tmux kill-window -t "$target" 2>/dev/null ) &
    else
      tmux kill-window -t "$target" 2>/dev/null
    fi
    ;;
  *)
    echo "usage: git-wt-tmux-hook.sh <add|delete>" >&2
    exit 1
    ;;
esac

exit 0
