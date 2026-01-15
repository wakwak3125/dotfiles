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

## Env
eval "$(sheldon source)"
eval "$(~/.local/bin/mise activate zsh)"
eval "$(direnv hook zsh)"

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
      if tmux has-session -t "$session_name" 2>/dev/null; then
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

#THIS MUST BE AT THE END OF THE FILE FOR SDKMAN TO WORK!!!
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"

