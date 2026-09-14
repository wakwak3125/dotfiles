export ZDOTDIR="$HOME/.zsh"

# Ubuntu の /etc/zsh/zshrc が .zshrc より先に compinit するのを止める。
# fpath が揃う前の compinit と .zshrc の compinit で毎回 .zcompdump が作り直され起動が遅くなるため
skip_global_compinit=1

# PATH / FPATH の重複を自動排除 (.zshrc_local 等で同じパスが複数回追加されるため)
typeset -U path PATH fpath FPATH

# mise / sheldon / claude 等の置き場。Ubuntu の ~/.profile は zsh からは読まれないため明示する
if [[ -d "$HOME/.local/bin" ]]; then
  path=("$HOME/.local/bin" $path)
fi

# sentry
if [[ -d "$HOME/.local/share/zsh/site-functions" ]]; then
  fpath=("$HOME/.local/share/zsh/site-functions" $fpath)
fi
