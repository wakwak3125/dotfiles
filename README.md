# dotfiles

- Just for me

## Setup

```bash
./script/bootstrap.sh
```

`bootstrap.sh` detects the host and delegates OS-specific work:

- macOS: `script/macos.sh`
- Ubuntu / WSL2: `script/linux.sh` (`script/wsl.sh` is a deprecated alias)

Common config symlinks for zsh, Neovim, tmux, herdr, sheldon, mise, starship, git, and agent runtime files are managed by `bootstrap.sh`. Codex profiles are rendered with `$HOME` expanded. Personal skills are installed with `gh skill` for Claude Code and Codex when the local GitHub CLI supports it.

## Ubuntu Notes

- `script/linux.sh` installs CLI dependencies with `apt-get`, installs sheldon into `~/.local/bin`, and changes the login shell to zsh.
- On desktop machines it also installs `wl-clipboard`/`xclip` and links Ghostty, Zed, and Terminator configs. The apps themselves are not installed (e.g. `sudo snap install ghostty --classic`).
- Neovim switches the IME back to `xkb:us::eng` via `ibus` when leaving insert mode.
- The Karabiner-based "IME off on Ctrl+T" is macOS only.
- `mise install` hits the GitHub API heavily; export `GITHUB_TOKEN` before bootstrap on a fresh machine to avoid rate limits.

## WSL2 Notes

- Run this repository inside the WSL filesystem, not under `/mnt/c`, to avoid slow file watching and permission edge cases.
- WezTerm is expected to be installed and configured on Windows, so this repository does not manage WezTerm config.
- `pbcopy`/`pbpaste` polyfills use Windows clipboard providers when available.
- Neovim uses `win32yank.exe` when present, otherwise falls back to `clip.exe` and PowerShell for clipboard integration.
