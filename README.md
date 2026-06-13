# dotfiles

- Just for me

## Setup

```bash
./script/bootstrap.sh
```

`bootstrap.sh` detects the host and delegates OS-specific work:

- macOS: `script/macos.sh`
- WSL2/Linux: `script/wsl.sh`

Common config symlinks for zsh, Neovim, tmux, herdr, sheldon, mise, starship, git, and Claude Code are managed by `bootstrap.sh`.

## WSL2 Notes

- Run this repository inside the WSL filesystem, not under `/mnt/c`, to avoid slow file watching and permission edge cases.
- WezTerm is expected to be installed and configured on Windows, so this repository does not manage WezTerm config.
- `script/wsl.sh` installs WSL-side CLI dependencies with `apt-get` and links `pbcopy`/`pbpaste` to Windows clipboard providers when available.
- Neovim uses `win32yank.exe` when present, otherwise falls back to `clip.exe` and PowerShell for clipboard integration.
- `herdr` auto attach is disabled by default on WSL. Add `AUTO_HERDR=true` to `~/.zsh/.zshrc_local` only after confirming it works in your Windows terminal.
