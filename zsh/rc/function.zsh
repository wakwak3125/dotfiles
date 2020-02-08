function fgq() {
  local select_dir=$(ghq list | fzf --query="$LBUFFER")
  local ghq_root=$(ghq root)
  if [ -n "$select_dir" ]; then
    BUFFER="${ghq_root}/${select_dir}"
    zle accept-line
  fi

  zle reset-prompt
}

zle -N fgq
bindkey "^g" fgq

