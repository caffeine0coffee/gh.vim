" https://github.com/prabirshrestha/quickpick.vim#UNKNOWN
"    :QuickpickEmbed path=./autoload/gh/provider/quickpick.vim namespace=gh#provider#quickpick prefix=gh-quickfix

let s:has_timer = exists('*timer_start') && exists('*timer_stop')
let s:has_matchfuzzy = exists('*matchfuzzy')
let s:has_matchfuzzypos = exists('*matchfuzzypos')
let s:has_proptype = exists('*prop_type_add') && exists('*prop_type_delete')

sign define gh_select text=>> texthl=Search

function! gh#provider#quickpick#open(opt) abort
  call gh#provider#quickpick#close() " hide existing picker if exists

  " when key is empty, item is a string else it is a dict
  " fitems is filtered items and is the item that is filtered
  let s:state = extend({
      \ 'items': [],
      \ 'highlights': [],
      \ 'fitems': [],
      \ 'key': '',
      \ 'busy': 0,
      \ 'busyframes': ['-', '\', '|', '/'],
      \ 'filetype': 'gh-quickfix',
      \ 'promptfiletype': 'gh-quickfix-filter',
      \ 'input': '',
      \ 'maxheight': 10,
      \ 'debounce': 250,
      \ 'filter': 1,
      \ 'multi_select': 0,
      \ 'selected_fitems': [],
      \ }, a:opt)

  let s:inputecharpre = 0
  let s:state['busyframe'] = 0

  let s:state['bufnr'] = bufnr('%')
  let s:state['winid'] = win_getid()

  " create result buffer
  exe printf('keepalt botright 1new %s', s:state['filetype'])
  let s:state['resultsbufnr'] = bufnr('%')
  let s:state['resultswinid'] = win_getid()
  if s:has_proptype
    call prop_type_add('highlight', { 'highlight': 'Directory', 'bufnr': s:state['resultsbufnr'] })
  endif

  " create prompt buffer
  exe printf('keepalt botright 1new %s', s:state['promptfiletype'])
  let s:state['promptbufnr'] = bufnr('%')
  let s:state['promptwinid'] = win_getid()

  call win_gotoid(s:state['resultswinid'])
  call s:set_buffer_options()
  setlocal cursorline
  call s:update_items()
  exec printf('setlocal filetype=' . s:state['filetype'])
  call s:notify('open', { 'bufnr': s:state['bufnr'], 'winid': s:state['winid'] , 'resultsbufnr': s:state['resultsbufnr'], 'resultswinid': s:state['resultswinid'] })

  call win_gotoid(s:state['promptwinid'])
  call s:set_buffer_options()
  call setline(1, s:state['input'])

  " map keys
  inoremap <buffer><silent> <Plug>(gh-quickfix-accept) <ESC>:<C-u>call <SID>on_accept()<CR>
  nnoremap <buffer><silent> <Plug>(gh-quickfix-accept) :<C-u>call <SID>on_accept()<CR>

  inoremap <buffer><silent> <Plug>(gh-quickfix-close) <ESC>:<C-u>call gh#provider#quickpick#close()<CR>
  nnoremap <buffer><silent> <Plug>(gh-quickfix-close) :<C-u>call gh#provider#quickpick#close()<CR>

  inoremap <buffer><silent> <Plug>(gh-quickfix-cancel) <ESC>:<C-u>call <SID>on_cancel()<CR>
  nnoremap <buffer><silent> <Plug>(gh-quickfix-cancel) :<C-u>call <SID>on_cancel()<CR>

  inoremap <buffer><silent> <Plug>(gh-quickfix-move-next) <ESC>:<C-u>call <SID>on_move_next(1)<CR>
  nnoremap <buffer><silent> <Plug>(gh-quickfix-move-next) :<C-u>call <SID>on_move_next(0)<CR>

  inoremap <buffer><silent> <Plug>(gh-quickfix-move-previous) <ESC>:<C-u>call <SID>on_move_previous(1)<CR>
  nnoremap <buffer><silent> <Plug>(gh-quickfix-move-previous) :<C-u>call <SID>on_move_previous(0)<CR>

  if s:state['multi_select']
    inoremap <buffer><silent> <Plug>(gh-quickfix-select) <Esc>:<C-u>call <SID>on_select(1)<CR>
    nnoremap <buffer><silent> <Plug>(gh-quickfix-select) :<C-u>call <SID>on_select(0)<CR>
    if !hasmapto('<Plug>(gh-quickfix-select)')
      imap <buffer><C-i> <Plug>(gh-quickfix-select)
      "nmap <buffer><C-i> <Plug>(gh-quickfix-select)
    endif
  endif

  exec printf('setlocal filetype=' . s:state['promptfiletype'])

  if !hasmapto('<Plug>(gh-quickfix-accept)')
    imap <buffer><cr> <Plug>(gh-quickfix-accept)
    "nmap <buffer><cr> <Plug>(gh-quickfix-accept)
  endif

  if !hasmapto('<Plug>(gh-quickfix-cancel)')
    imap <silent> <buffer> <C-c> <Plug>(gh-quickfix-cancel)
    map  <silent> <buffer> <C-c> <Plug>(gh-quickfix-cancel)
    imap <silent> <buffer> <Esc> <Plug>(gh-quickfix-cancel)
    map  <silent> <buffer> <Esc> <Plug>(gh-quickfix-cancel)
  endif

  if !hasmapto('<Plug>(gh-quickfix-move-next)')
    imap <silent> <buffer> <C-n> <Plug>(gh-quickfix-move-next)
    "nmap <silent> <buffer> <C-n> <Plug>(gh-quickfix-move-next)
    imap <silent> <buffer> <C-j> <Plug>(gh-quickfix-move-next)
    "nmap <silent> <buffer> <C-j> <Plug>(gh-quickfix-move-next)
  endif

  if !hasmapto('<Plug>(gh-quickfix-move-previous)')
    imap <silent> <buffer> <C-p> <Plug>(gh-quickfix-move-previous)
    "nmap <silent> <buffer> <C-p> <Plug>(gh-quickfix-move-previous)
    imap <silent> <buffer> <C-k> <Plug>(gh-quickfix-move-previous)
    "nmap <silent> <buffer> <C-k> <Plug>(gh-quickfix-move-previous)
  endif

  call cursor(line('$'), 0)
  call feedkeys('i', 'n')

  augroup gh#provider#quickpick
    autocmd!
    autocmd InsertCharPre   <buffer> call s:on_insertcharpre()
    autocmd TextChangedI    <buffer> call s:on_inputchanged()
    autocmd InsertEnter     <buffer> call s:on_insertenter()
    autocmd InsertLeave     <buffer> call s:on_insertleave()

    if exists('##TextChangedP')
      autocmd TextChangedP  <buffer> call s:on_inputchanged()
    endif
  augroup END

  call s:notify_items()
  call s:notify_selection()
  call gh#provider#quickpick#busy(s:state['busy'])
endfunction

function! s:on_select(insertmode) abort
  if win_gotoid(s:state['resultswinid'])
    let l:index = line('.') - 1 " line is 1 index, list is 0 index
    let l:item = [s:state['fitems'][l:index]][0]
    let l:items = s:state['selected_fitems']
    let l:idx = -1
    for i in range(len(l:items))
      if toupper(item) is# toupper(l:items[i])
        let l:idx = i
        break
      endif
    endfor
    if l:idx != -1
      call remove(l:items, l:idx)
    else
      call add(l:items, l:item)
    endif
    let pos = getcurpos()
    call s:update_items()
    call setpos('.', pos)
    call win_gotoid(s:state['promptwinid'])
    call s:on_move_next(a:insertmode)
  endif
endfunction

function! s:set_buffer_options() abort
  " set buffer options
  abc <buffer>
  setlocal bufhidden=unload           " unload buf when no longer displayed
  setlocal buftype=nofile             " buffer is not related to any file<Paste>
  setlocal noswapfile                 " don't create swap file
  setlocal nowrap                     " don't soft-wrap
  setlocal nonumber                   " don't show line numbers
  setlocal nolist                     " don't use list mode (visible tabs etc)
  setlocal foldcolumn=0               " don't show a fold column at side
  setlocal foldlevel=99               " don't fold anything
  setlocal nospell                    " spell checking off
  setlocal nobuflisted                " don't show up in the buffer list
  setlocal textwidth=0                " don't hardwarp (break long lines)
  setlocal nocursorline               " highlight the line cursor is off
  setlocal nocursorcolumn             " disable cursor column
  setlocal noundofile                 " don't enable undo
  setlocal winfixheight
  if exists('+colorcolumn') | setlocal colorcolumn=0 | endif
  if exists('+relativenumber') | setlocal norelativenumber | endif
  setlocal signcolumn=yes             " for prompt
endfunction

function! gh#provider#quickpick#close() abort
  if !exists('s:state')
    return
  endif

  call gh#provider#quickpick#busy(0)

  call win_gotoid(s:state['bufnr'])
  call s:notify('close', { 'bufnr': s:state['bufnr'], 'winid': s:state['winid'], 'resultsbufnr': s:state['resultsbufnr'], 'resultswinid': s:state['winid'] })

  augroup gh#provider#quickpick
    autocmd!
  augroup END

  exe 'silent! bunload! ' . s:state['promptbufnr']
  exe 'silent! bunload! ' . s:state['resultsbufnr']

  let s:inputecharpre = 0

  unlet s:state
endfunction

function! gh#provider#quickpick#items(items) abort
  let s:state['items'] = a:items
  call s:update_items()
  call s:notify_items()
  call s:notify_selection()
endfunction

function! gh#provider#quickpick#busy(busy) abort
  let s:state['busy'] = a:busy
  if a:busy
    if !has_key(s:state, 'busytimer')
      let s:state['busyframe'] = 0
      let s:state['busytimer'] = timer_start(60, function('s:busy_tick'), { 'repeat': -1 })
    endif
  else
    if has_key(s:state, 'busytimer')
      call timer_stop(s:state['busytimer'])
      call remove(s:state, 'busytimer')
      redraw
      echohl None
      echo ''
    endif
  endif
endfunction

function! s:busy_tick(...) abort
  let s:state['busyframe'] = s:state['busyframe'] + 1
  if s:state['busyframe'] >= len(s:state['busyframes'])
    let s:state['busyframe'] = 0
  endif
  redraw
  echohl Question | echon s:state['busyframes'][s:state['busyframe']]
  echohl None
endfunction

function! s:update_items() abort
  call s:win_execute(s:state['resultswinid'], 'silent! %delete')

  let s:state['highlights'] = []

  if s:state['filter'] " if filter is enabled
    if empty(s:trim(s:state['input']))
      let s:state['fitems'] = s:state['items']
    else
      if empty(s:state['key']) " item is string
        if s:has_matchfuzzypos
          let l:matchfuzzyresult = matchfuzzypos(s:state['items'], s:state['input'])
          let l:fitems = l:matchfuzzyresult[0]
          let l:highlights = l:matchfuzzyresult[1]
          let s:state['fitems'] = l:fitems
          let s:state['highlights'] = l:highlights
        elseif s:has_matchfuzzy
          let s:state['fitems'] = matchfuzzy(s:state['items'], s:state['input'])
        else
          let s:state['fitems'] = filter(copy(s:state['items']), 'stridx(toupper(v:val), toupper(s:state["input"])) >= 0')
        endif
      else " item is dict
        if s:has_matchfuzzypos
          " vim requires matchfuzzypos to have highlights.
          " matchfuzzy only patch doesn't support dict search
          let l:matchfuzzyresult = matchfuzzypos(s:state['items'], s:state['input'], { 'key': s:state['key'] })
          let l:fitems = l:matchfuzzyresult[0]
          let l:highlights = l:matchfuzzyresult[1]
          let s:state['fitems'] = l:fitems
          let s:state['highlights'] = l:highlights
        else
          let s:state['fitems'] = filter(copy(s:state['items']), 'stridx(toupper(v:val[s:state["key"]]), toupper(s:state["input"])) >= 0')
        endif
      endif
    endif
  else " if filter is disabled
    let s:state['fitems'] = s:state['items']
  endif


  if empty(s:state['key']) " item is string
    let l:lines = s:state['fitems']
  else " item is dict
    let l:lines = map(copy(s:state['fitems']), 'v:val[s:state["key"]]')
  endif

  call setbufline(s:state['resultsbufnr'], 1, l:lines)

  if s:has_proptype && !empty(s:state['highlights'])
    let l:i = 0
    for l:line in s:state['highlights']
      for l:pos in l:line
        let l:cs = split(getbufline(s:state['resultsbufnr'], l:i + 1)[0], '\zs')
        let l:mpos = strlen(join(l:cs[: l:pos - 1], ''))
        let l:len =  strlen(l:cs[l:pos])
        call prop_add(l:i + 1, l:mpos + 1, { 'length': l:len, 'type': 'highlight', 'bufnr': s:state['resultsbufnr'] })
      endfor
      let l:i += 1
    endfor
  endif

  " update sign
  call s:update_sign()

  call s:win_execute(s:state['resultswinid'], printf('resize %d', min([len(s:state['fitems']), s:state['maxheight']])))
  call s:win_execute(s:state['promptwinid'], 'resize 1')
endfunction

function! s:update_sign() abort
  let oldwin = win_getid()
  let resultwin = s:state['resultswinid']

  call win_gotoid(resultwin)
  sign unplace * group=gh-quickpick

  let lines = getline(0, '$')
  let fitems = {}
  for idx in range(len(lines))
    let fitems[idx+1] = lines[idx]
  endfor

  for select in s:state['selected_fitems']
    for [idx, item] in items(fitems)
      if toupper(item) is# toupper(select)
        exe printf('sign place %d group=gh-quickpick line=%d name=gh_select file=%s', idx, idx, expand("%:p"))
        continue
      endif
    endfor
  endfor

  call win_gotoid(oldwin)
endfunction

function! s:on_accept() abort
  if win_gotoid(s:state['resultswinid'])
    if s:state['multi_select'] is# 0 || empty(s:state['selected_fitems'])
      let l:index = line('.') - 1 " line is 1 index, list is 0 index
      if l:index < 0
        let l:items = []
      else
        let l:items = [s:state['fitems'][l:index]]
      endif
    else
      let l:items = s:state['selected_fitems']
    endif
    call win_gotoid(s:state['winid'])
    call s:notify('accept', { 'items': l:items })
  end
endfunction

function! s:on_cancel() abort
  call win_gotoid(s:state['winid'])
  call s:notify('cancel', {})
  call gh#provider#quickpick#close()
endfunction

function! s:on_move_next(insertmode) abort
  let l:col = col('.')
  call s:win_execute(s:state['resultswinid'], 'normal! j')
  if a:insertmode
    call s:win_execute(s:state['promptwinid'], 'startinsert | call setpos(".", [0, 1, ' . (l:col + 1) .', 1])')
  endif
  call s:notify_selection()
endfunction

function! s:on_move_previous(insertmode) abort
  let l:col = col('.')
  call s:win_execute(s:state['resultswinid'], 'normal! k')
  if a:insertmode
    call s:win_execute(s:state['promptwinid'], 'startinsert | call setpos(".", [0, 1, ' . (l:col + 1) .', 1])')
  endif
  call s:notify_selection()
endfunction

function! s:notify_items() abort
  " items could be huge, so don't send the items as part of data
  call s:notify('items', { 'bufnr': s:state['bufnr'], 'winid': s:state['winid'], 'resultsbufnr': s:state['resultsbufnr'], 'resultswinid': s:state['resultswinid'] })
endfunction

function! s:notify_selection() abort
  let l:original_winid = win_getid()
  call win_gotoid(s:state['resultswinid'])
  let l:index = line('.') - 1 " line is 1 based, list is 0 based
  if l:index < 0 || ((l:index + 1) > len(s:state['fitems']))
    let l:items = []
  else
    let l:items = [s:state['fitems'][l:index]]
  endif
  let l:data = {
    \ 'bufnr': s:state['bufnr'],
    \ 'winid': s:state['winid'],
    \ 'resultsbufnr': s:state['resultsbufnr'],
    \ 'resultswinid': s:state['resultswinid'],
    \ 'items': l:items,
    \ }
  call win_gotoid(s:state['winid'])
  call s:notify('selection', l:data)
  call win_gotoid(l:original_winid)
endfunction

function! s:on_inputchanged() abort
  if s:inputecharpre
    if s:has_timer && s:state['debounce'] > 0
      call s:debounce_onchange()
    else
      call s:notify_onchange()
    endif
  endif
endfunction

function! s:on_insertcharpre() abort
  let s:inputecharpre = 1
endfunction

function! s:on_insertenter() abort
  let s:inputecharpre = 0
endfunction

function! s:on_insertleave() abort
  if s:has_timer && has_key(s:state, 'debounce_onchange_timer')
    call timer_stop(s:state['debounce_onchange_timer'])
    call remove(s:state, 'debounce_onchange_timer')
  endif
endfunction

function! s:debounce_onchange() abort
  if has_key(s:state, 'debounce_onchange_timer')
    call timer_stop(s:state['debounce_onchange_timer'])
    call remove(s:state, 'debounce_onchange_timer')
  endif
  let s:state['debounce_onchange_timer'] = timer_start(s:state['debounce'], function('s:notify_onchange'))
endfunction

function! s:notify_onchange(...) abort
  let s:state['input'] = getbufline(s:state['promptbufnr'], 1)[0]
  call s:notify('change', { 'input': s:state['input'] })
  if s:state['filter']
    call s:update_items()
    call s:notify_selection()
  endif
endfunction

function! s:notify(name, data) abort
  if has_key(s:state, 'on_event') | call s:state['on_event'](a:data, a:name) | endif
  if has_key(s:state, 'on_' . a:name) | call s:state['on_' . a:name](a:data, a:name) | endif
endfunction

if exists('*win_execute')
  function! s:win_execute(win_id, cmd) abort
    call win_execute(a:win_id, a:cmd)
  endfunction
else
  function! s:win_execute(winid, cmd) abort
    let l:original_winid = win_getid()
    if l:original_winid == a:winid
      exec a:cmd
    else
      if win_gotoid(a:winid)
        exec a:cmd
        call win_gotoid(l:original_winid)
      end
    endif
  endfunction
endif

if exists('*trim')
  function! s:trim(str) abort
    return trim(a:str)
  endfunction
else
  function! s:trim(str) abort
    return substitute(a:string, '^\s*\|\s*$', '', 'g')
  endfunction
endif

function! gh#provider#quickpick#on_change(data, name, items) abort
  if empty(a:data['input'])
    call gh#provider#quickpick#items(a:items)
  else
    if exists('*matchfuzzy')
      let l:items = matchfuzzy(a:items, a:data['input'])
    else
      let l:items = filter(copy(a:items), 'stridx(toupper(v:val), toupper(a:data["input"])) >= 0')
    endif
    call gh#provider#quickpick#items(l:items)
  endif
endfunction
