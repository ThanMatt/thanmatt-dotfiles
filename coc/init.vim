call plug#begin() 
Plug 'neoclide/coc.nvim', {'branch': 'release'} 
Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
Plug 'junegunn/fzf.vim'
Plug 'itchyny/lightline.vim' 
Plug 'scrooloose/nerdtree'
Plug 'mg979/vim-visual-multi', {'branch': 'master'}
Plug 'maxmellon/vim-jsx-pretty'
Plug 'yuezk/vim-js'
Plug 'alvan/vim-closetag'
Plug 'jparise/vim-graphql'
Plug 'mileszs/ack.vim'
Plug 'junegunn/goyo.vim'
Plug 'Xuyuanp/nerdtree-git-plugin'
Plug 'airblade/vim-gitgutter'
Plug 'APZelos/blamer.nvim'
Plug 'preservim/nerdcommenter'
Plug 'jremmen/vim-ripgrep'
Plug 'easymotion/vim-easymotion'

call plug#end()

map ; :Files<CR>
map <C-I> :NERDTreeToggle<CR>
map <S-Right> :Goyo<CR>
map <S-Left> :Goyo!<CR>
nnoremap <C-J> <C-W><C-J>
nnoremap <C-K> <C-W><C-K>
nnoremap <C-L> <C-W><C-L>
nnoremap <C-H> <C-W><C-H>
nnoremap <C-P> <C-I>
nnoremap <silent> <Leader>f :Rg<CR>
"nmap <C-P> :call GotoJump()<CR>

"inoremap q <c-v>

let g:NERDTreeGitStatusWithFlags = 1
let g:NERDTreeIgnore = ['^node_modules$', '^dist$']
let NERDTreeShowHidden = 1
let g:closetag_filenames = '*.html,*.xhtml,*.phtml, *.js'
let g:closetag_xhtml_filenames = '*.xhtml,*.jsx'
let g:blamer_enabled = 1

vmap ++ <plug>NERDCommenterToggle
nmap ++ <plug>NERDCommenterToggle


let g:EasyMotion_do_mapping = 0 " Disable default mappings

" Jump to anywhere you want with minimal keystrokes, with just one key binding.
" `s{char}{label}`
nmap s <Plug>(easymotion-overwin-f)
" or
" `s{char}{char}{label}`
" Need one more keystroke, but on average, it may be more comfortable.
nmap s <Plug>(easymotion-overwin-f2)

" Turn on case-insensitive feature
let g:EasyMotion_smartcase = 1

" JK motions: Line motions
map <Leader>j <Plug>(easymotion-j)
map <Leader>k <Plug>(easymotion-k)


function! Start()
    " Don't run if: we have commandline arguments, we don't have an empty
    " buffer, if we've not invoked as vim or gvim, or if we'e start in insert mode
    if argc() || line2byte('$') != -1 || v:progname !~? '^[-gmnq]\=vim\=x\=\%[\.exe]$' || &insertmode
        return
    endif

    " Start a new buffer ...
    enew

    " Now we can just write to the buffer, whatever you want.
    " the '^' says to write the next argument at the beginning of the file
call append('^', '⣿⣿⣿⣿⣿⣿⣿⣿⣿⠃⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⣿⣿')
call append('^', '⣿⣿⣿⣿⣿⣿⣿⣿⣧⠀⠀⠀⠀⠀⠀⠀⠈⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢹⣿⣿')
call append('^', '⣿⣿⣿⣿⣿⣿⣿⣿⡀⠉⠀⠀⠀⠀⠀⢄⠀⢀⠀⠀⠀⠀⠉⠉⠁⠀⠀⣿⣿⣿')
call append('^', '⣿⣿⣿⣿⣿⣿⣿⣿⢾⣿⣷⠀⠀⠀⠀⡠⠤⢄⠀⠀⠀⠠⣿⣿⣷⠀⢸⣿⣿⣿')
call append('^', '⣿⣿⣿⣿⣿⣿⣿⣿⠃⠀⠀⠈⠉⠀⠀⠤⠄⠀⠀⠀⠉⠁⠀⠀⠀⠀⢿⣿⣿⣿')
call append('^', '⣿⣿⣿⣿⣿⣿⣿⣿⡟⠀⠀⢰⣹⡆⠀⠀⠀⠀⠀⠀⣭⣷⠀⠀⠀⠸⣿⣿⣿⣿')
call append('^', '⣿⣿⣿⣿⣿⣿⣿⣿⣿⠏⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠠⣴⣿⣿⣿⣿')
call append('^', '⣿⣿⣿⣿⣿⣿⣿⣷⣄⠀⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣴⣿⣿')
call append('^', '⣿⣿⣿⣿⣿⣿⣧⡀⠀⠀⠀⠀⠙⠿⠿⠿⠻⠿⠿⠟⠿⠛⠉⠀⠀⠀⠀⠀⣸⣿')
call append('^', '⣿⣿⣿⣿⣿⣿⠀⠀⠀⠈⠛⢿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠿⠛⠉⠁⠀⣿')
call append('^', '⣿⣿⣿⣿⣿⡏⠉⠛⢿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡿⣿')

    setlocal nomodifiable nomodified
endfunction

" Run after "doing all the startup stuff"
autocmd VimEnter * call Start()

set relativenumber
" When entering Insert mode, disable relativenumber
autocmd InsertEnter * :set norelativenumber

" When leaving Insert mode, enable relativenumber
autocmd InsertLeave * :set relativenumber


set wildignore=*/node_modules/*,*/android/*,*/ios/*
set mouse=a

"colorscheme gruvbox


"Indentations 
set expandtab
set tabstop=2
set softtabstop=2
set shiftwidth=2
set smartindent
set number


command! -nargs=0 Prettier :CocCommand prettier.formatFile

noremap <silent> <C-S> :update<CR>
"vnoremap <silent> <C-S> <C-C>:update<CR>
"inoremap <silent> <C-S> <C-O>:update<CR>

nmap <silent><expr> <c-space> coc#refresh()
inoremap <silent><expr> <CR> coc#pum#visible() ? coc#pum#confirm() : "\<C-g>u\<CR>"

nmap <silent> gd <Plug>(coc-definition)
nmap <silent> gy <Plug>(coc-type-definition)
nmap <silent> gi <Plug>(coc-implementation)
nmap <silent> gr <Plug>(coc-references)

" Use K to show documentation in preview window
nnoremap <silent> K :call <SID>show_documentation()<CR>


function! s:show_documentation()
  if (index(['vim','help'], &filetype) >= 0)
    execute 'h '.expand('<cword>')
  else
    call CocAction('doHover')
  endif
endfunction

function! s:goyo_enter()
  set number
  set relativenumber
  set wrap
  set linebreak
endfunction

function! GotoJump()
  jumps
  let j = input("Please select your jump: ")
  if j != ''
    let pattern = '\v\c^\+'
    if j =~ pattern
      let j = substitute(j, pattern, '', 'g')
      execute "normal " . j . "\<c-i>"
    else
      execute "normal " . j . "\<c-o>"
    endif
  endif
endfunction

let g:prettier#config#single_quote = 'false' 
let g:coc_global_extensions = [
  \ 'coc-snippets',
  \ 'coc-pairs',
  \ 'coc-tsserver',
  \ 'coc-eslint', 
  \ 'coc-prettier', 
  \ 'coc-json'
  \ ]

" from readme
" if hidden is not set, TextEdit might fail.
set hidden " Some servers have issues with backup files, see #649 set nobackup set nowritebackup " Better display for messages set cmdheight=2 " You will have bad experience for diagnostic messages when it's default 4000.
set updatetime=300
set clipboard+=unnamedplus

command! -nargs=0 Format :call CocAction('format')
autocmd! User GoyoEnter nested call <SID>goyo_enter()
autocmd CursorHold * silent call CocActionAsync('highlight')
