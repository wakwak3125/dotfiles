#! /bin/bash

cd `dirname $0`
ROOT=`dirname $(pwd)`
CONFIG_DIR='~/.config'

ln -sfv $ROOT/vimrc $HOME/.vimrc
ln -sfv $ROOT/ideavimrc $HOME/.ideavimrc
ln -sfv $ROOT/obsidian.vimrc $HOME/.obsidian.vimrc
ln -sfv $ROOT/zsh $HOME/.zsh
ln -sfv $ROOT/zshenv $HOME/.zshenv


if [ ! -d ~/.config/tmux ]; then
  mkdir -p ~/.config/tmux
  echo '~/.config/tmux was created'
fi

ln -sfv $ROOT/config/tmux/tmux.conf $HOME/.tmux.conf

if [ ! -d ~/.config/alacritty ]; then
  mkdir -p ~/.config/alacritty
  echo '~/.config/alacritty was created'
fi

ln -sfv $ROOT/config/alacritty/alacritty.yml $HOME/.config/alacritty/alacritty.yml

if [ ! -d ~/.config/sheldon ]; then
  mkdir -p ~/.config/sheldon
  echo '~/.config/sheldon was created'
fi

ln -sfv $ROOT/config/sheldon/plugins.toml $HOME/.config/sheldon/plugins.toml
