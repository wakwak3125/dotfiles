if [ -e $HOME/.vimrc ]; then
	echo '.vimrc found'
else
	ln -sf $HOME/dotfiles/_vimrc ~/.vimrc
fi

if [ -e $HOME/.ideavimrc ]; then
	echo '.ideavimrc found'
else
	ln -s $HOME/dotfiles/_ideavimrc $HOME/.ideavimrc
fi

if [ -e $HOME/.fzf ]; then
	echo '.fzf found'
else
	git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
	~/.fzf/install
fi

if [ -e $HOME/.vim/autoload/plug.vim ]; then
  echo 'plug.vim found'
else
  curl -fLo ~/.vim/autoload/plug.vim --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
fi

mkdir ./_vim/plugged
mkdir ./_vim/colors

