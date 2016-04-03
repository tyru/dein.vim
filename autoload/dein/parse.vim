"=============================================================================
" FILE: parse.vim
" AUTHOR:  Shougo Matsushita <Shougo.Matsu at gmail.com>
" License: MIT license
"=============================================================================

" Global options definition." "{{{
let g:dein#enable_name_conversion =
      \ get(g:, 'dein#enable_name_conversion', 0)
"}}}

let s:git = dein#types#git#define()

function! dein#parse#_add(repo, options) abort "{{{
  let plugin = dein#parse#_dict(
        \ dein#parse#_init(a:repo, a:options))
  if (has_key(g:dein#_plugins, plugin.name)
        \ && g:dein#_plugins[plugin.name].sourced)
        \ || !get(plugin, 'if', 1)
    " Skip already loaded or not enabled plugin.
    return {}
  endif

  let g:dein#_plugins[plugin.name] = plugin
  if has_key(plugin, 'hook_add')
    try
      execute plugin.hook_add
    catch
      call dein#util#_error(
            \ 'Error occurred while executing hook: ' . plugin.name)
      call dein#util#_error(v:exception)
    endtry
  endif
  return plugin
endfunction"}}}
function! dein#parse#_init(repo, options) abort "{{{
  let plugin = s:git.init(a:repo, a:options)
  if empty(plugin)
    let plugin.type = 'none'
    let plugin.local = 1
  endif
  let plugin.repo = a:repo
  if !empty(a:options)
    let plugin.orig_opts = deepcopy(a:options)
  endif
  return extend(plugin, a:options)
endfunction"}}}
function! dein#parse#_dict(plugin) abort "{{{
  let plugin = {
        \ 'rev': '',
        \ 'local': 0,
        \ 'depends': [],
        \ 'on_cmd': [],
        \ 'on_map': [],
        \ 'on_path': [],
        \ 'on_source': [],
        \
        \ 'type': 'none',
        \ 'uri': '',
        \ 'rtp': '',
        \ 'sourced': 0,
        \ }
  call extend(plugin, a:plugin)

  if !has_key(plugin, 'name')
    let plugin.name = dein#parse#_name_conversion(plugin.repo)
  endif

  if !has_key(plugin, 'normalized_name')
    let plugin.normalized_name = substitute(
          \ fnamemodify(plugin.name, ':r'),
          \ '\c^n\?vim[_-]\|[_-]n\?vim$', '', 'g')
  endif

  if !has_key(a:plugin, 'name') && g:dein#enable_name_conversion
    " Use normalized name.
    let plugin.name = plugin.normalized_name
  endif

  if !has_key(plugin, 'path')
    let plugin.path = (plugin.local && plugin.repo =~# '^/\|^\a:[/\\]') ?
          \ plugin.repo : dein#util#_get_base_path().'/repos/'.plugin.name
  endif
  if get(plugin, 'rev') != ''
    let plugin.path .= '_' . substitute(plugin.rev,
          \ '[^[:alnum:]_-]', '_', 'g')
  endif
  let plugin.path = dein#util#_chomp(plugin.path)

  " Check relative path
  if (!has_key(a:plugin, 'rtp') || a:plugin.rtp != '')
        \ && plugin.rtp !~ '^\%([~/]\|\a\+:\)'
    let plugin.rtp = plugin.path.'/'.plugin.rtp
  endif
  if plugin.rtp[0:] == '~'
    let plugin.rtp = dein#util#_expand(plugin.rtp)
  endif
  let plugin.rtp = dein#util#_chomp(plugin.rtp)

  " Auto convert2list.
  for key in filter([
        \ 'on_ft', 'on_path', 'on_cmd',
        \ 'on_func', 'on_map', 'on_source',
        \ ], "has_key(plugin, v:val) && type(plugin[v:val]) != type([])
        \")
    let plugin[key] = [plugin[key]]
  endfor

  if !has_key(a:plugin, 'lazy')
    let plugin.lazy =
          \ get(plugin, 'on_i', 0) || get(plugin, 'on_idle', 0)
          \ || has_key(plugin, 'on_ft')
          \ || !empty(plugin.on_cmd)
          \ || has_key(plugin, 'on_func')
          \ || !empty(plugin.on_map)
          \ || !empty(plugin.on_path)
          \ || !empty(plugin.on_source)
  endif

  if !has_key(a:plugin, 'merged')
    let plugin.merged =
          \ !plugin.lazy && !plugin.local && !has_key(a:plugin, 'if')
          \ && stridx(plugin.rtp, dein#util#_get_base_path()) == 0
  endif

  if has_key(a:plugin, 'if') && type(a:plugin.if) == type('')
    sandbox let plugin.if = eval(a:plugin.if)
  endif

  if has_key(a:plugin, 'depends')
    let plugin.depends = dein#util#_convert2list(a:plugin.depends)
  endif

  " Hooks
  let pattern = '\n\s*\\\|\%(^\|\n\)\s*"[^\n]*'
  if has_key(plugin, 'hook_add')
    let plugin.hook_add = substitute(
          \ plugin.hook_add, pattern, '', 'g')
  endif
  if has_key(plugin, 'hook_source')
    let plugin.hook_source = substitute(
          \ plugin.hook_source, pattern, '', 'g')
  endif
  if has_key(plugin, 'hook_post_source')
    let plugin.hook_post_source = substitute(
          \ plugin.hook_post_source, pattern, '', 'g')
  endif
  if has_key(plugin, 'hook_post_update')
    let plugin.hook_post_update = substitute(
          \ plugin.hook_post_update, pattern, '', 'g')
  endif

  if plugin.lazy
    if !empty(plugin.on_cmd)
      call s:generate_dummy_commands(plugin)
    endif
    if !empty(plugin.on_map)
      call s:generate_dummy_mappings(plugin)
    endif
  endif

  return plugin
endfunction"}}}
function! dein#parse#_load_toml(filename, default) abort "{{{
  try
    let toml = dein#toml#parse_file(dein#util#_expand(a:filename))
  catch /vital: Text.TOML:/
    call dein#util#_error('Invalid toml format: ' . a:filename)
    call dein#util#_error(v:exception)
    return 1
  endtry
  if type(toml) != type({}) || !has_key(toml, 'plugins')
    call dein#util#_error('Invalid toml file: ' . a:filename)
    return 1
  endif

  " Parse.
  for plugin in toml.plugins
    if !has_key(plugin, 'repo')
      call dein#util#_error('No repository plugin data: ' . a:filename)
      return 1
    endif

    let options = extend(plugin, a:default, 'keep')
    call dein#add(plugin.repo, options)
  endfor
endfunction"}}}
function! dein#parse#_plugins2toml(plugins) abort "{{{
  let toml = []

  let default = dein#parse#_dict(dein#parse#_init('', {}))
  let default.if = ''
  let default.frozen = 0
  let default.on_i = 0
  let default.on_idle = 0
  let default.on_ft = []
  let default.on_cmd = []
  let default.on_func = []
  let default.on_map = []
  let default.on_path = []
  let default.on_source = []
  let default.build = ''
  let default.hook_add = ''
  let default.hook_source = ''
  let default.hook_post_source = ''
  let default.hook_post_update = ''

  let skip_default = {
        \ 'type': 1,
        \ 'path': 1,
        \ 'uri': 1,
        \ 'rtp': 1,
        \ 'sourced': 1,
        \ 'orig_opts': 1,
        \ 'repo': 1,
        \ }

  for plugin in dein#util#_sort_by(a:plugins, 'v:val.repo')
    let toml += ['[[plugins]]',
          \ 'repo = ' . string(plugin.repo)]

    for key in filter(sort(keys(default)),
          \ "!has_key(skip_default, v:val)
          \      && has_key(plugin, v:val)
          \      && plugin[v:val] !=# default[v:val]")
      let val = plugin[key]
      if key =~ '^hook_'
        let toml += [
              \ ]
        call add(toml, key . " = '''")
        let toml += split(val, '\n')
        call add(toml, "'''")
      else
        call add(toml, key . ' = ' . string(
              \ (type(val) == type([]) && len(val) == 1) ? val[0] : val))
      endif
      unlet! val
    endfor

    call add(toml, '')
  endfor

  return toml
endfunction"}}}
function! dein#parse#_load_dict(dict, default) abort "{{{
  for [repo, options] in items(a:dict)
    call dein#add(repo, extend(copy(options), a:default, 'keep'))
  endfor
endfunction"}}}
function! dein#parse#_local(localdir, options, includes) abort "{{{
  let base = fnamemodify(dein#util#_expand(a:localdir), ':p')
  let directories = []
  for glob in a:includes
    let directories += map(filter(dein#util#_globlist(base . glob),
          \ "isdirectory(v:val)"), "
          \ substitute(dein#util#_substitute_path(
          \   fnamemodify(v:val, ':p')), '/$', '', '')")
  endfor

  for dir in dein#util#_uniq(directories)
    let options = extend({ 'local': 1, 'path': dir,
          \ 'name': fnamemodify(dir, ':t') }, a:options)

    let plugin = dein#get(options.name)
    if !empty(plugin)
      if plugin.sourced
        " Ignore already sourced plugins
        continue
      endif

      if has_key(plugin, 'orig_opts')
        call extend(options, copy(plugin.orig_opts), 'keep')
      endif
    endif

    call dein#add(dir, options)
  endfor
endfunction"}}}
function! s:generate_dummy_commands(plugin) abort "{{{
  let a:plugin.dummy_commands = []
  for name in a:plugin.on_cmd
    " Define dummy commands.
    let raw_cmd = 'command '
          \ . '-complete=customlist,dein#autoload#_dummy_complete'
          \ . ' -bang -bar -range -nargs=* '. name
          \ . printf(" call dein#autoload#_on_cmd(%s, %s, <q-args>,
          \  expand('<bang>'), expand('<line1>'), expand('<line2>'))",
          \   string(name), string(a:plugin.name))

    call add(a:plugin.dummy_commands, [name, raw_cmd])
    silent! execute raw_cmd
  endfor
endfunction"}}}
function! s:generate_dummy_mappings(plugin) abort "{{{
  let a:plugin.dummy_mappings = []
  for [modes, mappings] in map(copy(a:plugin.on_map), "
        \   type(v:val) == type([]) ?
        \     [split(v:val[0], '\\zs'), v:val[1:]] :
        \     [['n', 'x', 'o'], [v:val]]
        \ ")
    if mappings ==# ['<Plug>']
      " Use plugin name.
      let mappings = ['<Plug>(' . a:plugin.normalized_name]
      if stridx(a:plugin.normalized_name, '-') >= 0
        " The plugin mappings may use "_" instead of "-".
        call add(mappings, '<Plug>(' .
              \ substitute(a:plugin.normalized_name, '-', '_', 'g'))
      endif
    endif

    for mapping in mappings
      " Define dummy mappings.
      let prefix = printf("dein#autoload#_on_map(%s, %s,",
            \ string(substitute(mapping, '<', '<lt>', 'g')),
            \ string(a:plugin.name))
      for mode in modes
        let raw_map = mode.'noremap <unique><silent> '.mapping
            \ . (mode ==# 'c' ? " \<C-r>=" :
            \    mode ==# 'i' ? " \<C-o>:call " : " :\<C-u>call ") . prefix
            \ . string(mode) . ")<CR>"
        call add(a:plugin.dummy_mappings, [mode, mapping, raw_map])
        silent! execute raw_map
      endfor
    endfor
  endfor
endfunction"}}}

function! dein#parse#_name_conversion(path) abort "{{{
  return fnamemodify(get(split(a:path, ':'), -1, ''),
        \ ':s?/$??:t:s?\c\.git\s*$??')
endfunction"}}}

" vim: foldmethod=marker
