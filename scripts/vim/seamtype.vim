" Tells Seamtype which mode Vim is in, so that in an app whose Esc key is set to "Vim" every
" normal-mode key goes straight to Vim and words are decided only in insert mode.
" Put this file in ~/.vim/plugin/ (Vim 8.2 or later, with +job). Neovim: seamtype.lua.
if exists('g:loaded_seamtype') || !has('job') || has('nvim')
  finish
endif
let g:loaded_seamtype = 1

let s:seamtype = ''
for s:dir in [expand('~/Library/Input Methods'), '/Library/Input Methods']
  if executable(s:dir . '/Seamtype.app/Contents/MacOS/Seamtype')
    let s:seamtype = s:dir . '/Seamtype.app/Contents/MacOS/Seamtype'
    break
  endif
endfor
if empty(s:seamtype)
  finish
endif

function! s:Tell(mode) abort
  " Not stopped when Vim exits, so the last word still goes out when quitting.
  call job_start([s:seamtype, '--vim', a:mode], {'stoponexit': ''})
endfunction

function! s:Current() abort
  return mode() =~# '^[iR]' ? 'insert' : 'normal'
endfunction

augroup Seamtype
  autocmd!
  autocmd InsertEnter * call s:Tell('insert')
  autocmd InsertLeave,VimEnter * call s:Tell('normal')
  autocmd FocusGained * call s:Tell(s:Current())
  " Whatever is in front next (a shell in another pane) isn't Vim.
  autocmd VimLeavePre,FocusLost * call s:Tell('off')
  if exists('##VimResume')
    autocmd VimResume * call s:Tell('normal')
    autocmd VimSuspend * call s:Tell('off')
  endif
augroup END
