call plug#begin('~/.vim/plugged')

Plug 'tyrannicaltoucan/vim-quantum', {'do': 'cp colors/* ~/.vim/colors/'}
Plug 'scrooloose/nerdtree'
Plug 'itchyny/lightline.vim'
Plug 'fatih/vim-go'
Plug 'Shougo/neocomplete'
Plug 'Shougo/neosnippet'
Plug 'Shougo/neosnippet-snippets'
Plug 'tpope/vim-rails'
Plug 'tpope/vim-endwise'

call plug#end()

set fenc=utf-8

set nobackup

set noswapfile

set autoread

set hidden

set showcmd

set number

set cursorline

set cursorcolumn

set virtualedit=onemore

set smartindent

set visualbell

set showmatch

set laststatus=2

set wildmode=list:longest

nnoremap j gj

nnoremap k gk

set list listchars=tab:\▸\-

set expandtab

set tabstop=2

set shiftwidth=2

set ignorecase

set smartcase

set incsearch

set wrapscan

set hlsearch

set clipboard=unnamed,autoselect

nmap <Esc><Esc> :nohlsearch<CR><Esc>

set background=dark

if has('gui_macvim')
  set termguicolors
endif

colorscheme quantum

map <C-e> :NERDTreeToggle<CR>

let g:go_fmt_command = "goimports"

let NERDTreeShowHidden=1
