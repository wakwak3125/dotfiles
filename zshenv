export ZDOTDIR="$HOME/.zsh"

# PATH / FPATH の重複を自動排除 (.zshrc_local 等で同じパスが複数回追加されるため)
typeset -U path PATH fpath FPATH

# sentry
if [[ -d "$HOME/.local/share/zsh/site-functions" ]]; then
  fpath=("$HOME/.local/share/zsh/site-functions" $fpath)
fi
