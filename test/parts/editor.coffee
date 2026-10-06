# The editor is the program: mounting, vim, region extraction,
# autosave, reloads from disk, :e, :target and :help, and the command table
# the prompt shares with vim.

fsp      = require 'fs/promises'
path     = require 'path'
Settings = require '../../src/main/settings'

# How vim saves by default: the old file renamed aside, a new one written in
# its place, the backup removed. Every save is a new inode -- the case that
# broke Linux reloads on 2026-10-04, and one an in-place writeFile never
# exercises, because it keeps the inode.
vimSave = (file, text) ->
  await fsp.rename file, "#{file}~"
  await fsp.writeFile file, text, 'utf8'
  await fsp.rm "#{file}~"

# CodeMirror's Mod: Cmd on a Mac, Ctrl elsewhere.
onMac = process.platform is 'darwin'

module.exports = (t) ->
  {js, wait, check, setDoc, cursorOnLine, selectLines, consoleText,
   clearConsole, handleEx, linesText, overLine, overRed, paths, scratch,
   settled, evalRegion, untilDoc, asHeld} = t
  {waitFor, type, chord, vimKeys, vimItem} = t

  # 1. the editor is mounted, with ordinary keys unless Edit > Vim Keys says
  # otherwise (Robert, 2026-10-04: most people on Steam will not want vim).
  mounted = await js "return !!document.querySelector('.cm-editor')"
  check 'editor mounts', mounted

  # What the app came up with, before any part touched the setting. A run
  # starts from an empty data folder, so this is a fresh install.
  check 'a fresh install edits with ordinary keys, and Edit > Vim Keys is unticked',
    t.launched?.menu is false and t.launched?.editor is false, JSON.stringify t.launched

  await js "await Editor.load('scratch'); return true"

  # Typed, not dispatched: the OS's keys, into the focused editor.
  caretAtEnd = "Editor.focus(); const v = Editor.view(); v.dispatch({selection: {anchor: v.state.doc.length}}); return true"
  vimPanel   = "return !!document.querySelector('.cm-vim-panel')"
  await setDoc "a = 1\n"
  await js caretAtEnd
  await type ':'
  typed = await untilDoc "a = 1\n:"
  check 'with ordinary keys, : types a colon into the buffer',
    typed is "a = 1\n:" and not (await js vimPanel), JSON.stringify typed

  # The switch is live and keeps everything: the text, the cursor, and the
  # undo history. The cursor move between the two edits keeps them separate
  # undo steps, so one undo afterwards takes back only the X.
  editorState = -> js """
    const v = Editor.view()
    return {doc: v.state.doc.toString(), head: v.state.selection.main.head}
  """
  await setDoc "one\ntwo\n"
  await cursorOnLine 2
  await js "const v = Editor.view(); v.dispatch({changes: {from: 4, insert: 'X'}, selection: {anchor: 6}}); Editor.focus(); return true"
  before = await editorState()
  await vimKeys yes
  # codemirror-vim draws its block cursor on the next animation frame, so it
  # is waited for rather than read once. The suite has seen the window draw
  # before any part runs (suite.coffee), so the 3s is the switch's alone.
  fat     = await waitFor "return !!document.querySelector('.cm-fat-cursor')"
  ticked  = await editorState()
  await type ':'
  panel   = await waitFor vimPanel
  untyped = await js "return Editor.all()"
  check 'ticking Vim Keys switches to vim live, keeping the buffer and the cursor',
    fat and vimItem().checked and JSON.stringify(ticked) is JSON.stringify(before),
    JSON.stringify {fat, before, ticked}
  check 'and then : opens vim\'s command line instead of typing',
    panel and untyped is before.doc, JSON.stringify {panel, untyped}

  await js "CM.Vim.handleKey(CM.getCM(Editor.view()), '<Esc>'); Editor.focus(); return true"
  await vimKeys no
  gone = await waitFor "return !document.querySelector('.cm-fat-cursor') && !document.querySelector('.cm-vim-panel')"
  unticked = await editorState()
  await chord 'z', if onMac then {meta: yes} else {ctrl: yes}
  undone = await js "return Editor.all()"
  check 'unticking it switches back live, keeping the buffer, the cursor and the undo history',
    gone and not vimItem().checked and JSON.stringify(unticked) is JSON.stringify(before) and undone is "one\ntwo\n",
    JSON.stringify {gone, unticked, undone}

  # A selection made with ordinary keys is vim's to act on once vim is on.
  await setDoc "one\ntwo\nthree\n"
  await js "const v = Editor.view(); v.dispatch({selection: {anchor: 4, head: 7}}); Editor.focus(); return true"
  await vimKeys yes
  await type 'd'
  cut = await untilDoc "one\n\nthree\n"
  await js "CM.Vim.handleKey(CM.getCM(Editor.view()), '<Esc>'); return true"
  await vimKeys no
  check 'a selection made before ticking Vim Keys is the one vim\'s d deletes',
    cut is "one\n\nthree\n", JSON.stringify cut

  # The keys that make the editor a place to run code, in both modes.
  untilDisk = (wanted, limit = 3000) ->
    deadline = Date.now() + limit
    loop
      text = asHeld await fsp.readFile scratch, 'utf8'
      return text if text is wanted or Date.now() > deadline
      await wait 25

  for vimOn in [no, yes]
    await vimKeys vimOn
    named = if vimOn then 'with vim keys' else 'with ordinary keys'

    await setDoc "print 'FIRST'\n\nprint 'SECOND'\n"
    await cursorOnLine 3
    await clearConsole()
    await chord 'Enter', ctrl: yes
    text = await settled()
    check "#{named}, Ctrl-Enter evals the paragraph at the cursor",
      text.includes('SECOND') and not text.includes('FIRST'), JSON.stringify text.trim()

    await setDoc "print 'FRESH'\n"
    await clearConsole()
    await chord 'Enter', ctrl: yes, shift: yes
    text = await settled()
    check "#{named}, Ctrl-Shift-Enter runs in a fresh worker",
      text.includes('fresh worker') and text.includes('FRESH'), JSON.stringify text.trim()

    # Saved by the key, not by the autosave a moment later: the edit is
    # pending until Ctrl-S and not after, all inside one turn of the page.
    wanted = "print 'SAVED #{vimOn}'\n"
    saved = await js """
      const v = Editor.view()
      v.dispatch({changes: {from: 0, to: v.state.doc.length, insert: #{JSON.stringify wanted}}})
      const pending = Editor.dirty()
      v.contentDOM.dispatchEvent(new KeyboardEvent('keydown',
        {key: 's', code: 'KeyS', ctrlKey: true, bubbles: true, cancelable: true}))
      return {pending, after: Editor.dirty()}
    """
    onDisk = await untilDisk wanted
    check "#{named}, Ctrl-S saves at once",
      saved.pending and not saved.after and onDisk is wanted, JSON.stringify {saved, onDisk}

  # Unclaimed, Ctrl-r is View > Reload, which takes an edit still waiting for
  # its autosave down with it. sendInputEvent never reaches a menu
  # accelerator, so this asks whether the editor claimed the key.
  await vimKeys no
  claimed = await chord 'r', ctrl: yes
  check 'with ordinary keys, the editor claims Ctrl-r so it cannot reload the page', claimed

  # ...and with vim on, vim still has it: redo in normal mode.
  await vimKeys yes
  await setDoc "abc\n"
  redo = await js """
    const v = Editor.view(), cm = CM.getCM(v)
    CM.Vim.handleKey(cm, '<Esc>')
    v.dispatch({selection: {anchor: 0}})
    CM.Vim.handleKey(cm, 'x')
    const cut = Editor.all()
    CM.Vim.handleKey(cm, 'u')
    const undone = Editor.all()
    v.contentDOM.dispatchEvent(new KeyboardEvent('keydown',
      {key: 'r', ctrlKey: true, bubbles: true, cancelable: true}))
    return {cut, undone, redone: Editor.all()}
  """
  check 'with vim keys, Ctrl-r in normal mode still redoes',
    redo.cut is "bc\n" and redo.undone isnt redo.cut and redo.redone is redo.cut, JSON.stringify redo

  # Everything below drives vim's command line.
  await vimKeys yes
  await js "await Editor.load('scratch'); return true"

  # 2. edits reach disk without an explicit save
  await setDoc "print 'autosave check'\n"
  await wait 600
  onDisk = asHeld await fsp.readFile scratch, 'utf8'
  check 'autosave writes to disk', onDisk is "print 'autosave check'\n", JSON.stringify onDisk

  # 3. eval-region runs only the paragraph under the cursor
  await setDoc "print 'FIRST'\n\nprint 'SECOND'\n"
  await wait 500
  await clearConsole()
  await cursorOnLine 3
  await evalRegion()
  text = await settled()
  check 'region runs paragraph at cursor', text.includes('SECOND') and not text.includes('FIRST'), JSON.stringify text.trim()

  # 4. a cursor inside a definition runs the whole definition
  await setDoc "sketchy = ->\n  print 'CALLED'\n\nsketchy()\n"
  await wait 500
  await clearConsole()
  await cursorOnLine 2
  await evalRegion()
  defined = await settled()
  await cursorOnLine 4
  await evalRegion()
  text = await settled()
  check 'cursor in a definition runs the definition', defined.trim() is '' and text.includes('CALLED'), JSON.stringify text.trim()

  # 5. an explicitly selected indented region is dedented before it compiles
  await setDoc "if true\n  print 'INDENTED'\n  print 'STILL'\n"
  await wait 500
  await clearConsole()
  await selectLines 2, 3
  await evalRegion()
  text = await settled()
  check 'selected indented region dedents', text.includes('INDENTED') and text.includes('STILL') and not text.toLowerCase().includes('error'), JSON.stringify text.trim()

  # 8. a write from outside (vim) is picked up
  await fsp.writeFile scratch, "print 'FROM VIM'\n", 'utf8'
  await wait 700
  doc = await js "return Editor.all()"
  check 'external write reloads editor', doc is "print 'FROM VIM'\n", JSON.stringify doc

  # 8b. ...and keeps being picked up when every save is a new file. On Linux,
  # Node's recursive watch tracked each file's inode, so the first such save
  # was seen and every later one was not (Claude, 2026-10-04).
  seen = []
  for round in [1..3]
    text = "print 'VIM SAVE #{round}'\n"
    await vimSave scratch, text
    seen.push await untilDoc text
  check 'every rename-style save reloads, not just the first',
    seen.every((doc, index) -> doc is "print 'VIM SAVE #{index + 1}'\n"),
    JSON.stringify seen

  # A folder made by someone else while the app runs has to be watched too,
  # and a file in it saved the same way, more than once.
  outside = path.join paths.sketches, 'made-outside'
  await fsp.rm outside, recursive: yes, force: yes
  await fsp.mkdir outside
  later = path.join outside, 'later.coffee'
  await fsp.writeFile later, "print 'START'\n", 'utf8'
  await js "await Editor.load('made-outside/later'); return true"
  seen = []
  for round in [1..2]
    text = "print 'LATER #{round}'\n"
    await vimSave later, text
    seen.push await untilDoc text
  check 'a folder created outside the app is watched, every save',
    seen.every((doc, index) -> doc is "print 'LATER #{index + 1}'\n"),
    JSON.stringify seen
  await js "await Editor.load('scratch'); return true"
  await fsp.rm outside, recursive: yes, force: yes

  # A CRLF sketch (Notepad, Git for Windows' default checkout) is held with
  # \n by CodeMirror. Compared with the raw bytes it read dirty forever, so :e
  # refused to leave it, and switching away rewrote a file nobody had edited.
  crlf      = path.join paths.sketches, 'crlf.coffee'
  crlfBytes = "print 'ONE'\r\nprint 'TWO'\r\n"
  await fsp.writeFile crlf, crlfBytes, 'utf8'
  written = (await fsp.stat crlf).mtimeMs
  await js "await Editor.load('crlf'); return true"
  loaded = await js "return {doc: Editor.all(), dirty: Editor.dirty()}"
  check 'a CRLF sketch loads clean',
    loaded.doc is "print 'ONE'\nprint 'TWO'\n" and not loaded.dirty, JSON.stringify loaded
  # The symptom as the author met it: /e through the prompt, not Editor.load.
  await clearConsole()
  said     = await t.ask '/e scratch'
  switched = await waitFor "return Editor.name() === 'scratch'"
  check '/e leaves an unedited CRLF sketch without "no write since last change"',
    switched and not said.includes('no write since'), JSON.stringify {switched, said: said.trim()}
  left = {bytes: (await fsp.readFile crlf, 'utf8'), mtime: (await fsp.stat crlf).mtimeMs}
  check 'switching away from an unedited CRLF sketch leaves the file alone',
    left.bytes is crlfBytes and left.mtime is written, JSON.stringify {left, written}

  await js "await Editor.load('crlf'); return true"
  outsideBytes = "print 'THREE'\r\n"
  await fsp.writeFile crlf, outsideBytes, 'utf8'
  doc     = await untilDoc "print 'THREE'\n"
  applied = await js "const dirty = Editor.dirty(); await Editor.save(); return dirty"
  kept    = await fsp.readFile crlf, 'utf8'
  check 'an outside CRLF write is applied, clean, and not written back',
    doc is "print 'THREE'\n" and not applied and kept is outsideBytes,
    JSON.stringify {doc, applied, kept}
  await js "await Editor.load('scratch'); return true"
  await fsp.rm crlf

  # 9. :help goes through the real ex parser
  await clearConsole()
  await js "CM.Vim.handleEx(CM.getCM(Editor.view()), 'help'); return true"
  await wait 300
  text = await consoleText()
  check ':help lists every section',
    text.includes('Running code') and text.includes('Colors') and text.includes('Buffers')

  await clearConsole()
  await js "CM.Vim.handleEx(CM.getCM(Editor.view()), 'help colors'); return true"
  await wait 300
  text = await consoleText()
  check ':help <topic> narrows to one section',
    text.includes('Colors') and not text.includes('Running code')

  # 56. :help takes an object's name for its long form, and anything else
  # that is not a section is searched for, line by line
  helpFor = (topic) ->
    await clearConsole()
    await js "CM.Vim.handleEx(CM.getCM(Editor.view()), #{JSON.stringify "help #{topic}"}); return true"
    await wait 300
    consoleText()

  text = await helpFor 'keys'
  check ':help keys is the long form', text.includes('keys -- the keyboard') and text.includes('pagedown') and not text.includes('mouse.x'),
    JSON.stringify text.trim()[..200]

  text = await helpFor 'wheel'
  check ':help searches lines when no section matches',
    text.includes('mouse.wheel') and text.includes('Input') and not text.includes('keys.down'), JSON.stringify text.trim()

  text = await helpFor 'where fn'
  check ':help search keeps continuation lines and takes spaces',
    text.includes('where fn') and text.includes('p.hue'), JSON.stringify text.trim()

  text = await helpFor 'zzzz'
  check ':help with no match says so', text.includes('no help for "zzzz"'), JSON.stringify text.trim()

  # An example that does not run is worse than none, so the one that ends
  # (the others loop) is run as written: straight, then turned to touch.
  text = await helpFor 'overlaps'
  check ':help overlaps shows an example',
    text.includes('Example') and text.includes('turned = surface 13, 13'), JSON.stringify text.trim()[..200]

  example = await js "return HELP.match('overlaps')[0].example.join('\\n')"
  await setDoc example
  await clearConsole()
  await handleEx 'eval'
  text = await settled()
  check 'the overlaps example runs and both tests hit',
    text.trim() is 'truetrue', JSON.stringify text.trim()

  # 13. switching sketches must not drop an edit the autosave has not flushed
  await js "await Editor.load('scratch'); return true"
  await setDoc "print 'PENDING EDIT'\n"
  await js "await Editor.load('hello'); return true"
  await wait 700
  onDisk = await fsp.readFile scratch, 'utf8'
  check 'switching sketches flushes a pending edit', onDisk.includes('PENDING EDIT'), JSON.stringify onDisk
  # Back to scratch at once: anything that edits while a real sketch is
  # current would autosave test content straight over it.
  await js "await Editor.load('scratch'); return true"

  # 13a. the status line counts source lines, and a :target flags the overrun.
  # Goes through the real ex parser, the same path :help uses.


  await setDoc "# a comment\nprint 'one'\n\nprint 'two'\n"
  await wait 300
  check 'status line counts only source lines', (await linesText()) is '2 lines', JSON.stringify await linesText()

  # A comment is a comment however it is indented. `[^ #]` matched a tab, so a
  # tab-indented comment counted as source and so did a line of only tabs.
  await setDoc "print 'one'\n\t# tabbed comment\n\t\nprint 'two'\n"
  await wait 300
  check 'a tab-indented comment is not a source line',
    (await linesText()) is '2 lines', JSON.stringify await linesText()

  await setDoc "# a comment\nprint 'one'\n\nprint 'two'\n"
  await wait 300

  await handleEx 'target 3'
  await wait 200
  check 'a target above the count reads count/limit', (await linesText()) is '2/3 lines', JSON.stringify await linesText()
  check 'within the target nothing is flagged', (await overLine()) is null and (await overRed()) is false

  await handleEx 'target 1'
  await wait 200
  check 'over the target the count turns red', (await overRed()) is true
  check 'the first line past the target is flagged', (await overLine()) is "print 'two'", JSON.stringify await overLine()

  await handleEx 'target 0'
  await wait 200
  check ':target 0 clears the limit', (await overLine()) is null and (await overRed()) is false

  # 13b. :e switches sketches, creates them when new, and honours the dirty guard.
  await handleEx 'e hello'
  await wait 300
  check ':e switches to an existing sketch', (await js "return Editor.name()") is 'hello'

  created = path.join paths.sketches, 'ecreate.coffee'
  await fsp.rm created, force: yes
  await handleEx 'e ecreate.coffee'          # the .coffee he would type is stripped
  await wait 400
  made = false
  try
    await fsp.access created
    made = true
  listed = await js "return (await beans.list()).includes('ecreate')"
  check ':e newname creates, opens, and lists the sketch',
    (await js "return Editor.name()") is 'ecreate' and made and listed,
    "name=#{await js "return Editor.name()"} disk=#{made} listed=#{listed}"

  # Names are paths under sketches/, so folders work end to end.
  nested = path.join paths.sketches, 'sub', 'nested.coffee'
  await fsp.rm path.join(paths.sketches, 'sub'), recursive: yes, force: yes
  await handleEx 'e sub/nested'
  await wait 400
  onDisk = false
  try
    await fsp.access nested
    onDisk = true
  listed = await js "return (await beans.list()).includes('sub/nested')"
  check ':e sub/name creates the folder and lists the sketch by its path',
    (await js "return Editor.name()") is 'sub/nested' and onDisk and listed,
    "name=#{await js "return Editor.name()"} disk=#{onDisk} listed=#{listed}"
  await fsp.writeFile nested, "print 'NESTED FROM VIM'\n", 'utf8'
  await wait 700
  doc = await js "return Editor.all()"
  check 'an outside write in a folder reloads too', doc is "print 'NESTED FROM VIM'\n", JSON.stringify doc
  escaped = await js "try { await beans.read('../../escape'); return 'read' } catch (e) { return 'refused' }"
  check 'a name cannot climb out of sketches/', escaped is 'refused', escaped
  await js "await Editor.load('scratch'); return true"
  await fsp.rm path.join(paths.sketches, 'sub'), recursive: yes, force: yes

  await js "await Editor.load('scratch'); return true"
  await setDoc "print 'PENDING'\n"           # dirty: inside the 250ms save debounce
  await handleEx 'e hello'                    # must refuse and stay put
  await wait 100
  check ':e refuses to abandon a pending edit', (await js "return Editor.name()") is 'scratch'
  await wait 400                             # let that edit flush back to scratch
  await setDoc "print 'DISCARD ME'\n"
  await handleEx 'e! hello'                   # the bang drops it and switches
  await wait 400
  check ':e! discards the pending edit and switches', (await js "return Editor.name()") is 'hello'

  await fsp.rm created, force: yes
  # Back to scratch: the setDoc-heavy tests below must not autosave over a real one.
  await js "await Editor.load('scratch'); return true"

  # 45. saving leaves no staging files behind in the sketches folder
  await js "await Editor.load('scratch'); return true"
  await setDoc "print 'atomic'\n"
  await wait 700
  strays = (await fsp.readdir paths.sketches).filter (name) -> not name.endsWith '.coffee'
  check 'atomic save leaves nothing behind', strays.length is 0, strays.join ', '

  # --- one command table, two ways in --------------------------------------

  # Commands at the prompt, as `/` or `:`, from the same table vim's command
  # line uses (Robert's ask, 2026-10-04). Through Prompt.ask, the line the
  # Enter key sends; the keystroke itself is the repl part's business.
  {ask} = t
  await js "await Editor.load('scratch'); return true"

  await setDoc "print 'RAN FROM SLASH'\n"
  await wait 400
  await clearConsole()
  await ask '/run'
  text = await settled()
  check '/run at the prompt runs the buffer in a fresh worker',
    text.includes('fresh worker') and text.includes('RAN FROM SLASH'), JSON.stringify text.trim()

  await setDoc "print 'RAN FROM COLON'\n"
  await wait 400
  await clearConsole()
  await ask ':run'
  text = await settled()
  check ':run at the prompt does the same',
    text.includes('fresh worker') and text.includes('RAN FROM COLON'), JSON.stringify text.trim()

  # A regex can still open a line, in parens -- and without them it is a command.
  await clearConsole()
  text = await ask "(/a/).test 'a'"
  check 'a regex in parens at the prompt is CoffeeScript', text.includes('true'), JSON.stringify text.trim()

  await clearConsole()
  text = await ask "/a/.test 'a'"
  check 'a bare leading regex is taken as a command, not evaluated',
    text.includes('/a is not a command') and not text.includes('true'), JSON.stringify text.trim()

  await clearConsole()
  text = await ask '/foo'
  check 'an unknown command says so and names the real ones',
    text.includes('/foo is not a command') and
      ['/run', '/restart', '/eval', '/edit', '/help', '/target', '/pause', '/step', '/continue', '/line', '/write']
        .every((name) -> text.includes name),
    JSON.stringify text.trim()

  await clearConsole()
  text = await ask ':foo'
  check 'and names them with the mark that was typed',
    text.includes(':foo is not a command') and text.includes(':run') and not text.includes('/run'),
    JSON.stringify text.trim()

  # The same argument from both entrances. A command defined after mount is
  # one table entry; vim and the prompt must both find it, by its full name
  # and its short one, and hand it the same argument -- the bang included.
  probed = await js """
    if (!Editor.defineCommand) return 'no Editor.defineCommand'
    globalThis.probed = []
    Editor.defineCommand({name: 'zzprobe', short: 'zzp', run: (arg) => probed.push(arg)})
    return true
  """
  if probed is true
    await ask '/zzprobe one  two'
    await handleEx 'zzprobe one  two'
    await ask ':zzp! x'
    await handleEx 'zzp! x'
    await ask '/zzp'
    await handleEx 'zzp'
    probed = await js "return probed"
  check 'one table entry, reached from the prompt and from vim with the same argument',
    JSON.stringify(probed) is JSON.stringify(['one  two', 'one  two', '! x', '! x', '', '']),
    JSON.stringify probed
  await js "Editor.undefineCommand?.('zzprobe'); return true"

  # An entry with no short form is reached by its whole name from both sides.
  # Vim falls back to the name by itself; the prompt has to be told.
  bare = await js """
    globalThis.bare = []
    Editor.defineCommand({name: 'zzbare', run: (arg) => bare.push(arg)})
    return true
  """
  await ask '/zzbare hi'
  await handleEx 'zzbare hi'
  bare = await js "return bare"
  check 'an entry without a short form answers its full name at the prompt and in vim',
    JSON.stringify(bare) is JSON.stringify(['hi', 'hi']), JSON.stringify bare
  await js "Editor.undefineCommand?.('zzbare'); return true"

  # Both probes gone again, or every later part in a full run would list and
  # complete them, and a part alone would differ from the same part mid-suite.
  await clearConsole()
  text = await ask '/zzprobe'
  check 'a command the editor part defined is gone after it',
    text.includes('/zzprobe is not a command') and not text.includes('/zzbare'), JSON.stringify text.trim()

  # Real commands that take arguments, from the prompt.
  await setDoc "# a comment\nprint 'one'\n\nprint 'two'\n"
  await wait 300
  await ask '/target 3'
  set = await linesText()
  await ask '/tar 0'
  cleared = await linesText()
  check '/target n at the prompt sets the target, and /tar 0 clears it',
    set is '2/3 lines' and cleared is '2 lines', "set=#{JSON.stringify set} cleared=#{JSON.stringify cleared}"

  # A bare /target, no number at all, clears too -- from either side.
  cleared = {}
  for [side, give] in [['prompt', (line) -> ask "/#{line}"], ['vim', handleEx]]
    await give 'target 3'
    await wait 200
    set = await linesText()
    await give 'target'
    await wait 200
    cleared[side] = [set, await linesText()]
  check 'a bare /target at the prompt (and :target in vim) clears a set target',
    JSON.stringify(cleared) is JSON.stringify(prompt: ['2/3 lines', '2 lines'], vim: ['2/3 lines', '2 lines']),
    JSON.stringify cleared

  await clearConsole()
  text = await ask '/help colors'
  check '/help <topic> at the prompt narrows to one section',
    text.includes('Colors') and not text.includes('Running code'), JSON.stringify text.trim()[..200]

  # Several words are one topic, searched for line by line, and a run of
  # spaces between them is one space -- the same at the prompt as in vim.
  await clearConsole()
  fromPrompt = await ask '/help where   fn'
  fromVim    = await helpFor 'where   fn'
  check '/help <a> <b> at the prompt searches the same as :help <a> <b> in vim',
    fromPrompt.includes('where fn') and fromPrompt.includes('p.hue') and
      fromPrompt.trim() is "> /help where   fn#{fromVim.trim()}",
    JSON.stringify(prompt: fromPrompt.trim()[..200], vim: fromVim.trim()[..200])

  check 'help shows the / form of the commands',
    await js "return HELP.match('running')[0].lines.some(([syntax]) => syntax === '/run')"

  # Ordinary keys come first (Robert, 2026-10-04: most people on Steam will
  # not want vim), so nothing in Running code works only with vim on, and vim
  # has a section of its own that says how to switch it on.
  shape = await js """
    const text = (section) => section.lines.map((line) => line.join(' ')).join(' | ')
    const vim  = HELP.sections.find((section) => section.name === 'vim')
    return {running: /vim|visual mode/i.test(text(HELP.match('running')[0])),
            switch:  !!vim && text(vim).includes('Edit > Vim Keys'),
            visual:  !!vim && text(vim).includes('visual mode')}
  """
  check 'help leads with ordinary keys, and vim has its own section',
    JSON.stringify(shape) is JSON.stringify(running: no, switch: yes, visual: yes), JSON.stringify shape

  await wait 400                             # let the target edits flush
  await ask '/e hello'
  await wait 300
  check '/e name at the prompt switches sketches', (await js "return Editor.name()") is 'hello'
  await js "await Editor.load('scratch'); return true"

  # A bare /e! reloads the open sketch from disk and drops the edit not yet
  # saved. Had the edit been flushed instead -- by the reload's own save, or
  # by the debounce -- the buffer and the file would both read DROPPED.
  reloaded = {}
  for [side, give] in [['prompt', (line) -> ask "/#{line}"], ['vim', handleEx]]
    await setDoc "print 'KEPT'\n"
    await wait 600                           # past the save debounce: on disk
    await setDoc "print 'DROPPED'\n"         # inside it: pending
    await give 'e!'
    await wait 500                           # longer than a save would take
    reloaded[side] =
      name:    await js "return Editor.name()"
      doc:     await js "return Editor.all()"
      disk:    await fsp.readFile scratch, 'utf8'
  want = {name: 'scratch', doc: "print 'KEPT'\n", disk: "print 'KEPT'\n"}
  check 'a bare /e! at the prompt (and :e! in vim) reloads the sketch, discarding the edit',
    JSON.stringify(reloaded) is JSON.stringify(prompt: want, vim: want),
    JSON.stringify reloaded

  # --- the choice is remembered ---------------------------------------------

  # Written to the data folder, staged and renamed into place, and read back
  # by Settings.read, which is what a launch calls before it builds the menu;
  # and a page built from nothing, as a reload or a launch builds one, comes
  # up with vim on while the menu stays ticked. A cold launch itself is not
  # exercised: the suite runs inside the one it has.
  file = path.join paths.data, 'settings.json'
  await vimKeys yes
  stored  = Settings.read file
  staging = (await fsp.readdir paths.data).filter (name) -> name.endsWith '.saving'
  back    = await t.freshPage "return typeof Editor !== 'undefined' && !!Editor.view() && Editor.vimKeys()"
  check 'Vim Keys survives a reload (a page built afresh), and is saved where a launch reads it',
    stored.vim is true and staging.length is 0 and back and vimItem().checked,
    JSON.stringify {stored, staging, back}

  # A settings file the app did not write, or a write cut short, must not cost
  # the launch: `null` used to crash the menu before any window opened.
  probe  = path.join paths.data, 'settings-probe.json'
  broken = ['null', '5', '"x"', '[true]', '{"vim": tr', '']
  read   = for text in broken
    await fsp.writeFile probe, text, 'utf8'
    Settings.read probe
  await fsp.rm probe
  check 'a settings file that is not a JSON object reads as every default',
    read.every((found) -> JSON.stringify(found) is '{}'), JSON.stringify read

  # --- Edit > Undo and Redo -------------------------------------------------

  # The real menu items, clicked the way the menu clicks them, handed the
  # window because a hidden test run has none focused. On a Mac they are the
  # only way Cmd-Z reaches the prompt (K7, 2026-10-06), and no Mac runs this;
  # what runs here is that each click goes to the history that has focus, and
  # takes one step there. A step is a paste so that CodeMirror never joins
  # two of them into one, as it joins edits typed close together.
  {Menu, BrowserWindow} = require 'electron'
  win      = BrowserWindow.getAllWindows()[0]
  fromMenu = (id) -> Menu.getApplicationMenu().getMenuItemById(id)?.click undefined, win, win.webContents
  pasted   = -> js """
    const v = Editor.view()
    v.focus()
    v.dispatch({ changes: { from: 0, insert: 'X' }, userEvent: 'input.paste' })
    v.dispatch({ changes: { from: v.state.doc.length, insert: 'Y' }, userEvent: 'input.paste' })
    return document.activeElement === v.contentDOM && v.state.doc.toString()
  """

  # The prompt's edit goes through insertText, as the prompt's own keys do,
  # which is one step of the input's native undo. This check alone would
  # pass if every click took the native step; the two after it would not.
  promptLine = -> js "return document.getElementById('promptLine').value"
  until_ = (wanted) -> waitFor "return document.getElementById('promptLine').value === #{JSON.stringify wanted}"
  await js """
    const line = document.getElementById('promptLine')
    line.value = 'keep'
    line.focus()
    line.setSelectionRange(4, 4)
    document.execCommand('insertText', false, ' more')
    return true
  """
  typed = await promptLine()
  fromMenu 'undo'
  undone = await until_ 'keep'
  undid  = await promptLine()
  fromMenu 'redo'
  redone = await until_ 'keep more'
  check 'Edit > Undo and Redo undo and redo an edit at the prompt',
    typed is 'keep more' and undone and redone,
    "typed=#{JSON.stringify typed} undo=#{JSON.stringify undid} redo=#{JSON.stringify await promptLine()}"

  # From the canvas, nothing: the page has one native undo stack, and its
  # last step is that redo at the prompt. A listener behind the editor's on
  # the menu's message says when the click has been handled.
  await js """
    window.menuHandled = 0
    beans.onHistory(() => window.menuHandled++)
    document.getElementById('stage').focus()
    return true
  """
  fromMenu 'undo'
  handled = await waitFor "return window.menuHandled > 0"
  kept    = await promptLine()
  check 'Edit > Undo with the canvas focused leaves the prompt alone',
    handled and kept is 'keep more', "handled=#{handled} prompt=#{JSON.stringify kept}"
  await js "document.getElementById('promptLine').value = ''; return true"

  # Typing in the editor is a native step too, and Edit > Undo at the prompt
  # takes it. Through main's webContents.undo it reaches CodeMirror as an
  # undo of its own; document.execCommand in the page instead took one q out
  # of the editor's DOM behind CodeMirror's back, which read that as an edit,
  # `baseq`, and saved it (found by a Claude reviewer, 2026-10-06). Vim is
  # off for it: the reload check above left it on, and in normal mode q
  # types nothing.
  await vimKeys off
  await setDoc 'base'
  await js caretAtEnd
  await type 'qq'
  typedIn = await untilDoc 'baseqq'
  await js "document.getElementById('promptLine').focus(); return true"
  fromMenu 'undo'
  undoneIn = await untilDoc 'base'
  prompt   = await promptLine()
  check 'Edit > Undo at the prompt, after typing in the editor, undoes there through CodeMirror',
    typedIn is 'baseqq' and undoneIn is 'base' and prompt is '',
    JSON.stringify {typedIn, undoneIn, prompt}

  # Not the native undo the menu roles would send: CodeMirror answers that
  # from its own history only while Chromium's stack has something too, and
  # Redo after Undo found nothing there (measured by Claude, 2026-10-06).
  stepped = {}
  for vimOn in [off, on]
    await vimKeys vimOn
    await setDoc 'base'
    focused = await pasted()
    fromMenu 'undo'
    undid = await untilDoc 'Xbase'
    fromMenu 'redo'
    redid = await untilDoc 'XbaseY'
    stepped[if vimOn then 'vim' else 'keys'] = {focused, undid, redid}
  await vimKeys off
  want = {focused: 'XbaseY', undid: 'Xbase', redid: 'XbaseY'}
  check 'Edit > Undo and Redo take one CodeMirror step each in the editor, with and without Vim Keys',
    JSON.stringify(stepped) is JSON.stringify(keys: want, vim: want),
    JSON.stringify stepped

  # Ctrl-Z stays CodeMirror's on Linux and Windows, one step and not one
  # more from the menu as well: the menu shows Ctrl+Z there but does not
  # register it. Keys sent this way never reach a menu accelerator (see the
  # repl part), so this guards the editor's bindings, not the registration --
  # Ctrl-Shift-Z on Windows among them, which is ours, not CodeMirror's.
  mod = if onMac then 'meta' else 'control'
  key = (keyCode, modifiers) ->
    win.webContents.sendInputEvent {type: 'keyDown', keyCode, modifiers}
    win.webContents.sendInputEvent {type: 'keyUp',   keyCode, modifiers}
  await setDoc 'base'
  focused = await pasted()
  key 'z', [mod]
  undid = await untilDoc 'Xbase'
  key 'z', [mod, 'shift']
  redid = await untilDoc 'XbaseY'
  check 'Ctrl-Z and Ctrl-Shift-Z (Cmd on a Mac) in the editor take one CodeMirror step each',
    JSON.stringify({focused, undid, redid}) is JSON.stringify(want),
    JSON.stringify {focused, undid, redid}
  await setDoc ''

  # --- vim's autoindent -------------------------------------------------------

  # On an indented line `o` then Esc left the indent's spaces behind; in Vim
  # the line is blank (Robert, 2026-10-05). Each case below is what Vim 9.1
  # made of the same buffer, cursor line and keys -- `vim -u NONE -N -i NONE
  # -c 'set ai bs=indent,eol,start'`, driven by feedkeys, measured by Claude
  # on 2026-10-06; editor.coffee has the table and the rule it gives.
  #
  # All keys of a case go in one turn of the page, so the buffer is read after
  # the last of them and never between two. Vim's keys arrive as keydowns, the
  # way codemirror-vim takes them; a character typed in insert mode is the
  # transaction CodeMirror makes of typing, since a keydown made by hand
  # inserts nothing.
  await vimKeys yes
  await js "await Editor.load('scratch'); return true"
  START = "if x\n  foo\n  bar\nbaz\n"
  BLANK = "if x\n  foo\n\n  bar\nbaz\n"
  KEPT  = "if x\n  foo\n  \n  bar\nbaz\n"
  vimDid = (keys, line, doc = START) -> js """
    const v = Editor.view(), cm = CM.getCM(v)
    CM.Vim.handleKey(cm, '<Esc>')
    v.dispatch({changes: {from: 0, to: v.state.doc.length, insert: #{JSON.stringify doc}}})
    v.dispatch({selection: {anchor: v.state.doc.line(#{line}).from}})
    for (const key of #{JSON.stringify keys}) {
      const [, ctrl, name] = key.match(/^(Ctrl-)?(.+)$/)
      if (name.length === 1 && !ctrl && cm.state.vim.insertMode)
        v.dispatch(v.state.replaceSelection(name), {userEvent: 'input.type'})
      else
        v.contentDOM.dispatchEvent(new KeyboardEvent('keydown',
          {key: name, ctrlKey: !!ctrl, bubbles: true, cancelable: true}))
    }
    CM.Vim.handleKey(cm, '<Esc>')
    return Editor.all()
  """

  # Vc is not here: codemirror-vim's Vc on an indented line deletes the line
  # and its newline, where real Vim (and cc, S) leave a blank line -- the
  # plugin's own bug, found by a Claude reviewer of K5 on 2026-10-06.
  SPACES = "if x\n    \n  foo\nbaz\n"
  TWICE  = (made) -> "if x\n  foo\n#{made}\n  bar\n#{made}\nbaz\n"
  cases = [
    # what is typed                      on line  keys                                 what Vim left, from
    ['o Esc',                            2, ['o', 'Escape'],                           BLANK]
    ['O Esc',                            3, ['O', 'Escape'],                           BLANK]
    ['o Enter Enter Esc',                2, ['o', 'Enter', 'Enter', 'Escape'],         "if x\n  foo\n\n\n\n  bar\nbaz\n"]
    ['3o Esc',                           2, ['3', 'o', 'Escape'],                      "if x\n  foo\n\n\n\n  bar\nbaz\n"]
    ['o Down Esc',                       2, ['o', 'ArrowDown', 'Escape'],              BLANK]
    ['o Up Esc',                         2, ['o', 'ArrowUp', 'Escape'],                BLANK]
    ['o Ctrl-T Esc',                     2, ['o', 'Ctrl-t', 'Escape'],                 BLANK]
    ['cc Esc',                           2, ['c', 'c', 'Escape'],                      "if x\n\n  bar\nbaz\n"]
    ['S Esc',                            2, ['S', 'Escape'],                           "if x\n\n  bar\nbaz\n"]
    ['cj Esc',                           2, ['c', 'j', 'Escape'],                      "if x\n\nbaz\n"]
    ['o, two spaces typed, Esc',         2, ['o', ' ', ' ', 'Escape'],                 "if x\n  foo\n    \n  bar\nbaz\n"]
    ['o x Backspace Esc',                2, ['o', 'x', 'Backspace', 'Escape'],         KEPT]
    ['o Left Esc',                       2, ['o', 'ArrowLeft', 'Escape'],              KEPT]
    ['^C Esc (a change, not linewise)',  2, ['^', 'C', 'Escape'],                      "if x\n  \n  bar\nbaz\n"]
    ['o Esc u',                          2, ['o', 'Escape', 'u'],                      START]
    ['o Down Esc u',                     2, ['o', 'ArrowDown', 'Escape', 'u'],         START]
    ['cc Esc u',                         2, ['c', 'c', 'Escape', 'u'],                 START]
    ['o Esc u Ctrl-R',                   2, ['o', 'Escape', 'u', 'Ctrl-r'],            BLANK]
    ['o Ctrl-O 0 x Esc',                 2, ['o', 'Ctrl-o', '0', 'x', 'Escape'],       "if x\n  foo\nx\n  bar\nbaz\n"]
    ['A Esc on a line of spaces',        2, ['A', 'Escape'],                           "if x\n    \nbaz\n", "if x\n    \nbaz\n"]
    # Played back by a macro or by `.`. Before the fix (K5's fixer,
    # 2026-10-06) the first five each lost spaces: codemirror-vim records no
    # new last edit during a playback, so the cc before it still read as the
    # command that entered insert mode, and typing played back arrives inside
    # one vim command, where it read as indent. The take-back also shared an
    # undo step with the typing after the cc, which Ctrl-R showed. A lone `u`
    # there is not checked: codemirror-vim's undo splits cc from the typing
    # after it, with or without K5, where Vim undoes both.
    ['qqA Esc q, ccx Esc below, k @q',   2, ['q', 'q', 'A', 'Escape', 'q', 'j', 'c', 'c', 'x', 'Escape', 'k', '@', 'q'],
                                                                                           "if x\n    \n  x\nbaz\n", SPACES]
    ['the same, then u Ctrl-R',          2, ['q', 'q', 'A', 'Escape', 'q', 'j', 'c', 'c', 'x', 'Escape', 'k', '@', 'q', 'u', 'Ctrl-r'],
                                                                                           "if x\n    \n  x\nbaz\n", SPACES]
    ['qei Esc q, Sy Esc below, k @e',    2, ['q', 'e', 'i', 'Escape', 'q', 'j', 'S', 'y', 'Escape', 'k', '@', 'e'],
                                                                                           "if x\n    \n  y\nbaz\n", SPACES]
    ['qq o, two spaces, Esc q, j @q',    2, ['q', 'q', 'o', ' ', ' ', 'Escape', 'q', 'j', '@', 'q'], TWICE "    "]
    ['o, two spaces, Esc, j .',          2, ['o', ' ', ' ', 'Escape', 'j', '.'],       TWICE "    "]
    ['qq o Esc q, j @q',                 2, ['q', 'q', 'o', 'Escape', 'q', 'j', '@', 'q'], TWICE ""]
    ['o Esc, j .',                       2, ['o', 'Escape', 'j', '.'],                 TWICE ""]
    # A `.` inside a macro: codemirror-vim's repeat clears its playing flag as
    # it ends, though the macro still plays, so the spaces the macro typed
    # after it read as indent and were taken back. Failed before K5's second
    # fixer (Claude, 2026-10-06) decided playback once per vim command.
    ['jx qq . j o ·· Esc q, j x @q',     1, ['j', 'x', 'q', 'q', '.', 'j', 'o', ' ', ' ', 'Escape', 'q', 'j', 'x', '@', 'q'],
                                                                                           "if x\nfoo\n  bar\n    \n  q\n  zot\n    \nbaz\n",
                                                                                           "if x\n  foo\n  bar\n  qux\n  zot\nbaz\n"]
  ]
  for [typed, line, keys, wanted, doc] in cases
    got = await vimDid keys, line, doc
    check "with vim keys, #{typed} leaves the indent as Vim does",
      got is wanted, JSON.stringify {got, wanted}

  # Down on the last line goes nowhere, so the cursor never leaves it and the
  # Esc after takes the indent back. Vim wrote one more \n, its 'fixeol' at
  # :w, which is not an indent.
  got = await vimDid ['o', 'ArrowDown', 'Escape'], 2, "if x\n  foo"
  check 'with vim keys, o then Down on the last line, then Esc, leaves the line blank',
    got is "if x\n  foo\n", JSON.stringify got

  # The spaces typed through the OS this time, not dispatched: real typing is
  # what makes an indent the author's.
  await js """
    const v = Editor.view(), cm = CM.getCM(v)
    v.dispatch({changes: {from: 0, to: v.state.doc.length, insert: #{JSON.stringify START}}})
    v.dispatch({selection: {anchor: v.state.doc.line(2).from}})
    Editor.focus()
    CM.Vim.handleKey(cm, 'o')
    return true
  """
  await type '  '
  typed = await untilDoc "if x\n  foo\n    \n  bar\nbaz\n"
  await chord 'Escape'
  kept = await js "return Editor.all()"
  check 'with vim keys, spaces typed after o are kept at Esc, indent and all',
    kept is "if x\n  foo\n    \n  bar\nbaz\n", JSON.stringify {typed, kept}

  # A click on another line takes the indent back too, and a drag begun by
  # that click still selects: CodeMirror's mouse selection gives up on a drag
  # when it sees typing, which is what the take-back's undo label reads as.
  # DOM events into the page, never the real pointer.
  clicked = await js """
    const v = Editor.view(), cm = CM.getCM(v)
    CM.Vim.handleKey(cm, '<Esc>')
    v.dispatch({changes: {from: 0, to: v.state.doc.length, insert: #{JSON.stringify START}}})
    v.dispatch({selection: {anchor: v.state.doc.line(2).from}})
    Editor.focus()
    CM.Vim.handleKey(cm, 'o')
    const baz = v.state.doc.line(5), a = v.coordsAtPos(baz.from), b = v.coordsAtPos(baz.to)
    const at = (c, kind, target) => target.dispatchEvent(new MouseEvent(kind,
      {clientX: c.left + 1, clientY: (c.top + c.bottom) / 2, button: 0, buttons: 1, detail: 1,
       bubbles: true, cancelable: true}))
    at(a, 'mousedown', v.contentDOM)
    at(b, 'mousemove', document)
    at(b, 'mouseup', document)
    const {from, to} = v.state.selection.main
    CM.Vim.handleKey(cm, '<Esc>')
    return {doc: Editor.all(), selected: v.state.sliceDoc(from, to)}
  """
  check 'with vim keys, a click on another line after o takes the indent back, and its drag selects',
    clicked.doc is BLANK and clicked.selected is 'baz', JSON.stringify clicked

  # Ordinary keys are not vim: an indent nobody typed on stays.
  await vimKeys no
  plain = await js """
    const v = Editor.view()
    v.dispatch({changes: {from: 0, to: v.state.doc.length, insert: #{JSON.stringify START}}})
    v.dispatch({selection: {anchor: v.state.doc.line(2).to}})
    for (const key of ['Enter', 'Escape', 'ArrowDown'])
      v.contentDOM.dispatchEvent(new KeyboardEvent('keydown', {key, bubbles: true, cancelable: true}))
    return Editor.all()
  """
  check 'with ordinary keys, Enter then Esc and Down leave the new line its indent',
    plain is KEPT, JSON.stringify plain
