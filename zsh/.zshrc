# Created by newuser for 5.8

fpath=(
  $HOME/.zsh/functions
  "${fpath[@]}"
)

## Env
command -v sheldon >/dev/null 2>&1 && eval "$(sheldon source)"
_mise_bin=""
if [[ -x "$HOME/.local/bin/mise" ]]; then
  _mise_bin="$HOME/.local/bin/mise"
elif command -v mise >/dev/null 2>&1; then
  _mise_bin="mise"
fi
if [[ -n "$_mise_bin" ]]; then
  eval "$("$_mise_bin" activate zsh)"
fi
command -v direnv >/dev/null 2>&1 && eval "$(direnv hook zsh)"
# git-wt: git worktree ヘルパー。git() ラッパー関数と補完を有効化 (未インストール時はスキップ)
command -v git-wt >/dev/null 2>&1 && eval "$(git-wt --init zsh)"
if [[ -n "$_mise_bin" ]]; then
  JAVA_HOME="$("$_mise_bin" where java 2>/dev/null || true)"
  [[ -n "$JAVA_HOME" ]] && export JAVA_HOME
fi
unset _mise_bin

[[ -f "$ZDOTDIR/.zshrc_local" ]] && source "$ZDOTDIR/.zshrc_local"

bindkey -e
autoload -Uz add-zsh-hook

# herdr tab 名 / tmux window 名を git ブランチ名に自動更新
function _mux_update_window_name() {
  [[ -n "$HERDR_ENV" || -n "$TMUX" ]] || return
  local name branch
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
  if [[ -n "$branch" ]]; then
    if [[ "$branch" == "HEAD" ]]; then
      branch=$(git rev-parse --short HEAD 2>/dev/null)
    fi
    name="${branch##*/}"
  else
    name="${PWD##*/}"
  fi
  if [[ -n "$HERDR_ENV" ]]; then
    command -v herdr >/dev/null 2>&1 || return
    command -v jq >/dev/null 2>&1 || return
    # tab_id は pane 生存中不変なので初回のみ逆引きしてキャッシュ。
    # rename は前回値と変わったときだけ送り precmd 毎の socket 往復を避ける
    if [[ -z "$_HERDR_TAB_ID" ]]; then
      _HERDR_TAB_ID=$(herdr pane get "$HERDR_PANE_ID" 2>/dev/null | jq -r '.result.pane.tab_id // empty' 2>/dev/null)
    fi
    if [[ -n "$_HERDR_TAB_ID" && "$name" != "$_HERDR_TAB_NAME" ]]; then
      herdr tab rename "$_HERDR_TAB_ID" "$name" >/dev/null 2>&1 && _HERDR_TAB_NAME="$name"
    fi
  elif [[ -n "$TMUX" ]]; then
    tmux rename-window "$name"
  fi
}
add-zsh-hook precmd _mux_update_window_name

#setopt auto_cd
setopt extended_glob
setopt correct
setopt interactive_comments
autoload -Uz compinit
compinit
zstyle ':completion:*:default' menu select=2

## History
HISTFILE=~/.zsh/.zsh_history
HISTSIZE=100000
SAVEHIST=100000
setopt hist_ignore_all_dups
setopt hist_ignore_space
setopt hist_reduce_blanks
setopt share_history

## Directory
setopt auto_pushd
setopt pushd_ignore_dups
DIRSTACKSIZE=100

## alias
if [[ "$(uname)" == "Darwin" ]]; then
  alias ll='ls -lhaG'
else
  alias ll='ls -lha --color=auto'
fi
alias g='git'

# tmux全セッション削除
function tmux-kill-all() {
  if ! tmux list-sessions &>/dev/null; then
    echo "No tmux sessions running."
    return 0
  fi

  echo "Active tmux sessions:"
  tmux list-sessions
  echo ""
  read -q "REPLY?Kill all tmux sessions? [y/N] "
  echo ""
  if [[ "$REPLY" =~ ^[Yy]$ ]]; then
    tmux kill-server
    echo "All tmux sessions killed."
  else
    echo "Cancelled."
  fi
}

# starship prompt
command -v starship >/dev/null 2>&1 && eval "$(starship init zsh)"

## fzf widgets (replacing anyframe)
# 履歴検索
function fzf-history-widget() {
  local selected
  selected=$(history -n -r 1 | fzf --query="$LBUFFER" --no-sort)
  if [[ -n "$selected" ]]; then
    BUFFER="$selected"
    CURSOR=$#BUFFER
  fi
  zle reset-prompt
}
zle -N fzf-history-widget
bindkey '^r' fzf-history-widget

# ghqリポジトリ移動 + herdr workspace / tmuxセッション
function fzf-ghq-widget() {
  local selected workspace_name
  selected=$(ghq list -p | fzf --query="$LBUFFER")
  if [[ -n "$selected" ]]; then
    # リポジトリ名をworkspace/セッション名に（.を_に置換）
    workspace_name=$(basename "$selected" | tr '.' '_')

    if [[ -n "$HERDR_ENV" ]]; then
      # herdr内の場合: workspace = repo (案A)。label一致で focus/create
      local ws_id current_ws
      ws_id=$(herdr workspace list 2>/dev/null | jq -r --arg l "$workspace_name" '.result.workspaces[] | select(.label == $l) | .workspace_id' 2>/dev/null | head -1)
      current_ws=$(herdr pane get "$HERDR_PANE_ID" 2>/dev/null | jq -r '.result.pane.workspace_id // empty' 2>/dev/null)
      if [[ -n "$ws_id" && "$ws_id" == "$current_ws" ]]; then
        # すでにそのworkspaceにいる場合はcdを実行
        cd "$selected"
      elif [[ -n "$ws_id" ]]; then
        herdr workspace focus "$ws_id" >/dev/null 2>&1 || cd "$selected"
      else
        herdr workspace create --cwd "$selected" --label "$workspace_name" --focus >/dev/null 2>&1 || cd "$selected"
      fi
    elif [[ -n "$TMUX" ]]; then
      # tmux内の場合 (移行完了まで併存)
      local current_session
      current_session=$(tmux display-message -p '#S')
      if [[ "$current_session" == "$workspace_name" ]]; then
        # すでにそのセッションにいる場合はcdを実行
        cd "$selected"
      elif tmux has-session -t "$workspace_name" 2>/dev/null; then
        tmux switch-client -t "$workspace_name"
      else
        tmux new-session -d -s "$workspace_name" -c "$selected"
        tmux switch-client -t "$workspace_name"
      fi
    else
      # multiplexer外の場合はcdのみ (herdrへは auto-attach で入る)
      cd "$selected"
    fi
  fi
  zle reset-prompt
}
zle -N fzf-ghq-widget
bindkey '^]' fzf-ghq-widget

# git worktree移動 + herdr workspace/tab / tmuxセッション/ウィンドウ
function fzf-worktree-widget() {
  local selected worktree_path window_name session_name repo_root repo_name
  local worktrees

  # 現在のディレクトリがgit管理下かどうかをチェック
  if git rev-parse --is-inside-work-tree &>/dev/null; then
    # git管理下の場合は現在のリポジトリのworktreeのみ取得
    worktrees=$(git worktree list 2>/dev/null)
  else
    # git管理下でない場合は全ghqリポジトリからworktreeを収集
    local spinner='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local spin_idx=0
    local tmpfile=$(mktemp)
    local donefile=$(mktemp)
    rm -f "$donefile"

    # バックグラウンドで全ghqリポジトリからworktreeを収集
    {
      ghq list -p | while IFS= read -r repo; do
        git -C "$repo" worktree list 2>/dev/null
      done > "$tmpfile"
      touch "$donefile"
    } &!

    # スピナーを表示しながら待機
    while [[ ! -f "$donefile" ]]; do
      zle -M "${spinner:$spin_idx:1} Scanning worktrees..."
      zle -R
      spin_idx=$(( (spin_idx + 1) % ${#spinner} ))
      sleep 0.1
    done
    zle -M ""

    worktrees=$(<"$tmpfile")
    rm -f "$tmpfile" "$donefile"
  fi

  # worktree一覧を表示
  selected=$(echo "$worktrees" | fzf --query="$LBUFFER")

  if [[ -n "$selected" ]]; then
    # パスを取得（最初のカラム）
    worktree_path=$(echo "$selected" | awk '{print $1}')
    # ウィンドウ名はworktreeのブランチ名（precmdフックと統一）
    window_name=$(git -C "$worktree_path" rev-parse --abbrev-ref HEAD 2>/dev/null)
    window_name="${window_name##*/}"
    [[ -z "$window_name" ]] && window_name=$(basename "$worktree_path" | tr '.' '_')
    # リポジトリのルートパスを取得（選択したworktreeから取得）
    repo_root=$(git -C "$worktree_path" worktree list | head -1 | awk '{print $1}')
    # リポジトリ名をworkspace/セッション名に
    repo_name=$(basename "$repo_root" | tr '.' '_')
    session_name="$repo_name"

    if [[ -n "$HERDR_ENV" ]]; then
      # herdr内の場合: workspace = repo / tab = branch (案A)
      local ws_id tab_id current_tab
      ws_id=$(herdr workspace list 2>/dev/null | jq -r --arg l "$repo_name" '.result.workspaces[] | select(.label == $l) | .workspace_id' 2>/dev/null | head -1)
      if [[ -z "$ws_id" ]]; then
        # repo の workspace がなければ作成 (root tab は repo 直下)
        ws_id=$(herdr workspace create --cwd "$repo_root" --label "$repo_name" --no-focus 2>/dev/null | jq -r '.result.workspace.workspace_id // empty' 2>/dev/null)
      fi
      if [[ -n "$ws_id" ]]; then
        tab_id=$(herdr tab list --workspace "$ws_id" 2>/dev/null | jq -r --arg l "$window_name" '.result.tabs[] | select(.label == $l) | .tab_id' 2>/dev/null | head -1)
        current_tab=$(herdr pane get "$HERDR_PANE_ID" 2>/dev/null | jq -r '.result.pane.tab_id // empty' 2>/dev/null)
        if [[ -n "$tab_id" && "$tab_id" == "$current_tab" ]]; then
          # すでにそのtabにいる場合はcdを実行
          cd "$worktree_path"
        elif [[ -n "$tab_id" ]]; then
          herdr tab focus "$tab_id" >/dev/null 2>&1 || cd "$worktree_path"
        else
          herdr tab create --workspace "$ws_id" --cwd "$worktree_path" --label "$window_name" --focus >/dev/null 2>&1 || cd "$worktree_path"
        fi
      else
        # workspace 解決失敗時はcdのみ (best-effort)
        cd "$worktree_path"
      fi
    elif [[ -n "$TMUX" ]]; then
      # tmux内の場合
      local current_session current_window
      current_session=$(tmux display-message -p '#S')
      current_window=$(tmux display-message -p '#W')
      if [[ "$current_session" == "$session_name" ]]; then
        # すでに対象セッションにいる場合
        if [[ "$current_window" == "$window_name" ]]; then
          # すでにそのウィンドウにいる場合はcdを実行
          cd "$worktree_path"
        elif tmux list-windows -t "$session_name" -F '#W' | grep -qxF "${window_name}"; then
          # ウィンドウが存在すれば移動
          tmux select-window -t "$session_name:$window_name"
        else
          # ウィンドウがなければ作成（-tなしで現在のセッションに作成）
          tmux new-window -n "$window_name" -c "$worktree_path"
        fi
      elif tmux has-session -t "$session_name" 2>/dev/null; then
        # 別のセッションにいて、対象セッションが存在する場合
        if tmux list-windows -t "$session_name" -F '#W' | grep -qxF "${window_name}"; then
          # ウィンドウが存在すれば移動
          tmux switch-client -t "$session_name"
          tmux select-window -t "$session_name:$window_name"
        else
          # ウィンドウがなければ作成して移動
          tmux new-window -t "$session_name" -n "$window_name" -c "$worktree_path"
          tmux switch-client -t "$session_name"
        fi
      else
        # セッションがなければ作成（ウィンドウ名も指定）
        tmux new-session -d -s "$session_name" -n "$window_name" -c "$worktree_path"
        tmux switch-client -t "$session_name"
      fi
    else
      # multiplexer外の場合はcdのみ (herdrへは auto-attach で入る)
      cd "$worktree_path"
    fi
  fi
  zle reset-prompt
}
zle -N fzf-worktree-widget
bindkey '^w' fzf-worktree-widget

# herdr auto-attach (loaded from functions directory)
# To disable, add AUTO_HERDR=false to ~/.zsh/.zshrc_local
autoload -Uz herdr-auto-attach
herdr-auto-attach

fancy-ctrl-z () {
  if [[ $#BUFFER -eq 0 ]]; then
    BUFFER="fg"
    zle accept-line
  else
    zle push-input
    zle clear-screen
  fi
}
zle -N fancy-ctrl-z
bindkey '^Z' fancy-ctrl-z

function fgg() {
    wc=$(jobs | wc -l | tr -d ' ')
    if [ $wc -ne 0 ]; then
        job=$(jobs | awk -F "suspended" "{print $1 $2}"|sed -e "s/\-//g" -e "s/\+//g" -e "s/\[//g" -e "s/\]//g" | grep -v pwd | fzf | awk "{print $1}")
        wc_grep=$(echo $job | grep -v grep | grep 'suspended')
        if [ "$wc_grep" != "" ]; then
            fg %$job
        fi
    fi
}

# Claude Code YOLO mode
autoload -Uz yolo
compdef yolo=claude

# Docker CLI completions (パスが存在する場合のみ)
if [[ -d "$HOME/.docker/completions" ]]; then
  fpath=($HOME/.docker/completions $fpath)
  autoload -Uz compinit
  compinit
fi
