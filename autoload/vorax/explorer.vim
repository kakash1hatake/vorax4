" File:        autoload/vorax/explorer.vim
" Author:      Alexandru Tică
" Description: Provides DB object explore features.
" License:     see LICENSE.txt

" Define the dbexplorer tree
let s:tree = vorax#tree#New(
			\ {'root' : '@',
			\  'name' : '/__VORAX_DBEXPLORER__',
			\  'style': 'vertical', 
			\  'side': 'left', 
			\  'size': 30, 
			\  'min_size': 10,
			\  'span': 1})

let s:base_categories = [
			\ {'label': 'Tables', 'object_type': 'TABLE'}, 
			\ {'label': 'Views', 'object_type': 'VIEW'}, 
			\ {'label': 'MViews', 'object_type': 'MATERIALIZED_VIEW'}, 
			\ {'label': 'Sequences', 'object_type': 'SEQUENCE'}, 
			\ {'label': 'Synonyms', 'object_type': 'SYNONYM'},
			\ {'label': 'Packages', 'object_type': 'PACKAGE'}, 
			\ {'label': 'Types', 'object_type': 'TYPE'}, 
			\ {'label': 'Procedures', 'object_type': 'PROCEDURE'},
			\ {'label': 'Functions', 'object_type': 'FUNCTION'}, 
			\ {'label': 'Triggers', 'object_type': 'TRIGGER'}, 
			\ {'label': 'Java Sources', 'object_type': 'JAVA_SOURCE'},
			\ {'label': 'DB Links', 'object_type': 'DB_LINK'},
			\ {'label': 'Users', 'object_type': 'USER'}
			\ ]

function! vorax#explorer#OpenDbComplete(arglead, cmdline, crrpos) "{{{
	let parts = split(strpart(a:cmdline, 0, a:crrpos), '\s\+', 1)
	if len(parts) == 2
		" completion for object type
		let object_types = map(copy(s:base_categories), 'v:val.object_type')
		return filter(object_types, "v:val =~? '^" . a:arglead . "'")
	elseif len(parts) == 3
		" completion for object name
		let object_type = s:DbmsMetadata2AllObjects(parts[1])
		let lead_parts = split(a:arglead, '\.', 1)
		if len(lead_parts) > 1
			let owner = lead_parts[0]
			let prefix = lead_parts[1]
		else
			let owner = ''
			let prefix = a:arglead
		endif
		let output = vorax#sqlplus#RunVoraxScript('get_objects.sql',
					\ toupper(object_type),
					\ toupper(owner),
          \ toupper(prefix))
		let data  = vorax#ruby#ParseResultset(output)
		let result = []
		if exists('data["resultset"][0]')
			let rs = data["resultset"][0]
			for rec in rs
				call add(result, rec[0])
			endfor
			return result
		endif
	endif
endfunction "}}}

function! vorax#explorer#OpenDbObject(bang, ...) "{{{
  call VORAXDebug("vorax#explorer#OpenDbObject bang=" . string(a:bang) .
				\ ' rest=' . string(a:000))
	" expect the first parameter to be the object type and
	" the second the object name (possibly including the owner)
	if a:0 == 2
		let name = a:2
		" the type is stored in DBMS_METADATA style but the
		" lookup is done in ALL_OBJECTS
		let type = toupper(a:1)
	else
		" not enough params
		return
	endif
	let parts = split(name, '\.')
	if len(parts) == 2
    let owner = parts[0]
    let object_name = parts[1]
	else
		let owner = ''
		let object_name = name
	endif
	" compute the buffer/file name
	let file_name = s:BufferName(type, object_name)
	if a:bang == ""
	  if a:bang == "" && filereadable(file_name)
			call s:OpenVoraxBuffer(file_name)
			call vorax#utils#SpitInfo("The local file was openned for edit not " . 
						\ "the definition from the database!")
			return
		endif
	endif
	let output = vorax#sqlplus#RunVoraxScript('extract_def.sql',
				\ toupper(owner),
				\ toupper(object_name),
				\ type)
  call VORAXDebug("vorax#explorer#OpenDbObject output=" . string(output))
	let data  = vorax#ruby#ParseResultset(output)
	if exists('data["resultset"][0]')
		let rs = data["resultset"][0]
		" expect one record only
		if exists('rs[0][0]')
			let content = rs[0][0]
			if vorax#utils#IsEmpty(content)
				redraw
				call vorax#utils#SpitWarn('Sorry, the definition is empty! No such database object?')
				return
			endif
			call s:OpenVoraxBuffer(file_name)
			if a:bang == "!"
				" clear the buffer content
				normal! gg"_dG
				if g:vorax_edit_warning && filereadable(file_name)
					redraw
					call vorax#utils#SpitInfo("A local file matching the DB object name was found!\n" .
								\ "It was overwritten with the definition from the database!\n" .
								\ "Take care before saving the buffer!")
				endif
			endif
			call append(0, split(content, '\n'))
			normal! gg
		endif
	endif
endfunction "}}}

function! vorax#explorer#Open() abort "{{{
	call s:tree.Open()
endfunction "}}}

function! vorax#explorer#Close() abort "{{{
	call s:tree.Close()
endfunction "}}}

function! vorax#explorer#Toggle() abort "{{{
	call s:tree.Toggle()
	call vorax#explorer#RefreshRoot()
endfunction "}}}

function! vorax#explorer#RefreshRoot() abort "{{{
	if vorax#explorer#IsOpen()
		let sp_props = vorax#sqlplus#Properties()
		let root = sp_props['user'] . '@' . sp_props['db']
		if s:tree.root != root
			call s:tree.SetPath(root, 1)
		endif
	endif
endfunction "}}}

function! vorax#explorer#Refresh(...) "{{{
	let state = winsaveview()
	call s:tree.RebuildTree()
	if a:0 > 0
		let path = a:1
		call s:tree.RevealNode(path)
	endif
	call winrestview(state)
endfunction "}}}

function! vorax#explorer#IsOpen() abort "{{{
  return s:tree._window.IsOpen()
endfunction "}}}

function! vorax#explorer#Root() abort "{{{
	return s:tree.root
endfunction "}}}

function! vorax#explorer#IsOpen() abort "{{{
	return s:tree._window.IsOpen()
endfunction "}}}

function! vorax#explorer#IsNodeEditable() "{{{
	let path = s:tree.GetPathUnderCursor()
	let descriptor = s:DescribeNode(path)
	if vorax#utils#IsEmpty(descriptor['object'])
		return 0
	endif
	return 1
endfunction "}}}

function! vorax#explorer#DescribeCurrentNode() "{{{
	let path = s:tree.GetPathUnderCursor()
	return s:DescribeNode(path)
endfunction "}}}

function! s:tree.ConfigureOptions() "{{{
  let &ft="explorervorax"
  setlocal winfixheight
  setlocal hidden
  setlocal winfixheight
  setlocal noswapfile
  setlocal buftype=nofile
  setlocal nowrap
  setlocal nospell
  setlocal nonu
  setlocal cursorline
  setlocal modifiable
  setlocal nolist
  setlocal noreadonly
  setlocal nobuflisted
  setlocal isk+=$
  setlocal isk+=#
	setlocal conceallevel=3
endfunction "}}}

function! s:tree.ConfigureKeys() "{{{
	noremap <silent> <buffer> R :call vorax#explorer#Refresh()<CR>
	noremap <silent> <buffer> m :call vorax#explorer#OpenContextMenu()<CR>
endfunction "}}}

function! s:tree.GetSubNodes(path) "{{{
  if s:IsRoot(a:path)
		return s:GetRootCategories()
	elseif s:IsUsersCategory(a:path)
		return s:GetAllUsers()
	elseif s:IsUserNode(a:path)
		let user_categories = s:GetRootCategories()
		" remove the last [Users] item
		call remove(user_categories, -1)
		return user_categories
	else
		let descriptor = s:DescribeNode(a:path)
		if descriptor != {}
			if descriptor['category'] == 'Tables'
				return s:GetObjects('TABLE', descriptor['owner'])
			elseif descriptor['category'] == 'Views'
				return s:GetObjects('VIEW', descriptor['owner'])
			elseif descriptor['category'] == 'MViews'
				return s:GetObjects('MATERIALIZED VIEW', descriptor['owner'])
			elseif descriptor['category'] == 'Sequences'
				return s:GetObjects('SEQUENCE', descriptor['owner'])
			elseif descriptor['category'] == 'Synonyms'
				return s:GetObjects('SYNONYM', descriptor['owner'])
			elseif descriptor['category'] == 'Packages'
				return s:GetObjects('PACKAGE', descriptor['owner'])
			elseif descriptor['category'] == 'Types'
				return s:GetObjects('TYPE', descriptor['owner'])
			elseif descriptor['category'] == 'Procedures'
				return s:GetObjects('PROCEDURE', descriptor['owner'])
			elseif descriptor['category'] == 'Functions'
				return s:GetObjects('FUNCTION', descriptor['owner'])
			elseif descriptor['category'] == 'Triggers'
				return s:GetObjects('TRIGGER', descriptor['owner'])
			elseif descriptor['category'] == 'Java Sources'
				return s:GetObjects('JAVA SOURCE', descriptor['owner'])
			elseif descriptor['category'] == 'DB Links'
				return s:GetDbLinks(descriptor['owner'])
			endif
		endif
	endif
	return []
endfunction "}}}

function! s:tree.IsLeaf(path) "{{{
	let parts = split(a:path, self.path_separator)
	if len(parts) == 1 || len(parts) == 2
		return 0
	elseif s:IsUserNode(a:path)
		return 0
  elseif s:IsCategoryUnderUser(a:path)
  	return 0
  else
		return 1
	endif
endfunction "}}}

function! s:OpenVoraxBuffer(file_name) "{{{
	" find a suitable window to stack upon to
	call vorax#utils#FocusCandidateWindow()
	" open the file
	silent! exe 'edit ' . a:file_name
endfunction "}}}

function! s:DbmsMetadata2AllObjects(type) "{{{
	let type = a:type
	if type =~? '^PACKAGE_.*'
		let type = 'PACKAGE'
	elseif type =~? '^TYPE_.*'
		let type = 'TYPE'
	elseif type ==? 'DB_LINK'
		let type = a:type
	else
		let type = substitute(type, '_', ' ', 'g')
	endif
	return type
endfunction "}}}

function! s:Category2DbmsMetadata(category) abort "{{{
	if a:category == 'Tables'
		return 'TABLE'
	elseif a:category == 'Views'
		return 'VIEW'
	elseif a:category == 'MViews'
		return 'MATERIALIZED VIEW'
	elseif a:category == 'Sequences'
		return 'SEQUENCE'
	elseif a:category == 'Synonyms'
		return 'SYNONYM'
	elseif a:category == 'Packages'
		return 'PACKAGE'
	elseif a:category == 'Types'
		return 'TYPE'
	elseif a:category == 'Procedures'
		return 'PROCEDURE'
	elseif a:category == 'Functions'
		return 'FUNCTION'
	elseif a:category == 'Triggers'
		return 'TRIGGER'
	elseif a:category == 'Java Sources'
		return 'JAVA SOURCE'
	elseif a:category == 'DB Links'
		return 'DB_LINK'
	elseif a:category == 'Users'
		return 'USER'
	endif
	return ''
endfunction "}}}

function! s:BufferName(type, name) "{{{
	" is it a plsql object?
	let file_ext = get(g:vorax_plsql_associations, a:type, '')
	if vorax#utils#IsEmpty(file_ext)
		" it's a SQL buffer then
		let file_ext = get(g:vorax_sql_associations, a:type, g:vorax_sql_script_default_extension)
	endif
	return a:name . '.' . file_ext
endfunction "}}}

function! s:OpenCurrentNode(bang) "{{{
	let path = s:tree.GetPathUnderCursor()
	let descriptor = s:DescribeNode(path)
	if descriptor != {}
		let dbtype = s:Category2DbmsMetadata(descriptor['category'])
		if !vorax#utils#IsEmpty(descriptor['object'])
			if descriptor['category'] == 'Users'
				let dbobject = toupper(descriptor['object'])
			else
				let dbobject = toupper(descriptor['owner'] . '.' . descriptor['object'])
			endif
			if exists('dbobject')
				call vorax#explorer#OpenDbObject(a:bang, dbtype, dbobject)
			endif
		endif
	endif
endfunction "}}}

function! s:tree.OpenNode(path) "{{{
	let bang = g:vorax_dbexplorer_force_edit ? '!' : ''
	call s:OpenCurrentNode(bang)
endfunction "}}}

function! s:GetObjects(type, owner) "{{{
  let result = []
  let rs = vorax#sqlplus#Query("select object_name || decode(status, 'INVALID', ' [INVALID]', '') from all_objects " .
				\ "where owner = '" . a:owner . "' and " .
				\ "object_type = '" . a:type . "'  " .
				\ "order by 1;")
	if exists("rs['resultset'][0]")
		for rec in rs['resultset'][0]
			call add(result, rec[0])
		endfor
	endif
	return result
endfunction "}}}

function! s:GetDbLinks(owner) "{{{
  let result = []
  let rs = vorax#sqlplus#Query('select db_link from all_db_links ' .
				\ "where owner = '" . a:owner . "' " .
				\ "order by 1;")
	if exists("rs['resultset'][0]")
		for rec in rs['resultset'][0]
			call add(result, rec[0])
		endfor
	endif
	return result
endfunction "}}}

function! s:GetAllUsers() "{{{
  let result = []
  let rs = vorax#sqlplus#Query(
				\ 'select * from (' .
				\ 'select username ' . 
				\ 'from all_users ' .
				\ 'union all ' .
				\ "select 'PUBLIC' from dual " .
				\ ') order by 1;')
	if exists("rs['resultset'][0]")
		for rec in rs['resultset'][0]
			call add(result, rec[0])
		endfor
	endif
	return result
endfunction "}}}

function! s:IsRoot(path) "{{{
  return a:path ==? (s:tree.path_separator . s:tree.root)
endfunction "}}}

function! s:DescribeNode(path) "{{{
	let descriptor = {'object': '', 
				\ 'category': '', 
				\ 'owner': '',
				\ 'dbtype': ''}
	let parts = split(a:path, s:tree.path_separator)
  if len(parts) >= 2
		let category = parts[1]
		if category == 'Users'
      if len(parts) >= 4
				let descriptor['category'] = parts[3]
				let descriptor['owner'] = parts[2]
				if len(parts) > 4
					let descriptor['object'] = parts[-1]
				endif
			elseif len(parts) == 3
				let descriptor['category'] = category
				let descriptor['object'] = parts[-1]
			endif
		else
			let splus_props = vorax#sqlplus#Properties()
			let descriptor['category'] = category
			let descriptor['owner'] = splus_props['user']
			if len(parts) > 2
				let descriptor['object'] = parts[-1]
			endif
		endif
	endif
	for item in s:base_categories
		if item.label == descriptor['category']
			let descriptor.dbtype = item.object_type
			break
		endif
	endfor
	let descriptor.object = substitute(descriptor.object, '\m \[INVALID\]$', '', 'g')
	return descriptor
endfunction "}}}

function! s:IsUserNode(path) "{{{
	let parts = split(a:path, s:tree.path_separator)
	return len(parts) == 3 && parts[-2] == 'Users'
endfunction "}}}

function! s:IsUsersCategory(path) "{{{
	let parts = split(a:path, s:tree.path_separator)
	return len(parts) == 2 && parts[-1] == 'Users'
endfunction "}}}

function! s:IsCategoryUnderUser(path) "{{{
	let parts = split(a:path, s:tree.path_separator)
	return len(parts) == 4 && parts[-3] == 'Users'
endfunction "}}}

function! s:GetRootCategories() "{{{
	let base_categories = map(copy(s:base_categories), 'v:val.label')
  if vorax#utils#IsEmpty(g:vorax_dbexplorer_exclude)
		let categories = base_categories
	else
		let categories = []
		for category in base_categories
			if category !~ g:vorax_dbexplorer_exclude
				call add(categories, category)
			endif
		endfor
	endif
	return categories
endfunction "}}}

" Contextual menu "{{{

function! vorax#explorer#Menu() "{{{
	if !exists('s:explorer_menu')
		let items = []
		call add(items, s:OpenDefMenuItem())
		call add(items, s:ForceOpenDefMenuItem())
		let s:explorer_menu = vorax#menu#Create(items, 'Explorer menu. ')
	endif
	return s:explorer_menu
endfunction "}}}

function! vorax#explorer#OpenContextMenu() "{{{
	let path = s:tree.GetPathUnderCursor()
	call vorax#explorer#Menu().showMenu()
endfunction "}}}

" Normal open definition item "{{{

function! s:OpenDefMenuItem() "{{{
	let open_def = vorax#menuitem#Create(
				\ {'text': '(O)pen definition', 
				\  'shortcut' : 'o', 
				\  'callback' : 'vorax#explorer#NormalOpenCurrentNode',
				\  'isActiveCallback' : 'vorax#explorer#IsNodeEditable'})
	return open_def
endfunction "}}}

function! vorax#explorer#NormalOpenCurrentNode() "{{{
	call s:OpenCurrentNode('')
endfunction "}}}

"}}}

" Force open definiton item "{{{

function! vorax#explorer#ForceOpenCurrentNode() "{{{
	call s:OpenCurrentNode('!')
endfunction "}}}

function! s:ForceOpenDefMenuItem() "{{{
	let open_def = vorax#menuitem#Create(
				\ {'text': '(F)orce open definition', 
				\  'shortcut' : 'f', 
				\  'callback' : 'vorax#explorer#ForceOpenCurrentNode',
				\  'isActiveCallback' : 'vorax#explorer#IsNodeEditable'})
	return open_def
endfunction "}}}

"}}}

"}}}

