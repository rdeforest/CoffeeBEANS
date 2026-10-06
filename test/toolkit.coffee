# Everything a part needs to drive the real app, in one object. A part takes
# only the handles it uses, so its first line says what it touches.

path                  = require 'path'
{Menu, BrowserWindow} = require 'electron'

wait = (ms) -> new Promise (resolve) -> setTimeout resolve, ms

module.exports = (win, paths) ->
  t =
    paths:    paths
    wait:     wait
    failures: 0
    scratch:  path.join paths.sketches, 'scratch.coffee'

  t.js = (code) -> win.webContents.executeJavaScript "(async () => { #{code} })()", yes

  t.check = (name, ok, detail = '') ->
    t.failures += 1 unless ok
    console.log "#{if ok then 'PASS' else 'FAIL'}  #{name}#{if detail then "   #{detail}" else ''}"

  # --- the editor -------------------------------------------------------------

  t.setDoc = (text) -> t.js """
    const v = Editor.view()
    v.dispatch({ changes: { from: 0, to: v.state.doc.length, insert: #{JSON.stringify text} } })
    return v.state.doc.length
  """

  t.cursorOnLine = (n) -> t.js """
    const v = Editor.view()
    v.dispatch({ selection: { anchor: v.state.doc.line(#{n}).from } })
    return #{n}
  """

  t.selectLines = (a, b) -> t.js """
    const v = Editor.view()
    v.dispatch({ selection: { anchor: v.state.doc.line(#{a}).from, head: v.state.doc.line(#{b}).to } })
    return true
  """

  # Until the editor shows `wanted`, rather than a sleep that guesses how long
  # a watcher event, a read and an IPC round trip take. Hands back what it saw
  # last, so a failing check can say what arrived instead.
  t.untilDoc = (wanted, limit = 3000) ->
    deadline = Date.now() + limit
    loop
      doc = await t.js "return Editor.all()"
      return doc if doc is wanted or Date.now() > deadline
      await wait 25

  # Until the page answers `probe` with something truthy, and that answer.
  t.waitFor = (probe, limit = 3000) ->
    deadline = Date.now() + limit
    loop
      seen = await t.js probe
      return seen if seen or Date.now() > deadline
      await wait 25

  # Keys as the OS would deliver them, to whatever has the page's focus. A
  # keydown dispatched by hand reaches CodeMirror's keymaps but never inserts
  # text, so it cannot tell an editor that types `:` from one that swallows it.
  t.type = (text) ->
    for key in text
      win.webContents.sendInputEvent type: 'keyDown', keyCode: key
      win.webContents.sendInputEvent type: 'char',    keyCode: key
      win.webContents.sendInputEvent type: 'keyUp',   keyCode: key
    undefined

  # A keydown straight into the editor, for the bindings: same-tick, so a
  # check can read what it did before anything else gets a turn.
  t.chord = (key, mods = {}) -> t.js """
    const down = new KeyboardEvent('keydown', { key: #{JSON.stringify key},
      ctrlKey: #{!!mods.ctrl}, shiftKey: #{!!mods.shift}, bubbles: true, cancelable: true })
    Editor.view().contentDOM.dispatchEvent(down)
    return down.defaultPrevented
  """

  # --- Edit > Vim Keys ------------------------------------------------------

  # The real menu item, clicked the way the menu clicks it, and then until the
  # editor has followed -- the menu tells the page over IPC.
  t.vimItem = -> Menu.getApplicationMenu().getMenuItemById 'vim'

  t.vimKeys = (wanted) ->
    item = t.vimItem()
    item.click() unless item.checked is wanted
    await t.waitFor "return Editor.vimKeys() === #{wanted}"

  t.vimState = ->
    menu:   t.vimItem()?.checked
    editor: await t.js "return Editor.vimKeys?.()"

  # Through the real ex parser, so :help and :target are tested the way they
  # are typed rather than by calling the handler behind them. Needs vim on.
  t.handleEx  = (cmd) -> t.js "CM.Vim.handleEx(CM.getCM(Editor.view()), #{JSON.stringify cmd}); return true"
  t.linesText = -> t.js "return document.getElementById('lines').textContent"
  t.overLine  = -> t.js "return (document.querySelector('.cm-over-limit') || {}).textContent ?? null"
  t.overRed   = -> t.js "return document.getElementById('lines').classList.contains('over')"

  # --- the app around it ------------------------------------------------------

  t.click        = (id) -> t.js "document.getElementById('#{id}').click(); return true"
  # There is no button for the whole buffer any more -- it is `/eval`, through
  # the command table, which answers with or without vim.
  t.evalAll      = -> t.js "Editor.command('/eval'); return true"
  t.status       = -> t.js "return document.getElementById('status').textContent"
  t.consoleText  = -> t.js "return document.getElementById('console').textContent"
  t.clearConsole = -> t.js "document.getElementById('console').innerHTML = ''; return true"

  t.evalRegion = -> t.js "Editor.evalRegion(); return true"

  # The console, once the run that filled it has finished. A fixed sleep was
  # only ever a guess at how long a sketch takes, and on a busy machine the
  # guess is wrong: every check then reads the *previous* test's output, which
  # is a suite that lies rather than one that fails.
  #
  # "The run finished" is still not "everything it printed is on screen": the
  # ring drains on one 16ms timer and the console flushes on another. Asking
  # whether anything is still in flight beats watching the text stop moving,
  # which cannot tell a finished console from a late one -- and on a busy
  # machine a late one reads as empty.
  t.quiet = (limit = 5000) ->
    deadline = Date.now() + limit
    loop
      return true unless await t.js "return Printing.pending()"
      return false if Date.now() > deadline
      await wait 20

  t.settled = (limit = 30000) ->
    await t.settle limit
    await t.quiet()
    await t.consoleText()

  # Asks, then waits for the answer however long the sketch takes to reach a
  # yield point, and hands back only what the console gained. Through
  # Prompt.ask rather than the keystroke, except where the keystroke is the
  # thing under test.
  t.ask = (line, limit = 15000) ->
    before = (await t.consoleText()).length
    await t.js "Prompt.ask(#{JSON.stringify line}); return true"
    deadline = Date.now() + limit
    loop
      break unless await t.js "return Prompt.pending()"
      break if Date.now() > deadline
      await wait 25
    await t.quiet()
    (await t.consoleText())[before..]

  t.pause  = -> t.js "Stepping.pause(); return true"
  t.step   = -> t.js "Stepping.step(); return true"
  t.go     = -> t.js "Stepping.go(); return true"

  t.key = (kind, code) -> t.js """
    const stage = document.getElementById('stage')
    stage.focus()
    stage.dispatchEvent(new KeyboardEvent('#{kind}', { code: '#{code}', bubbles: true }))
    return true
  """

  # A second page of the app, brought up from nothing the way a launch brings
  # one up, asked `probe` until it answers, and closed. Not a reload of the
  # window under test: on Linux a page reloaded inside a minimised window gets
  # no animation frames at all, backgroundThrottling or not -- a shown window
  # ran 144.5 rAF/s before and after a reload, a shown-then-minimised one 144
  # before and 0 after every reload, its sketch stuck `running` (measured by a
  # Claude reviewer, 2026-10-05). A hidden Linux test run shows its window and
  # then minimises it, so reloading it would stall the present loop for every
  # part after. `query` is the URL's, for a part that drives the boot.
  t.freshPage = (probe, limit = 15000, query = '') ->
    page = new BrowserWindow
      show: no
      webPreferences:
        contextIsolation: yes
        nodeIntegration:  no
        preload:          path.join paths.root, 'src', 'main', 'preload.js'
    page.webContents.setAudioMuted yes
    try
      await page.loadURL "app://beans/src/renderer/index.html#{query}"
      deadline = Date.now() + limit
      loop
        seen = await page.webContents.executeJavaScript "(async () => { #{probe} })()", yes
        return seen if seen or Date.now() > deadline
        await wait 25
    finally
      page.destroy()

  # --- between parts ----------------------------------------------------------

  # Polled rather than slept: a boot takes what it takes, and most of them take
  # far less than the wait we would otherwise have to guess at.
  t.settle = (limit = 5000) ->
    deadline = Date.now() + limit
    loop
      state = await t.status()
      return state unless state in ['arming', 'booting', 'running']
      return state if Date.now() > deadline
      await wait 50

  # A part must not inherit what the last one left behind -- a live double
  # buffer, a drawTo, a colour, a shadowed command -- or it fails for reasons
  # that have nothing to do with what it is testing, and running it on its own
  # means something different from running it in the middle of everything else.
  #
  # Scratch first, and only then blank the buffer: Editor.load flushes the
  # outgoing text to whatever sketch is *current*, so blanking while a real
  # sketch is open would autosave the emptiness straight over it.
  #
  # Vim is off at the start of every part, the way a fresh install has it, and
  # a part that drives vim turns it on. What the app came up with is kept
  # first, for the check that a fresh install has no vim.
  t.reset = ->
    t.launched ?= await t.vimState()
    await t.vimKeys off
    await t.js "await Editor.load('scratch'); return true"
    await t.setDoc ''
    await wait 400                   # past the autosave debounce
    await t.click 'runFresh'
    await t.settle()
    await t.clearConsole()
    undefined

  t
