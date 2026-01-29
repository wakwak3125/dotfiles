# Created by newuser for 5.8

fpath=( 
  $HOME/.zsh/functions 
  "${fpath[@]}"
)

source $ZDOTDIR/.zshrc_local

#sdkman
export SDKMAN_DIR="$HOME/.sdkman"
export JAVA_HOME=$HOME/.sdkman/candidates/java/current

#golang
export GOPATH=$HOME/go
export GOBIN=$GOPATH/bin
export PATH=$PATH:$GOBIN

#rust
export PATH=$PATH:$HOME/.cargo/bin

bindkey -e
autoload -Uz add-zsh-hook
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
alias ll='ls -lhaG --color=auto'
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

## Env
eval "$(sheldon source)"
eval "$(~/.local/bin/mise activate zsh)"
eval "$(direnv hook zsh)"

# starship prompt
eval "$(starship init zsh)"

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

# ghqリポジトリ移動 + tmuxセッション
function fzf-ghq-widget() {
  local selected session_name
  selected=$(ghq list -p | fzf --query="$LBUFFER")
  if [[ -n "$selected" ]]; then
    # リポジトリ名をセッション名に（.を_に置換）
    session_name=$(basename "$selected" | tr '.' '_')

    if [[ -n "$TMUX" ]]; then
      # tmux内の場合
      local current_session
      current_session=$(tmux display-message -p '#S')
      if [[ "$current_session" == "$session_name" ]]; then
        # すでにそのセッションにいる場合はcdを実行
        cd "$selected"
      elif tmux has-session -t "$session_name" 2>/dev/null; then
        tmux switch-client -t "$session_name"
      else
        tmux new-session -d -s "$session_name" -c "$selected"
        tmux switch-client -t "$session_name"
      fi
    else
      # tmux外の場合
      if tmux has-session -t "$session_name" 2>/dev/null; then
        tmux attach-session -t "$session_name"
      else
        tmux new-session -s "$session_name" -c "$selected"
      fi
    fi
  fi
  zle reset-prompt
}
zle -N fzf-ghq-widget
bindkey '^g' fzf-ghq-widget

# git worktree移動 + tmuxセッション/ウィンドウ
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
    # ウィンドウ名はworktreeのディレクトリ名
    window_name=$(basename "$worktree_path" | tr '.' '_')
    # リポジトリのルートパスを取得（選択したworktreeから取得）
    repo_root=$(git -C "$worktree_path" worktree list | head -1 | awk '{print $1}')
    # リポジトリ名をセッション名に
    repo_name=$(basename "$repo_root" | tr '.' '_')
    session_name="$repo_name"

    if [[ -n "$TMUX" ]]; then
      # tmux内の場合
      local current_session current_window
      current_session=$(tmux display-message -p '#S')
      current_window=$(tmux display-message -p '#W')
      if [[ "$current_session" == "$session_name" ]]; then
        # すでに対象セッションにいる場合
        if [[ "$current_window" == "$window_name" ]]; then
          # すでにそのウィンドウにいる場合はcdを実行
          cd "$worktree_path"
        elif tmux list-windows -t "$session_name" -F '#W' | grep -q "^${window_name}$"; then
          # ウィンドウが存在すれば移動
          tmux select-window -t "$session_name:$window_name"
        else
          # ウィンドウがなければ作成（-tなしで現在のセッションに作成）
          tmux new-window -n "$window_name" -c "$worktree_path"
        fi
      elif tmux has-session -t "$session_name" 2>/dev/null; then
        # 別のセッションにいて、対象セッションが存在する場合
        if tmux list-windows -t "$session_name" -F '#W' | grep -q "^${window_name}$"; then
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
      # tmux外の場合
      if tmux has-session -t "$session_name" 2>/dev/null; then
        if tmux list-windows -t "$session_name" -F '#W' | grep -q "^${window_name}$"; then
          tmux attach-session -t "$session_name"
          tmux select-window -t "$session_name:$window_name"
        else
          tmux new-window -t "$session_name" -n "$window_name" -c "$worktree_path"
          tmux attach-session -t "$session_name"
        fi
      else
        tmux new-session -s "$session_name" -n "$window_name" -c "$worktree_path"
      fi
    fi
  fi
  zle reset-prompt
}
zle -N fzf-worktree-widget
bindkey '^w' fzf-worktree-widget

# tmux auto-attach (loaded from functions directory)
# To disable, add AUTO_TMUX=false to ~/.zsh/.zshrc_local
autoload -Uz tmux-auto-attach
tmux-auto-attach

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

# git worktree helper command
autoload -Uz wt

#THIS MUST BE AT THE END OF THE FILE FOR SDKMAN TO WORK!!!
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"

# The following lines have been added by Docker Desktop to enable Docker CLI completions.
fpath=(/Users/wakwak/.docker/completions $fpath)
autoload -Uz compinit
compinit
# End of Docker CLI completions
