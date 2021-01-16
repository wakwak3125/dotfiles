# Created by newuser for 5.8

source $ZDOTDIR/.zshrc_local

EDITOR=vim
bindkey -e
autoload -Uz add-zsh-hook
setopt auto_cd
setopt extended_glob
setopt correct
setopt interactive_comments

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
alias ll='ls -lhaG'
alias vi='vim'
alias g='git'
alias gs='git switch'
alias gsc='git switch -c'
alias gitpr='git pull-request'
alias pr='pull-request'
eval "$(hub alias -s)"

## Env
eval "$(anyenv init - zsh)"
eval "$(direnv hook zsh)"

## Zplug
source $ZPLUG_HOME/init.zsh
zplug 'zplug/zplug', hook-build:'zplug --self-manage'
zplug 'mafredri/zsh-async'
zplug 'sindresorhus/pure'
zplug 'zsh-users/zsh-syntax-highlighting'
zplug "zsh-users/zsh-history-substring-search"
zplug "zsh-users/zsh-autosuggestions"
zplug "zsh-users/zsh-completions"
zplug "chrissicool/zsh-256color"
zplug "junegunn/fzf-bin", as:command, from:gh-r, rename-to:fzf
zplug "mollifier/anyframe"
zstyle ':completion:*' menu select

if ! zplug check --verbose; then
    printf "Install? [y/N]: "
    if read -q; then
        echo; zplug install
    fi
fi

zplug load

## anyframe
bindkey '^r' anyframe-widget-execute-history
bindkey '^g' anyframe-widget-cd-ghq-repository
bindkey '^xs' anyframe-widget-tmux-attach
bindkey '^xk' anyframe-widget-kill

