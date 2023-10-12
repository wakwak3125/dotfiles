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

#anyenv
export PATH=$PATH:$HOME/.anyenv/bin

EDITOR=vim
bindkey -e
autoload -Uz add-zsh-hook
setopt auto_cd
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
alias vi='vim'
alias g='git'

## Env
eval "$(anyenv init - zsh)"
eval "$(direnv hook zsh)"
eval "$(sheldon source)"

## anyframe
bindkey '^r' anyframe-widget-put-history
bindkey '^g' anyframe-widget-cd-ghq-repository
bindkey '^xs' anyframe-widget-tmux-attach
bindkey '^xk' anyframe-widget-kill

PERCOL=fzf

## Launch tmux
if [[ ! -n $TMUX && -o login ]]; then
  # get the IDs
  ID="`tmux list-sessions`"
  if [[ -z "$ID" ]]; then
    tmux new-session
  fi
  create_new_session="Create New Session"
  ID="$ID\n${create_new_session}:"
  ID="`echo $ID | $PERCOL | cut -d: -f1`"
  if [[ "$ID" = "${create_new_session}" ]]; then
    tmux new-session
  elif [[ -n "$ID" ]]; then
    tmux attach-session -t "$ID"
  else
    :  # Start terminal normally
  fi
fi

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
