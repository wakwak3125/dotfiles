call plug#begin('~/.vim/plugged')

Plug 'cocopon/iceberg.vim'

call plug#end()

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

set clipboard=unnamed,autoselect,unnamedplus

nmap <Esc><Esc> :nohlsearch<CR><Esc>

set background=dark

set backspace=indent,eol,start

