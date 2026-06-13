export ZDOTDIR="$HOME/.zsh"

# sentry
if [[ -d "$HOME/.local/share/zsh/site-functions" ]]; then
  fpath=("$HOME/.local/share/zsh/site-functions" $fpath)
fi
