if [ -e $HOME/.vimrc ]; then
	echo '.vimrc found'
else
	ln -s _vimrc $HOME/.vimrc
fi

if [ -e $HOME/.gvimrc ]; then
	echo '.gvimrc found'
else
	ln -s _gvimrc $HOME/.gvimrc
fi

if [ -e $HOME/.ideavimrc ]; then
	echo '.ideavimrc found'
else
	ln -s _ideavimrc $HOME/.ideavimrc
fi

if [ -e $HOME/.fzf ]; then
	echo '.fzf found'
else
	git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
	~/.fzf/install
fi

mkdir ./_vim/plugged
mkdir ./_vim/colors

