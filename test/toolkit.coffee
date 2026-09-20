# Everything a part needs to drive the real app, in one object. A part takes
# only the handles it uses, so its first line says what it touches.

path = require 'path'

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

  # Through the real ex parser, so :help and :target are tested the way they
  # are typed rather than by calling the handler behind them.
  t.handleEx  = (cmd) -> t.js "CM.Vim.handleEx(CM.getCM(Editor.view()), #{JSON.stringify cmd}); return true"
  t.linesText = -> t.js "return document.getElementById('lines').textContent"
  t.overLine  = -> t.js "return (document.querySelector('.cm-over-limit') || {}).textContent ?? null"
  t.overRed   = -> t.js "return document.getElementById('lines').classList.contains('over')"

  # --- the app around it ------------------------------------------------------

  t.click        = (id) -> t.js "document.getElementById('#{id}').click(); return true"
  # There is no button for the whole buffer any more -- it is `:eval`, through
  # the real ex parser, the same path :help and :target are tested on.
  t.evalAll      = -> t.handleEx 'eval'
  t.status       = -> t.js "return document.getElementById('status').textContent"
  t.consoleText  = -> t.js "return document.getElementById('console').textContent"
  t.clearConsole = -> t.js "document.getElementById('console').innerHTML = ''; return true"

  t.evalRegion = -> t.js "Editor.evalRegion(); return true"

  # The console, once the run that filled it has finished. A fixed sleep was
  # only ever a guess at how long a sketch takes, and on a busy machine the
  # guess is wrong: every check then reads the *previous* test's output, which
  # is a suite that lies rather than one that fails.
  t.settled = (limit = 30000) ->
    await t.settle limit
    await wait 60                  # the console flushes on a 16ms timer
    await t.consoleText()

  t.key = (kind, code) -> t.js """
    const stage = document.getElementById('stage')
    stage.focus()
    stage.dispatchEvent(new KeyboardEvent('#{kind}', { code: '#{code}', bubbles: true }))
    return true
  """

  # --- between parts ----------------------------------------------------------

  # Polled rather than slept: a boot takes what it takes, and most of them take
  # far less than the wait we would otherwise have to guess at.
  t.settle = (limit = 5000) ->
    deadline = Date.now() + limit
    loop
      state = await t.status()
      return state unless state in ['booting', 'running']
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
  t.reset = ->
    await t.js "await Editor.load('scratch'); return true"
    await t.setDoc ''
    await wait 400                   # past the autosave debounce
    await t.click 'runFresh'
    await t.settle()
    await t.clearConsole()
    undefined

  t
