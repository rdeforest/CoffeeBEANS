# The editor is the program. Running is an operation applied to a region of
# it, and the file on disk is the single source of truth so vim in another
# window stays coherent.

{EditorState, EditorSelection, StateField, StateEffect, Prec,
 EditorView, Decoration, keymap, lineNumbers, highlightActiveLine,
 highlightActiveLineGutter, drawSelection,
 defaultKeymap, history, historyKeymap, indentWithTab,
 StreamLanguage, syntaxHighlighting, HighlightStyle, indentUnit, bracketMatching,
 coffeeScript, searchKeymap, highlightSelectionMatches,
 vim, Vim, tags} = CM

SAVE_DELAY  = 250
FLASH_DELAY = 260

view        = null
handlers    = {}
current     = null
lastWritten = null
saveTimer   = null

# --- ran-region flash -------------------------------------------------------

flashEffect = StateEffect.define()
flashMark   = Decoration.mark class: 'cm-ran'

flashField = StateField.define
  create:  -> Decoration.none
  update:  (marks, tr) ->
    marks = marks.map tr.changes
    for effect in tr.effects when effect.is flashEffect
      {from, to} = effect.value ? {}
      marks = if from? and to > from
        Decoration.set [flashMark.range from, to]
      else
        Decoration.none
    marks
  provide: (field) -> EditorView.decorations.from field

flash = (from, to) ->
  view.dispatch effects: flashEffect.of {from, to}
  setTimeout (-> view.dispatch effects: flashEffect.of null), FLASH_DELAY

# --- regions ----------------------------------------------------------------

# A bare selection is what you asked for. A bare cursor means the paragraph
# around it, which for CoffeeScript is usually exactly one definition.
regionAt = (state) ->
  {from, to} = state.selection.main
  return {from, to} if from isnt to

  line = state.doc.lineAt from
  return {from: line.from, to: line.to} unless line.text.trim()

  first = last = line.number
  first -= 1 while first > 1              and state.doc.line(first - 1).text.trim()
  last  += 1 while last < state.doc.lines and state.doc.line(last  + 1).text.trim()
  {from: state.doc.line(first).from, to: state.doc.line(last).to}

# An indented fragment is a syntax error on its own, so a region taken from
# inside a block has to come back out to column zero.
dedent = (text) ->
  widths = (line.match(/^[ \t]*/)[0].length for line in text.split '\n' when line.trim())
  return text unless widths.length
  cut = Math.min widths...
  return text unless cut
  (line[cut..] for line in text.split '\n').join '\n'

# --- persistence ------------------------------------------------------------

save = ->
  clearTimeout saveTimer
  return unless current and view
  text = view.state.doc.toString()
  return if text is lastWritten
  lastWritten = text
  await beans.write current, text
  handlers.onSave? current

scheduleSave = ->
  clearTimeout saveTimer
  saveTimer = setTimeout save, SAVE_DELAY

# A pending debounced edit is the only "unsaved" state this editor has, and
# only briefly: switching sketches flushes it first. :e honours it anyway so
# vim muscle memory holds.
isDirty = -> view? and view.state.doc.toString() isnt lastWritten

# :e! forgets a pending edit rather than flushing it: call the buffer already
# written so the reload's save() is a no-op, then let the reload replace it.
dropPending = ->
  clearTimeout saveTimer
  lastWritten = view.state.doc.toString()

# Echoes of our own writes come back through the watcher; ignore those.
applyExternal = ({name, text}) ->
  return unless name is current and view
  return if text is lastWritten or text is view.state.doc.toString()
  lastWritten = text
  anchor      = Math.min view.state.selection.main.anchor, text.length
  view.dispatch
    changes:   {from: 0, to: view.state.doc.length, insert: text}
    selection: {anchor}
  handlers.onExternal? name

# --- source count + length limit --------------------------------------------

# A source line is one his co-work limits count: not blank, not a comment.
# The same test he was running by hand in the REPL.
SOURCE = /^\s*[^ #]/

countSource = (doc) ->
  n = 0
  for i in [1..doc.lines] when SOURCE.test doc.line(i).text
    n += 1
  n

lineLimit = null

# Where the (limit+1)th source line lives: the first line he went over budget
# on. null while there is no limit, or while he is still within it.
overFrom = (doc) ->
  return null unless lineLimit?
  n = 0
  for i in [1..doc.lines] when SOURCE.test doc.line(i).text
    return doc.line(i).from if (n += 1) > lineLimit
  null

overMark   = Decoration.line class: 'cm-over-limit'
buildLimit = (doc) ->
  from = overFrom doc
  if from? then Decoration.set [overMark.range from] else Decoration.none

# Asks the field to recompute when the limit changed but the text did not.
relimit = StateEffect.define()

limitField = StateField.define
  create:  (state) -> buildLimit state.doc
  update:  (deco, tr) ->
    return buildLimit tr.state.doc if tr.docChanged or tr.effects.some (e) -> e.is relimit
    deco.map tr.changes
  provide: (field) -> EditorView.decorations.from field

reportLines = -> handlers.onLines? count: countSource(view.state.doc), limit: lineLimit

setLimit = (n) ->
  lineLimit = if n > 0 then n else null
  view.dispatch effects: relimit.of null
  reportLines()

# --- appearance -------------------------------------------------------------

palette =
  bg:      '#111114'
  fg:      '#d3d3d8'
  dim:     '#5d5d68'
  coffee:  '#C0FFEE'
  string:  '#e8c37e'
  keyword: '#8ab4ff'
  number:  '#f78ca0'

theme = EditorView.theme {
  '&':                        {height: '100%', backgroundColor: palette.bg, color: palette.fg}
  '.cm-scroller':             {fontFamily: 'ui-monospace, "DejaVu Sans Mono", monospace', lineHeight: '1.5'}
  '.cm-content':              {caretColor: palette.coffee}
  '.cm-gutters':              {backgroundColor: palette.bg, color: palette.dim, border: 'none'}
  '.cm-activeLine':           {backgroundColor: '#ffffff08'}
  '.cm-activeLineGutter':     {backgroundColor: 'transparent', color: palette.coffee}
  '.cm-ran':                  {backgroundColor: '#C0FFEE33', transition: 'background-color .2s'}
  '.cm-over-limit':           {backgroundColor: '#ff6b6b22', boxShadow: 'inset 2px 0 0 #ff6b6b'}
  '.cm-fat-cursor':           {backgroundColor: '#C0FFEE99 !important', outline: 'none !important'}
  '.cm-vim-panel':            {backgroundColor: '#17171b', color: palette.coffee, padding: '0 .4rem'}
  '.cm-vim-panel input':      {color: palette.coffee, fontFamily: 'inherit'}
}, dark: yes

highlight = HighlightStyle.define [
  {tag: tags.comment,                     color: palette.dim, fontStyle: 'italic'}
  {tag: tags.string,                      color: palette.string}
  {tag: tags.number,                      color: palette.number}
  {tag: [tags.keyword, tags.operatorKeyword], color: palette.keyword}
  {tag: [tags.definitionKeyword, tags.controlKeyword], color: palette.keyword}
  {tag: tags.propertyName,                color: palette.coffee}
  {tag: tags.variableName,                color: palette.fg}
  {tag: tags.atom,                        color: palette.number}
]

# --- commands ---------------------------------------------------------------

runRegion = ->
  {from, to} = regionAt view.state
  flash from, to
  handlers.onRun? dedent(view.state.sliceDoc from, to), current
  true

runAll = ->
  save()
  handlers.onRunAll? view.state.doc.toString(), current
  true

restartAll = ->
  save()
  handlers.onRestart? view.state.doc.toString(), current
  true

# :e opens a sketch by name, creating it if new -- the app's version of
# touching a file and reloading. A bare :e reloads the current one. The bang
# is not a flag this vim build exposes; it stays in the argument string.
editSketch = (params) ->
  arg   = ((params?.argString ? '') or (params?.args ? []).join ' ').trim()
  force = arg[0] is '!'
  arg   = arg[1..].trim() if force
  name  = arg.split(/\s+/)[0]?.replace(/\.coffee$/, '') or current
  return true unless name
  if isDirty() and not force
    handlers.onMessage? 'no write since last change (add ! to override)'
    return true
  dropPending() if force
  handlers.onEdit? name
  true

beansKeymap = [
  {key: 'Ctrl-Enter',       run: runRegion,  preventDefault: yes}
  {key: 'Ctrl-Shift-Enter', run: restartAll, preventDefault: yes}
  {key: 'Ctrl-s',           run: (-> save(); true), preventDefault: yes}
]

installVimCommands = ->
  Vim.defineAction 'beansRunRegion', -> runRegion()
  Vim.mapCommand '<C-r>', 'action', 'beansRunRegion', {}, context: 'visual'
  Vim.defineEx 'write',   'w',   -> save()
  Vim.defineEx 'run',     'run', -> runAll()
  Vim.defineEx 'restart', 'restart', -> restartAll()
  Vim.defineEx 'help',    'h',   (cm, params) -> handlers.onHelp? params?.args?[0]
  Vim.defineEx 'edit',    'e',   (cm, params) -> editSketch params
  Vim.defineEx 'target',  'tar', (cm, params) -> setLimit Number((params?.args ? [])[0] ? 0)

# --- public -----------------------------------------------------------------

Editor =
  mount: (parent, hooks) ->
    handlers = hooks
    installVimCommands()
    view = new EditorView
      parent: parent
      state:  EditorState.create
        doc: ''
        extensions: [
          vim()
          lineNumbers()
          highlightActiveLine()
          highlightActiveLineGutter()
          drawSelection()
          bracketMatching()
          history()
          highlightSelectionMatches()
          flashField
          limitField
          StreamLanguage.define coffeeScript
          syntaxHighlighting highlight
          indentUnit.of '  '
          theme
          Prec.highest keymap.of beansKeymap
          keymap.of [...defaultKeymap, ...historyKeymap, ...searchKeymap, indentWithTab]
          EditorView.updateListener.of (update) ->
            return unless update.docChanged
            scheduleSave()
            reportLines()
        ]
    beans.onChanged applyExternal
    reportLines()
    view

  load: (name) ->
    await save()          # the outgoing sketch may have an unflushed edit
    text        = await beans.read name
    current     = name
    lastWritten = text
    view.dispatch
      changes:   {from: 0, to: view.state.doc.length, insert: text}
      selection: {anchor: 0}
    name

  name:      -> current
  all:       -> view.state.doc.toString()
  runRegion: -> view.focus(); runRegion()
  view:      -> view
  save:   save
  focus:  -> view.focus()

globalThis.Editor = Editor
