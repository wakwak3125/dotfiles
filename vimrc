if empty(glob('~/.vim/autoload/plug.vim'))
  silent !curl -fLo ~/.vim/autoload/plug.vim --create-dirs
    \ https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
  autocmd VimEnter * PlugInstall --sync | source $MYVIMRC
endif

call plug#begin('~/.vim/plugged')
Plug 'nordtheme/vim'
call plug#end()

syntax on
colorscheme nord
set termguicolors

set fenc=utf-8
set nobackup
set noswapfile
set autoread
set hidden
set showcmd
set number
set virtualedit=onemore
set smartindent
set showmatch
set laststatus=2
set wildmode=list:longest
nnoremap j gj
nnoremap k gk
set expandtab
set tabstop=2
set shiftwidth=2
set ignorecase
set smartcase
set incsearch
set wrapscan
set hlsearch
set clipboard=unnamed
nmap <Esc><Esc> :nohlsearch<CR><Esc>
set backspace=indent,eol,start

