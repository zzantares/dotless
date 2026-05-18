" Trylist
" https://github.com/Valloric/MatchTagAlways
" https://github.com/mhinz/vim-sayonara  to replace bufonly
" TODO: ZzTerm and LastFrame require refactoring
" =============================================================================
" Start Vim Plug setup
" =============================================================================

if &compatible
  set nocompatible  " Be iMproved
endif

call plug#begin(stdpath('data') . '/plugged')
  " Add or remove your plugins here:
  " Plug 'Shougo/deoplete.nvim', { 'do': ':UpdateRemotePlugins' }   " Completion framework
  " Plug 'zchee/deoplete-go', {'do': 'make'}     " Go source completion for deoplete
  " Plug 'zchee/deoplete-jedi'                   " Python source completion for deoplete
  " Plug 'carlitux/deoplete-ternjs'              " Javascript source completion for deoplete
  " Plug 'Shougo/denite.nvim', { 'do': ':UpdateRemotePlugins' }  " Narrowing framework

  " Plug 'Shougo/echodoc.vim'                    " Display function signatures from completions the command line
  " Plug 'dense-analysis/ale'                    " Asynchronous Linting Engine
  " "Plug 'vim-airline/vim-airline'               " Better looking status line and buffer line
  Plug 'justinmk/vim-sneak'                    " Quick jump motion
  Plug 'SirVer/ultisnips'                      " Ultimate snippet solution for Vim
  Plug 'schickling/vim-bufonly'                " Kill all buffers but current
  Plug 'vim-scripts/gitignore'                 " Ignore .gitignore files on vim tab completion commands
  Plug 'junegunn/goyo.vim'                     " Distraction free editing
  Plug 'Raimondi/delimitMate'                  " Autoclose pairs
  Plug 'tpope/vim-surround'                    " Manipulate surrounding chars
  Plug 'airblade/vim-gitgutter'                " Git diff in the sign column as well as easy stage/discard tool
  " "Plug 'lambdalisue/gina.vim'                  " Magit like git wrapper for vim
  " "Plug 'rhysd/committia.vim'                   " Useful editing on git commit messages

  " File type & language support
  " Plug 'folke/lazydev.nvim'                    " LuaLS Neovim support
  " Plug 'sheerun/vim-polyglot'                  " Multilang support
  Plug 'fatih/vim-go'                          " Go for Vim
  Plug 'motus/pig.vim'                         " Apache Pig Latin .pig
  " Plug 'ElmCast/elm-vim'                       " Elm support
  " Plug 'neovimhaskell/haskell-vim'             " Haskell support
  " Plug 'tomlion/vim-solidity'                  " Solidity support
  " "Plug 'elzr/vim-json'                         " Better JSON support
  Plug 'LnL7/vim-nix'                          " Support for editting Nix files
  Plug 'mattn/emmet-vim'                       " Emmet for vim

  " Color Schemes Themes
  " "Plug 'vim-airline/vim-airline-themes'
  " "Plug 'altercation/vim-colors-solarized'
  " "Plug 'vim-scripts/chlordane.vim'
  " "Plug 'zeis/vim-kolor'
  " "Plug 'rakr/vim-two-firewatch'
  " "" Plug 'ajh17/Spacegray.vim'
  " "Plug 'dracula/vim'
  " "Plug 'trusktr/seti.vim'
  " "Plug 'gosukiwi/vim-atom-dark'
  " "Plug 'cocopon/iceberg.vim'
  " "Plug 'w0ng/vim-hybrid'
  " "Plug 'kristijanhusak/vim-hybrid-material'
  " "Plug 'morhetz/gruvbox'
  " "Plug 'sonph/onehalf', {'rtp': 'vim/'}
call plug#end()

" Required: (automatically done by Vim Plug)
filetype plugin indent on
" syntax enable

" =============================================================================
" End dein scripts
" =============================================================================
" Base Settings
" =============================================================================

"set hidden
"set noshowmode
"set lazyredraw
"set ttyfast
"set nocursorline
"set signcolumn=yes
"set ignorecase
"set smartcase
"set termguicolors
"let mapleader = "\<Space>"

" =============================================================================
" Base Mappings
" =============================================================================

" Terminal
tnoremap <C-[> <C-\><C-n>
autocmd TermOpen *:$SHELL,*:\$SHELL let g:zz_my_term = b:terminal_job_pid
autocmd TermClose *:$SHELL,*:\$SHELL unlet g:zz_my_term

function! g:ZzTerm()
  if !exists("g:zz_my_term")
    :term
  else
    let l:count = winnr('$')

    if l:count != 1
      :wincmd p
    endif

    execute 'b ' . g:zz_my_term . ': | startinsert'
  endif
endfunction

nnoremap <leader>sh :call g:ZzTerm()<CR>
inoremap ;q <Esc><C-u>:call g:ZzTerm()<CR>
nnoremap ;q :call g:ZzTerm()<CR>

function! LastFrame()
  let l:count = winnr('$')

  if l:count == 1
    :b#
  else
    :wincmd p
  endif
endfunction

tnoremap ;q <C-\><C-n>:call LastFrame()<CR>

" Movement mappings (colemak)
"nmap h <Up>
"nmap k <Down>
"nmap j <Left>
"vmap h <Up>
"vmap k <Down>
"vmap j <Left>
"nmap gj gk
"nmap gk gh
"vmap gj gk
"vmap gk gh

"noremap <C-w><C-k> <C-w><C-j>
"noremap <C-w><C-j> <C-w><C-h>
"noremap <C-w><C-h> <C-w><C-k>
"noremap <C-w>k <C-w>j
"noremap <C-w>j <C-w>h
"noremap <C-w>h <C-w>k

"nmap <leader>tr :e .<CR>
"nmap <leader>tt :Explore<CR>
""nmap <M-,> :e $MYVIMRC<CR>

"nmap <C-s> :update<CR>
"imap <C-s> <Esc>:update<CR>
" "inoremap <C-f> <Right>

" Buffers mappings
" nmap gb <C-^>
nmap ]b :bnext<CR>
nmap [b :bprevious<CR>
nmap ]B :blast<CR>
nmap [B :bfirst<CR>

map <C-a>d :q<CR>
" "map <Leader>qq :q <CR>
map <C-a>k :bdelete<CR>
" map <Leader>bk :bdelete<CR>
map <C-a>c :Bonly<CR>

" Paste from clipboard
inoremap <C-v> <C-r>+

" Move whole lines up or down (Bubble effect)
" Alt+j = ê   Alt+k = ë
nnoremap <C-k> :m+<CR>==
nnoremap <C-h> :m-2<CR>==
inoremap <C-k> <Esc>:m+<CR>==gi
inoremap <C-h> <Esc>:m-2<CR>==gi
vnoremap <C-k> :m'>+<CR>gv=gv
vnoremap <C-h> :m-2<CR>gv=gv

" Visually select last pasted or changed text
noremap gV `[v`]
noremap zv zt5

" Quit help with q
" autocmd FileType help noremap <buffer> q :q<CR>

" Netrw mappings
augroup netrw_mapping
    autocmd!
    autocmd filetype netrw call NetrwMapping()
augroup END

function! NetrwMapping()
    nmap <buffer> o <CR>
    nmap <buffer> gb <C-^>
    nmap <buffer> u -
    nmap <buffer> + d
endfunction

"" Git commit settings
"autocmd FileType gitcommit setlocal et ts=4 sw=4 sts=4
"
"" Golang settings
"autocmd FileType go setlocal noet ts=4 sw=4 sts=4
"
"" HTML settings
"autocmd FileType html setlocal et ts=2 sw=2 sts=2
"
"" JSON settings
"autocmd FileType json setlocal et ts=2 sw=2 sts=2
"
"" Ba[Sh]ell settings
"autocmd FileType sh setlocal et ts=4 sw=4 sts=4
"
"" Vimscript settings
"autocmd FileType vim setlocal et ts=2 sw=2 sts=2
"
"" Ruby settings
"autocmd FileType ruby setlocal et ts=2 sw=2 sts=2
"
"" Haskell settings
"autocmd FileType haskell setlocal et ts=2 sw=2 sts=2
"
"" PureScript settings
"autocmd FileType purescript setlocal et ts=2 sw=2 sts=2
"
"" SQL settings
"autocmd FileType sql setlocal et ts=4 sw=4 sts=4
"
"" Javascript settings
"autocmd FileType javascript setlocal et ts=2 sw=2 sts=2

" =============================================================================
" Plugins settings
" =============================================================================

" Ale
"let g:ale_sign_error = '•'
"let g:ale_sign_warning = '●'
"let g:ale_lint_on_text_changed = 'always'
"let g:ale_lint_delay = 500
"let g:ale_echo_msg_error_str = 'E'
"let g:ale_echo_msg_warning_str = 'W'
"let g:ale_echo_msg_format = '[%linter%] %s [%severity%]'
"
"let g:ale_linters = {
"      \   'rust': ['analyzer'],
"      \   'python': ['flake8', 'mypy'],
"      \ }
"let g:ale_fixers = {
"      \   '*': ['remove_trailing_lines', 'trim_whitespace'],
"      \   'rust': ['rustfmt'],
"      \   'python': ['autopep8', 'yapf', 'black', 'isort'],
"      \   'nix': ['nixfmt'],
"      \ }
"
"let g:ale_fix_on_save = 1
"
"nmap <silent> ]e <Plug>(ale_next_wrap)
"nmap <silent> [e <Plug>(ale_previous_wrap)

" Denite
"call denite#custom#var('file/rec', 'command',
"      \ ['rg', '--files', '--glob', '!.git', '--color', 'never'])
"
"call denite#custom#option('_', {
"              \ 'auto_resize': v:true,
"              \ 'winheight': 10,
"              \ 'highlight_matched_char' : 'Function',
"              \ 'highlight_matched_range' : 'Function'
"              \ })
"
"nnoremap <Leader>ls :Denite buffer<CR>
"noremap <C-p> :Denite -start-filter file/rec<CR>
"nnoremap <Leader><Space> :Denite -start-filter file/rec<CR>
"
"autocmd FileType denite call s:denite_my_settings()
"function! s:denite_my_settings() abort
"  nnoremap <silent><buffer><expr> <CR>
"  \ denite#do_map('do_action')
"  nnoremap <silent><buffer><expr> d
"  \ denite#do_map('do_action', 'delete')
"  nnoremap <silent><buffer><expr> p
"  \ denite#do_map('do_action', 'preview')
"  nnoremap <silent><buffer><expr> q
"  \ denite#do_map('quit')
"  nnoremap <silent><buffer><expr> i
"  \ denite#do_map('open_filter_buffer')
"  nnoremap <silent><buffer><expr> <Space>
"  \ denite#do_map('toggle_select').'j'
"endfunction
"
"autocmd FileType denite-filter call s:denite_filter_my_settings()
"function! s:denite_filter_my_settings() abort
"  inoremap <silent><buffer><expr> <C-k> denite#increment_parent_cursor(1)
"  inoremap <silent><buffer><expr> <C-h> denite#increment_parent_cursor(-1)
"  nnoremap <silent><buffer><expr> <C-k> denite#increment_parent_cursor(1)
"  nnoremap <silent><buffer><expr> <C-h> denite#increment_parent_cursor(-1)
"  inoremap <silent><buffer><expr> <CR> denite#do_map('do_action')
"  imap <silent><buffer> <Esc> <Plug>(denite_filter_quit)
"endfunction

" Echodoc
let g:echodoc#enable_at_startup = 1

" Deplete
" let g:deoplete#enable_at_startup = 1
" call deoplete#custom#option('max_list', 10)
" https://github.com/Shougo/deoplete.nvim/wiki/Completion-Sources
" https://github.com/padawan-php/deoplete-padawan
" https://github.com/tpope/vim-eunuch

" Don't show preview window on completion
set completeopt-=preview

" Airline
" "let g:loaded_airline = 1
" "let g:airline_powerline_fonts = 1
" "let g:airline#extensions#ale#enabled = 1
" "let g:airline#extensions#tabline#enabled = 1
" "let g:airline#extensions#tabline#fnamemod = ':t'

" Vim Sneak
"map f <Plug>Sneak_f
"map F <Plug>Sneak_F
"map t <Plug>Sneak_t
"map T <Plug>Sneak_T

" Goyo
"nmap <leader>cw :Goyo<CR>

" Delimitmate
"let g:delimitMate_expand_cr = 1
"imap <C-g>g <Plug>delimitMateS-Tab
"imap <C-g>l <Plug>delimitMateJumpMany
"autocmd FileType python let b:delimitMate_nesting_quotes = ['"']

" Emmet
"let g:user_emmet_leader_key='<C-e>'
"let g:user_emmet_install_global = 0
"autocmd FileType html,css EmmetInstall

" Git gutter
"let g:gitgutter_map_keys = 0

"nmap ]h <Plug>(GitGutterNextHunk)
"nmap [h <Plug>(GitGutterPrevHunk)
"nmap <Leader>ga <Plug>(GitGutterStageHunk)
"nmap <Leader>gr <Plug>(GitGutterUndoHunk)
"nmap <Leader>gp <Plug>(GitGutterPreviewHunk)
"omap ih <Plug>(GitGutterTextObjectInnerPending)
"omap ah <Plug>(GitGutterTextObjectOuterPending)
"xmap ih <Plug>(GitGutterTextObjectInnerVisual)
"xmap ah <Plug>(GitGutterTextObjectOuterVisual)

" Gina
"nnoremap <leader>gs :Gina status --opener=tabedit<CR>
"nnoremap <leader>gg :Gina status --opener=tabedit<CR>
" nnoremap <leader>gw :Gwrite<CR>
"nnoremap <leader>gc :Gina commit<CR>
"nnoremap <leader>gl :Gina log --opener=tabedit<CR>
" nnoremap <leader>go :Git checkout<Space>
" nnoremap <leader>gpl :Dispatch! git pull<Space>
" nnoremap <leader>gps :Dispatch! git push<Space>
" nnoremap <leader>gb :Gbrowse<CR>
"call gina#custom#execute('commit', 'setlocal spell')
"call gina#custom#mapping#nmap('log', 'q', ':<C-u>bdelete<CR>', {'noremap': 1, 'silent': 1})
"call gina#custom#mapping#nmap('status', 'q', ':<C-u>bdelete<CR>', {'noremap': 1, 'silent': 1})
"call gina#custom#mapping#nmap('status', 'cc', ':<C-u>Gina commit<CR>', {'noremap': 1, 'silent': 1})
"call gina#custom#mapping#nmap('status', 'ca', ':<C-u>Gina commit --amend<CR>', {'noremap': 1, 'silent': 1})
"call gina#custom#mapping#imap('commit', '<C-c><C-c>', '<Esc>:<C-u>wq<CR>', {'noremap': 1, 'silent': 1})
"call gina#custom#mapping#imap('commit', '<C-s>', '<Esc>:<C-u>wq<CR>', {'noremap': 1, 'silent': 1})
"call gina#custom#mapping#nmap('commit', '<C-s>', ':<C-u>wq<CR>', {'noremap': 1, 'silent': 1})
"call gina#custom#mapping#nmap('status', 's', '<<')
"call gina#custom#mapping#nmap('status', 'u', '>>')

" Commitia
"let g:committia_hooks = {}
"function! g:committia_hooks.edit_open(info)
"  setlocal spell
"
"  " If no commit message, start with insert mode
"  if a:info.vcs ==# 'git' && getline(1) ==# ''
"    normal O
"    startinsert
"  end
"
"  " Scroll the diff window from insert mode
"  imap <buffer><C-d> <Plug>(committia-scroll-diff-down-half)
"  imap <buffer><C-u> <Plug>(committia-scroll-diff-up-half)
"
"  " Commit with <C-s> and <C-c><C-c>
"  inoremap <buffer><C-s> <Esc>:<C-u>wq<CR>
"  inoremap <buffer><C-c><C-c> <Esc><C-u>wq<CR>
"  nnoremap <buffer><C-s> :<C-u>wq<CR>
"  nnoremap <buffer><C-c><C-c> :<C-u>wq<CR>
"endfunction

" Elm support
"let g:elm_setup_keybindings = 0
"let g:elm_format_autosave = 1

" PureScript support
"let purescript_indent_where = 2
"let purescript_indent_case = 2

" Ultisnips
let g:UltiSnipsSnippetsDir = "~/.config/nvim/ultisnips"
let g:UltiSnipsExpandTrigger = "<Nop>"
let g:UltiSnipsJumpForwardTrigger = "<Nop>"
let g:UltiSnipsJumpBackwardTrigger = "<Nop>"
let g:UltiSnipsEditSplit = "vertical"

" Integration of Deoplete and UltiSnips both on <Tab> and <S-Tab>
" function! g:SmartTab()
"   if pumvisible()
"     call UltiSnips#ExpandSnippetOrJump()
"     if g:ulti_expand_or_jump_res == 0
"       return "\<C-n>"
"     else
"       return ''
"     endif
"   else
"     call UltiSnips#ExpandSnippetOrJump()
"     if g:ulti_expand_or_jump_res == 0
"       return "\<Tab>"
"     else
"       return ''
"     endif
"   endif
" endfunction
"
" function! g:SmartShiftTab()
"   if pumvisible()
"     call UltiSnips#JumpBackwards()
"     if g:ulti_jump_backwards_res == 0
"       return "\<C-p>"
"     else
"       return ''
"     endif
"   else
"     call UltiSnips#JumpBackwards()
"     if g:ulti_expand_or_jump_res == 0
"       return "\<S-Tab>"
"     else
"       return ''
"     endif
"   endif
" endfunction

" inoremap <silent> <Tab> <C-R>=g:SmartTab()<CR>
" snoremap <silent> <Tab> <Esc>:call g:SmartTab()<CR>
" inoremap <silent> <S-Tab> <C-R>=g:SmartShiftTab()<CR>
" snoremap <silent> <S-Tab> <Esc>:call g:SmartShiftTab()<CR>


" =============================================================================
" Appearance settings
" =============================================================================

" "set list
" "set background=dark
" "let g:airline_theme='dracula'
" "color iceberg
" "" color spacegray
