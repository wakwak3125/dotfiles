#! /bin/bash

cd `dirname $0`
ROOT=`dirname $(pwd)`
CONFIG_DIR='~/.config'

ln -sfv $ROOT/_vimrc $HOME/.vimrc
ln -sfv $ROOT/_ideavimrc $HOME/.ideavimrc

if [ ! -d ~/.config/tmux ]; then
  mkdir -p ~/.config/tmux
  echo '~/.config/tmux was created'
fi

ln -sfv $ROOT/config/tmux/tmux.conf $HOME/.config/tmux/tmux.conf

if [ ! -d ~/.config/alacritty ]; then
  mkdir -p ~/.config/alacritty
  echo '~/.config/alacritty was created'
fi

ln -sfv $ROOT/config/alacritty/alacritty.yml $HOME/.config/alacritty/alacritty.yml

