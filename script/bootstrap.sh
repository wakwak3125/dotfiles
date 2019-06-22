if [ -e $HOME/.vimrc ]; then
	echo '.vimrc is already exists'
else
	ln -s _vimrc $HOME/.vimrc
fi

if [ -e $HOME/.gvimrc ]; then
	echo '.gvimrc is already exists'
else
	ln -s _gvimrc $HOME/.gvimrc
fi

if [ -e $HOME/.ideavimrc ]; then
	echo '.ideavimrc is already exists'
else
	ln -s _ideavimrc $HOME/.ideavimrc
fi

mkdir ./_vim/plugged
mkdir ./_vim/colors

