# The editor is the program. Running is an operation applied to a region of
# it, and the file on disk is the single source of truth so vim in another
# window stays coherent.

{EditorState, EditorSelection, Compartment, StateField, StateEffect, Prec,
 EditorView, Decoration, keymap, lineNumbers, highlightActiveLine,
 highlightActiveLineGutter, drawSelection,
 defaultKeymap, history, historyKeymap, indentWithTab,
 StreamLanguage, syntaxHighlighting, HighlightStyle, indentUnit, bracketMatching,
 coffeeScript, searchKeymap, highlightSelectionMatches,
 vim, Vim, getCM, tags} = CM

SAVE_DELAY  = 250
FLASH_DELAY = 260

view        = null
handlers    = {}
current     = null
lastWritten = null
saveTimer   = null
writing     = {}      # sketch name -> this page's saves of it not yet answered
sent        = {}      # sketch name -> the text of this page's latest save of it

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

# One timer, not one per flash: a second region run inside the delay would
# otherwise have its highlight cleared by the first run's timer.
flashTimer = null

flash = (from, to) ->
  view.dispatch effects: flashEffect.of {from, to}
  clearTimeout flashTimer
  flashTimer = setTimeout (-> view.dispatch effects: flashEffect.of null), FLASH_DELAY

# --- the line a sketch is paused on ------------------------------------------

# Set from outside: the debugger says which line, the editor only draws it.
# Mapped through edits like the other marks, so typing above a paused line
# does not leave the highlight on the wrong one.
pausedEffect = StateEffect.define()
pausedMark   = Decoration.line class: 'cm-paused-line'

pausedField = StateField.define
  create:  -> Decoration.none
  update:  (marks, tr) ->
    marks = marks.map tr.changes
    for effect in tr.effects when effect.is pausedEffect
      marks = if effect.value? then Decoration.set [pausedMark.range effect.value] else Decoration.none
    marks
  provide: (field) -> EditorView.decorations.from field

showLine = (n) ->
  return view.dispatch effects: pausedEffect.of null unless n? and 1 <= n <= view.state.doc.lines
  from = view.state.doc.line(n).from
  view.dispatch
    effects: [pausedEffect.of(from), EditorView.scrollIntoView from, y: 'center']

# Where a run broke. Unlike the paused line it does not follow edits: the
# first keystroke there is the start of the fix, and a red line that kept up
# with the typing would go on saying the code is broken.
errorEffect = StateEffect.define()
errorMark   = Decoration.line class: 'cm-error-line'

errorField = StateField.define
  create:  -> Decoration.none
  update:  (marks, tr) ->
    marks = Decoration.none if tr.docChanged
    for effect in tr.effects when effect.is errorEffect
      marks = if effect.value? then Decoration.set [errorMark.range effect.value] else Decoration.none
    marks
  provide: (field) -> EditorView.decorations.from field

lineStart = (n) -> view.state.doc.line(n).from if n? and 1 <= n <= view.state.doc.lines

showError = (n) ->
  from = lineStart n
  return view.dispatch effects: errorEffect.of null unless from?
  view.dispatch effects: [errorEffect.of(from), EditorView.scrollIntoView from, y: 'center']

# The cursor on a line, the line marked, and the keyboard handed over. A
# syntax error knows its column; a stack frame only knows its line, so it
# gets the first thing written there.
jumpTo = (n, column) ->
  from = lineStart n
  return unless from?
  line   = view.state.doc.line n
  offset = if column? then column - 1 else line.text.search /\S|$/
  at     = from + Math.min Math.max(0, offset), line.length
  view.dispatch
    selection: {anchor: at}
    effects:   [errorEffect.of(from), EditorView.scrollIntoView at, y: 'center']
  view.focus()

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
# Hands back how much it cut as well: a syntax error in the region reports
# its column in the dedented text, and the cursor belongs in the buffer's.
dedent = (text) ->
  widths = (line.match(/^[ \t]*/)[0].length for line in text.split '\n' when line.trim())
  cut    = if widths.length then Math.min widths... else 0
  return {text, cut: 0} unless cut
  {text: (line[cut..] for line in text.split '\n').join('\n'), cut}

# --- persistence ------------------------------------------------------------

# lastWritten is set before the write, so the watcher's echo of our own write
# is recognised and ignored. A write that *fails* has to put it back, or the
# editor believes an edit reached disk that never did and silently drops it at
# the next reload. Unless a later save has moved lastWritten on since: putting
# this one's `was` back over that would claim an older text is on disk.
save = ->
  clearTimeout saveTimer
  return unless current and view
  text = view.state.doc.toString()
  return if text is lastWritten
  was         = lastWritten
  lastWritten = text
  name        = current
  writing[name] = (writing[name] ? 0) + 1
  sent[name]    = text
  try
    note = await beans.write name, text
    handlers.onMessage? note if note
  catch error
    lastWritten = was if lastWritten is text
    handlers.onProblem? "could not save #{name}: #{error.message}"
  finally
    writing[name] -= 1
  undefined

scheduleSave = ->
  clearTimeout saveTimer
  saveTimer = setTimeout save, SAVE_DELAY

# The page is going away -- View > Reload, the window closing, the app
# quitting -- and the debounce timer with it, so an edit made in the last
# 250ms never reached the disk. Sent even with nothing new, so the page waits
# for an autosave still in flight and a reload reads it back. The text goes
# too while one of this page's saves is in flight: if that save fails, nobody
# is left to save it again, so main writes it once more behind it. Blocks
# until main answers (sketch:flush). A crashed renderer runs none of this,
# and comes back as last saved. A sketch switched away from while its
# autosave was in flight is flushed the same way, with the text that save
# sent: switching saves first, but a save already going is not waited for.
flush = ->
  clearTimeout saveTimer
  if current and view
    text        = view.state.doc.toString()
    resend      = text isnt lastWritten or writing[current] > 0
    lastWritten = text
    beans.flush current, (text if resend)
  beans.flush name, sent[name] for name, count of writing when count > 0 and name isnt current
  undefined

# A pending debounced edit is the only "unsaved" state this editor has, and
# only briefly: switching sketches saves it first. :e honours it anyway so
# vim muscle memory holds.
isDirty = -> view? and view.state.doc.toString() isnt lastWritten

# :e! forgets a pending edit rather than flushing it: call the buffer already
# written so the reload's save() is a no-op, then let the reload replace it.
dropPending = ->
  clearTimeout saveTimer
  lastWritten = view.state.doc.toString()

# lastWritten is the text as CodeMirror holds it, never the bytes on disk:
# CodeMirror reads \r\n and \r as \n, so a CRLF sketch compared raw read dirty
# forever and its next save rewrote a file nobody edited. A save sends \n and
# main writes it back with the endings the file already has (writeSketch), so
# the echo of a CRLF save is recognised here in its \n form.
asHeld = (text) -> view.state.toText(text).toString()

# Echoes of our own writes come back through the watcher; ignore those.
applyExternal = ({name, text}) ->
  return unless name is current and view
  text = asHeld text
  return if text is lastWritten or text is view.state.doc.toString()
  lastWritten = text
  anchor      = Math.min view.state.selection.main.anchor, text.length
  view.dispatch
    changes:   {from: 0, to: view.state.doc.length, insert: text}
    selection: {anchor}
  handlers.onExternal? name

# --- source count + length limit --------------------------------------------

# A source line is one his co-work limits count: not blank, not a comment.
# The same test he was running by hand in the REPL. The character class has to
# exclude every kind of space, not just the one: `[^ #]` matched a tab, so a
# tab-indented comment counted as source and so did a line of nothing but tabs.
SOURCE = /^\s*[^\s#]/

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
  '.cm-paused-line':          {backgroundColor: '#e8c37e2e', boxShadow: 'inset 3px 0 0 #e8c37e'}
  '.cm-error-line':           {backgroundColor: '#ff6b6b26', boxShadow: 'inset 3px 0 0 #ff6b6b'}
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

# Eval puts code into the worker that is already running, so everything it
# knows stays. Run throws that worker away first. They are different in kind,
# not in scope, which is why they do not share a verb.
evalRegion = ->
  {from, to} = regionAt view.state
  flash from, to
  # Padded down to where the region sits, so every line number a run reports
  # -- an error, a traceback, the line a breakpoint stopped on -- is a line
  # of the buffer rather than of the region.
  above = '\n'.repeat view.state.doc.lineAt(from).number - 1
  {text, cut} = dedent view.state.sliceDoc from, to
  handlers.onEval? above + text, current, cut
  true

evalAll = ->
  save()
  handlers.onEvalAll? view.state.doc.toString(), current
  true

runFresh = ->
  save()
  handlers.onRun? view.state.doc.toString(), current
  true

# :e opens a sketch by name, creating it if new -- the app's version of
# touching a file and reloading. A bare :e reloads the current one. The bang
# is not a flag vim's parser knows; it arrives as the start of the argument.
editSketch = (arg) ->
  force = arg[0] is '!'
  arg   = arg[1..].trim() if force
  name  = arg.split(/\s+/)[0].replace(/\.coffee$/, '') or current
  return true unless name
  if isDirty() and not force
    handlers.onMessage? 'no write since last change (add ! to override)'
    return true
  dropPending() if force
  handlers.onEdit? name
  true

beansKeymap = [
  {key: 'Ctrl-Enter',       run: evalRegion, preventDefault: yes}
  {key: 'Ctrl-Shift-Enter', run: runFresh,   preventDefault: yes}
  {key: 'Ctrl-s',           run: (-> save(); true), preventDefault: yes}
  # Unclaimed, Ctrl-r reaches View > Reload (CmdOrCtrl+R off a Mac), which
  # throws the worker away and everything the sketch built in it.
  # Vim keeps its own Ctrl-r (redo, insert register, eval in visual mode)
  # because its slot sees keys before this keymap does; the editor test
  # checks redo, so that order cannot quietly flip.
  {key: 'Ctrl-r',           run: -> true}
]

# One table, two ways in: vim's `:` line, and the prompt, where a line
# starting with `/` or `:` is always a command. Both hand an entry the same
# argument -- whatever follows the name, trimmed -- so `:e! foo` and
# `/e! foo` cannot drift apart. `short` is the least a name may be cut to,
# vim's rule, kept at the prompt so a name means the same in both places.
# Nothing here needs vim: the prompt works with it switched off.
COMMANDS = [
  {name: 'write',    short: 'w',       run: -> save()}
  {name: 'eval',     short: 'ev',      run: evalAll}
  {name: 'run',      short: 'run',     run: runFresh}
  # Kept because it is exactly what run does, and it was the name for a while.
  {name: 'restart',  short: 'restart', run: runFresh}
  # Vim's parser used to hand help its words already split; the topic is
  # searched for as typed, so a run of spaces must not make it miss.
  {name: 'help',     short: 'h',       run: (arg) -> handlers.onHelp? arg.replace /\s+/g, ' '}
  {name: 'edit',     short: 'e',       run: editSketch}
  {name: 'target',   short: 'tar',     run: (arg) -> setLimit Number arg.split(/\s+/)[0]}
  # Frame at a time. `:step` from a running sketch pauses it first, so you do
  # not have to catch it.
  {name: 'pause',    short: 'pau',     run: -> handlers.onPause?()}
  {name: 'step',     short: 'st',      run: -> handlers.onStep?()}
  {name: 'continue', short: 'cont',    run: -> handlers.onGo?()}
  # Line at a time: to the next line that runs, wherever it is.
  {name: 'line',     short: 'li',      run: -> handlers.onLine?()}
]

lookup = (word) ->
  COMMANDS.find (entry) -> entry.name.startsWith(word) and word.startsWith entry.short

COMMAND_LINE = /^\s*([\/:])(\w*)([^]*)$/

# The prompt's way in. Vim's parser splits a line the same way: a run of word
# characters is the name and the rest, `!` included, is the argument.
command = (line) ->
  [, mark, word, arg] = line.match COMMAND_LINE
  entry = lookup word
  return entry.run arg.trim() if entry
  names = ("#{mark}#{known.name}" for known in COMMANDS).join ' '
  handlers.onProblem? "#{mark}#{word} is not a command -- there are #{names}"

toVim = (entry) ->
  Vim.defineEx entry.name, entry.short, (cm, params) -> entry.run (params.argString ? '').trim()

# Vim lets a name with no short form be cut to nothing shorter; so does the
# prompt, or an entry would work after `:` and never after `/`.
defineCommand = (entry) ->
  entry = {entry..., short: entry.short ? entry.name}
  COMMANDS.push entry
  toVim entry

# Vim has no way to forget an ex command (codemirror-vim's defineEx writes
# two private tables and nothing removes from them), so `:name` keeps working
# after this. The prompt, its "not a command" list and Tab read COMMANDS.
undefineCommand = (name) ->
  index = COMMANDS.findIndex (entry) -> entry.name is name
  COMMANDS.splice index, 1 unless index < 0

installVimCommands = ->
  Vim.defineAction 'beansEvalRegion', -> evalRegion()
  Vim.mapCommand '<C-r>', 'action', 'beansEvalRegion', {}, context: 'visual'
  toVim entry for entry in COMMANDS

# --- vim's autoindent ---------------------------------------------------------

# With 'autoindent', Vim takes back an indent it put on a line if nothing was
# typed there. codemirror-vim keeps CodeMirror's indent and has no such rule,
# so `o` then Esc left the spaces behind (Robert, 2026-10-05). What Vim 9.1
# does -- `vim -u NONE -N -i NONE -c 'set ai bs=indent,eol,start'` driven by
# feedkeys, on "if x / ··foo / ··bar / baz", measured by Claude on 2026-10-06;
# the `editor` test part checks each row:
#
#   keys (on a ··line)               the line after
#   o Esc, O Esc, 3o Esc             blank
#   o Enter Enter Esc                all three blank
#   o Up Esc, o Down Esc             blank, Down on the last line too
#   o Ctrl-T Esc                     blank
#   cc Esc, S Esc, cj Esc            blank
#   o Ctrl-O 0 x Esc                 x      the indent gone before the x
#   o ·· Esc                         ····   typed, so kept
#   o x Backspace Esc                ··     typed, so kept
#   o Left Esc                       ··     moved along the line, so kept
#   ^C Esc                           ··     a change, but not a linewise one
#   A Esc, on a line of spaces       kept: not an indent Vim made
#   o Esc u, o Down Esc u, cc Esc u  as it was: one undo
#   o Esc u Ctrl-R                   blank: one redo
#   o Backspace Esc                  ·      kept, though `:help autoindent`
#                                           says Backspace counts as nothing
#
#   played back by @q, or by `.`     the line after
#   o Esc                            blank
#   o ·· Esc                         ····   typed, so kept
#   A Esc, i Esc (onto ····, after   ····   not an indent Vim made
#     a cc on the line below)
#   cc Esc                           blank  ours: ··
#   o Ctrl-T Esc (by `.`)            blank  ours: ····
#   o Enter Enter Esc (by @q)        blank  ours: ··, ··, then blank
#
# So: a newline brings an indent (o, O, Enter) and a linewise change keeps
# one (cc, S, cj); typing on the line, or moving along it, makes it the
# author's; Esc, Ctrl-O, Enter or moving to another line takes it back --
# Enter with nothing here, since CodeMirror's newline already empties a line
# of spaces it breaks at the end. The last row is not ours to match:
# CodeMirror's Backspace takes a whole indent unit, so `o` Backspace Esc
# leaves the line blank either way.
#
# A playback runs inside the one vim command that plays it, and
# codemirror-vim records no last edit during one, so there the rule is
# coarser: what it types or Ctrl-T does on the line makes it the author's,
# and a cc keeps its indent. The rows marked "ours" are where that leaves an
# indent Vim takes back; the Enters keep theirs because a played-back Enter
# is inserted text, not CodeMirror's newline. None takes back too much.

indentOnly = (line) -> line.length > 0 and not /\S/.test line.text

# The undo label codemirror-vim gives a command's second change, which the
# history always joins to the change before it. Taken back under it, the
# indent goes with whatever brought it, and one `u` undoes both, as in Vim.
TAKE_BACK = 'input.type.compose'

setIndent = StateEffect.define()

# Where the line starts whose indent is still the editor's, or null. A field,
# so it follows undo and redo too, which skip transaction filters; any edit
# to the line that followIndent did not vouch for makes the line the author's.
indentField = StateField.define
  create: -> null
  update: (at, tr) ->
    for effect in tr.effects when effect.is setIndent
      return effect.value
    return null unless at?
    line = tr.startState.doc.lineAt at
    if tr.changes.touchesRange line.from, line.to then null else tr.changes.mapPos at

# A line break followed by the line's whole indent, and the cursor after it:
# what CodeMirror's newline makes for o, O and Enter.
newIndent = (tr) ->
  {head, empty} = tr.newSelection.main
  line = tr.newDoc.lineAt head
  return null unless empty and head is line.to and indentOnly line
  made = null
  tr.changes.iterChanges (fromA, toA, fromB, toB, text) ->
    made = line.from if toB is head and text.toString() is "\n#{line.text}"
  made

# Inside one vim command (o and cc on their way, Ctrl-T, Ctrl-U) neither the
# edits nor the cursor's steps are the author's: all that counts is whether
# the line is still nothing but indent.
byCommand = (tr, line) ->
  return tr unless tr.changes.touchesRange line.from, line.to
  still = tr.newDoc.lineAt tr.changes.mapPos line.from
  [tr, {effects: setIndent.of(if indentOnly still then still.from else null)}]

# Typing on the line is left to indentField. The cursor still at the end
# keeps the indent pending, anywhere else on the line makes it the author's,
# and on another line takes it back, in the same transaction as the move.
# A click keeps its own label first: CodeMirror's mouse selection reads only
# the first, takes TAKE_BACK for typing and ends the drag the click began.
# So after a click off the line, undo takes two steps instead of one.
byAuthor = (tr, line) ->
  return tr if tr.changes.touchesRange line.from, line.to
  here = tr.newDoc.lineAt tr.changes.mapPos line.from
  head = tr.newSelection.main.head
  return tr if head is here.to
  return [tr, {effects: setIndent.of null}] if here.from <= head <= here.to
  strip = {changes: {from: line.from, to: line.to}, userEvent: TAKE_BACK}
  if tr.isUserEvent 'select.pointer' then [tr, strip] else [strip, tr]

# A macro (@q) or a repeat (.) plays its typing back inside the one vim
# command that plays it, so there byCommand would take typed spaces for an
# indent. codemirror-vim keeps the flag only in its global state, reached
# through what it calls a testing hook.
replaying = -> Vim.getVimGlobalState_().macroModeState.isPlaying

followIndent = EditorState.transactionFilter.of (tr) ->
  cm = getCM view
  return tr unless cm.state.vim.insertMode
  made = newIndent tr
  return [tr, {effects: setIndent.of made}] if made?
  at = tr.startState.field indentField
  return tr unless at?
  line = tr.startState.doc.lineAt at
  if cm.curOp?.isVimOp and not replaying() then byCommand tr, line else byAuthor tr, line

takeBack = ->
  at = view.state.field indentField
  return unless at?
  line = view.state.doc.lineAt at
  view.dispatch changes: {from: line.from, to: line.to}, userEvent: TAKE_BACK

# The lastEditInputState keepAfterChange last read. codemirror-vim records a
# new one for each edit command typed (none before the first), but not for
# one a macro or a repeat plays, nor when Ctrl-O or a paste in normal mode
# brings insert mode back: then it still names some earlier command, maybe a
# cc on another line.
seenEdit = null

# cc, S and cj empty their line down to its indent, and enter insert mode
# with the selection still starting there. Only the command can tell cc from
# ^C, which makes the same edit and keeps the indent, and only a command just
# recorded is the one that entered insert mode. So a cc played by @q or `.`
# keeps its indent, where Vim's line ends blank.
keepAfterChange = ->
  edit = getCM(view).state.vim.lastEditInputState
  return if edit is seenEdit
  seenEdit = edit
  {operator, motionArgs} = edit ? {}
  return unless operator is 'change' and motionArgs?.linewise
  line = view.state.doc.lineAt view.state.selection.main.from
  view.dispatch effects: setIndent.of line.from if indentOnly line

ON_MODE =
  insert: keepAfterChange
  normal: takeBack

followMode = ({mode}) -> ON_MODE[mode]?()

# Each switch-on brings a new codemirror-vim, and at mount the setting
# arrives twice over the same one (beans.vim and beans.onVim): off before on
# keeps it to one listener.
followModes = ->
  cm = getCM view
  cm.off 'vim-mode-change', followMode
  cm.on  'vim-mode-change', followMode

# --- vim, if asked for -------------------------------------------------------

# Ordinary keys unless Edit > Vim Keys is ticked (Robert, 2026-10-04: most
# people on Steam will not want vim). Main keeps the setting, because the menu
# shows it; the editor only follows. Swapped in place, so the buffer, the
# cursor and the undo history all survive the switch.
vimSlot = new Compartment
VIM     = [vim(), indentField, followIndent]

# codemirror-vim only learns of a selection from a transaction it sees, so
# one made before the switch is handed over again; otherwise vim ignores it
# and the first `d` leaves it standing (seen by Claude, 2026-10-05).
setVim = (wanted) ->
  view.dispatch effects: vimSlot.reconfigure if wanted then VIM else []
  view.dispatch selection: view.state.selection if wanted
  followModes() if wanted

# --- Edit > Undo and Redo ----------------------------------------------------

# The menu's, and on a Mac the only way Cmd-Z reaches the prompt: a text field
# there takes undo from the menu, not from the key. Not the native undo the
# menu roles send. Chromium keeps one undo stack for the whole page, and
# undoes its last step wherever that was taken; CodeMirror answers it from
# its own history only when that step was typed into the editor. Measured by
# Claude on Linux, 2026-10-06, with the editor focused: after an edit made
# only through CodeMirror (a paste; vim's are the same kind) native Undo did
# nothing; after a prompt edit it undid the prompt; and after one Undo that
# CodeMirror did answer, Redo did nothing. So the editor gets CodeMirror's
# own commands, a field that takes typing -- the prompt, a dialog's -- the
# page's native step, and anything else nothing: from the canvas, native undo
# undid the prompt's last edit. The native step is taken by main's
# webContents.undo, not document.execCommand: when that step was typed into
# the editor, execCommand edits CodeMirror's DOM behind its back, which
# CodeMirror then reads as half an edit of its own and saves (found by a
# Claude reviewer, 2026-10-06; the editor part checks it). activeElement, not
# view.hasFocus: that also asks whether the window has focus, which a hidden
# test run's never does. The commands come from the keymap the bundle already
# exports, rather than a rebuilt bundle for two names.
HISTORY =
  undo: (historyKeymap.find (binding) -> binding.key is 'Mod-z').run
  redo: (historyKeymap.find (binding) -> binding.key is 'Mod-y').run

fromMenu = (verb) ->
  focused = document.activeElement
  return HISTORY[verb] view if focused is view.contentDOM
  beans.nativeHistory verb if focused.matches 'input, textarea'

# Edit > Redo shows Shift+CmdOrCtrl+Z everywhere, but CodeMirror binds
# Ctrl-Shift-Z only on Linux; Windows gets Ctrl-Y alone.
shiftRedo = {key: 'Mod-Shift-z', run: HISTORY.redo, preventDefault: yes}

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
          vimSlot.of []           # first, as codemirror-vim asks, so it sees keys before the rest
          lineNumbers()
          highlightActiveLine()
          highlightActiveLineGutter()
          drawSelection()
          bracketMatching()
          history()
          highlightSelectionMatches()
          flashField
          pausedField
          errorField
          limitField
          StreamLanguage.define coffeeScript
          syntaxHighlighting highlight
          indentUnit.of '  '
          theme
          Prec.highest keymap.of beansKeymap
          keymap.of [...defaultKeymap, ...historyKeymap, shiftRedo, ...searchKeymap, indentWithTab]
          EditorView.updateListener.of (update) ->
            return unless update.docChanged
            scheduleSave()
            reportLines()
        ]
    beans.onChanged applyExternal
    # pagehide rather than beforeunload: it comes once the page is really
    # leaving, and both reached main every time (Claude, 2026-10-06).
    window.addEventListener 'pagehide', flush
    beans.onVim setVim
    beans.vim().then setVim
    beans.onHistory fromMenu
    reportLines()
    view

  load: (name) ->
    await save()          # the outgoing sketch may have an unflushed edit
    text        = asHeld await beans.read name
    current     = name
    lastWritten = text
    view.dispatch
      changes:   {from: 0, to: view.state.doc.length, insert: text}
      selection: {anchor: 0}
    name

  name:      -> current
  all:       -> view.state.doc.toString()
  evalRegion: -> view.focus(); evalRegion()
  showLine:  showLine
  showError: showError
  jumpTo:    jumpTo
  view:      -> view
  save:   save
  focus:  -> view.focus()

  vimKeys: -> vimSlot.get(view.state) is VIM
  dirty:   isDirty

  isCommand:       (line) -> COMMAND_LINE.test line
  command:         command
  defineCommand:   defineCommand
  undefineCommand: undefineCommand
  commands:        -> (entry.name for entry in COMMANDS)

globalThis.Editor = Editor
