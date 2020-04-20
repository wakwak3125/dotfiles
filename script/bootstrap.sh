#! /bin/bash

cd `dirname $0`
ROOT=`dirname $(pwd)`

ln -sfv $ROOT/_vimrc $HOME/.vimrc
ln -sfv $ROOT/_ideavimrc $HOME/.ideavimrc

if [ -e $HOME/.fzf ]; then
  echo '.fzf found'
else
  git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
  $HOME/.fzf/install
fi

if [ -e $HOME/.vim/autoload/plug.vim ]; then
  echo 'plug.vim found'
else
  curl -fLo ~/.vim/autoload/plug.vim --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
fi

if !(type "brew" > /dev/null 2>&1); then
  curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh
  echo "eval $(/home/linuxbrew/.linuxbrew/bin/brew shellenv)" >> $HOME/.zshrc
fi

brew update
brew install ghq anyenv zplug
anyenv install --force-init
