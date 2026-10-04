# Where the keyboard goes after a run. Run and :eval hand it to the canvas;
# region eval leaves it in the editor; a syntax error puts the cursor on it;
# a runtime error shows its stack, marks the innermost line, and gives the
# prompt the keyboard until a frame is chosen. Robert asked for all of it on
# 2026-10-04.

fsp  = require 'fs/promises'
path = require 'path'

module.exports = (t) ->
  {js, wait, check, setDoc, selectLines, settle, click, handleEx, evalRegion, paths} = t

  # The element with the keyboard, named the way these checks talk about it.
  focused = -> js """
    const a = document.activeElement
    if (!a) return null
    if (a.closest('.cm-editor')) return 'editor'
    return a.id || a.tagName
  """

  # Polled: the canvas takes the keyboard a tick after a run, on purpose.
  untilFocused = (wanted, limit = 2000) ->
    deadline = Date.now() + limit
    loop
      now = await focused()
      return now if now is wanted or Date.now() > deadline
      await wait 20

  cursor = -> js """
    const v = Editor.view(), head = v.state.selection.main.head, line = v.state.doc.lineAt(head)
    return {line: line.number, column: head - line.from + 1}
  """

  errorLine = -> js """
    const marked = document.querySelector('.cm-error-line')
    if (!marked) return null
    const v = Editor.view()
    return v.state.doc.lineAt(v.posAtDOM(marked)).number
  """

  stack = -> js """
    const pane = document.getElementById('vars')
    return {
      shown:  !pane.hidden,
      frames: [...pane.querySelectorAll('.stack-frame')].map(f => f.querySelector('.stack-site').textContent),
    }
  """

  # Through vim's own command line -- the colon, the panel, Enter -- because
  # the trap is the panel focusing the editor as it closes, which calling the
  # ex handler directly would never exercise.
  typeEx = (command) -> js """
    const cm = CM.getCM(Editor.view())
    Editor.focus()
    CM.Vim.handleKey(cm, '<Esc>')        // in insert mode ':' would just type a colon
    CM.Vim.handleKey(cm, ':')
    const input = document.querySelector('.cm-vim-panel input')
    input.value = #{JSON.stringify command}
    const enter = new KeyboardEvent('keydown', { key: 'Enter', bubbles: true })
    Object.defineProperty(enter, 'keyCode', { get: () => 13 })
    input.dispatchEvent(enter)
    return true
  """

  quick = "screen 320, 200\ncls()\n"

  # --- runs hand the keyboard to the canvas ------------------------------------

  await setDoc quick
  await wait 400
  await js "Editor.focus(); return true"
  await click 'runFresh'
  await settle()
  check 'the Run button gives the canvas the keyboard', (await untilFocused 'stage') is 'stage', await focused()

  await js "Editor.focus(); return true"
  await js """
    Editor.view().contentDOM.dispatchEvent(new KeyboardEvent('keydown',
      { key: 'Enter', code: 'Enter', ctrlKey: true, shiftKey: true, bubbles: true, cancelable: true }))
    return true
  """
  await settle()
  check 'Ctrl-Shift-Enter gives the canvas the keyboard', (await untilFocused 'stage') is 'stage', await focused()

  await typeEx 'run'
  await settle()
  check ':run typed on the command line gives the canvas the keyboard',
    (await untilFocused 'stage') is 'stage', await focused()

  await typeEx 'eval'
  await settle()
  check ':eval typed on the command line gives the canvas the keyboard',
    (await untilFocused 'stage') is 'stage', await focused()

  # Region eval is the redefine-and-keep-typing loop: the keyboard stays put.
  await js "Editor.focus(); return true"
  await evalRegion()
  await settle()
  await wait 100                       # past the tick a canvas focus would take
  check 'region eval leaves the keyboard in the editor', (await focused()) is 'editor', await focused()

  # --- a syntax error takes you to it ------------------------------------------

  # Columns asked of CoffeeScript, not counted by hand: `unexpected *`, line 2
  # column 8.
  await setDoc "a = 1\nb = 2 +* 3\n"
  await wait 400
  await click 'runFresh'
  await settle()
  where = await cursor()
  check 'a syntax error puts the cursor on it, not the canvas',
    (await untilFocused 'editor') is 'editor' and where.line is 2 and where.column is 8,
    "focus=#{await focused()} cursor=#{JSON.stringify where}"
  check 'and marks its line', (await errorLine()) is 2, "marked=#{await errorLine()}"

  # A region is dedented before it compiles, so the compiler's column is short
  # by the indent cut: 8 in the region is 10 in the buffer.
  await setDoc "if true\n  q = 1\n  r = 2 +* 3\n"
  await wait 400
  await selectLines 2, 3
  await evalRegion()
  await settle()
  where = await cursor()
  check 'a syntax error in an indented region lands on the buffer column',
    where.line is 3 and where.column is 10, JSON.stringify where

  check 'typing the fix clears the mark', await do ->
    await js "Editor.view().dispatch({changes: {from: 0, insert: ' '}}); return true"
    (await errorLine()) is null

  # --- a runtime error offers its stack ----------------------------------------

  await setDoc """
    helper = (n) ->
      n.nope.deeper

    outer = ->
      helper 5

    outer()
  """
  await wait 400
  await js "const v = Editor.view(); v.dispatch({selection: {anchor: 0}}); return true"
  before = await cursor()
  await click 'runFresh'
  await settle()
  shown = await stack()
  check 'a runtime error shows its stack, innermost first',
    shown.shown and shown.frames.length is 3 and
    shown.frames[0].includes('helper') and shown.frames[0].includes('line 2') and
    shown.frames[2].includes('top level') and shown.frames[2].includes('line 7'),
    JSON.stringify shown
  check 'marks the innermost line without moving the cursor',
    (await errorLine()) is 2 and JSON.stringify(await cursor()) is JSON.stringify(before),
    "marked=#{await errorLine()} cursor=#{JSON.stringify await cursor()}"
  check 'and gives the prompt the keyboard, not the canvas',
    (await untilFocused 'promptLine') is 'promptLine', await focused()

  await js "document.querySelectorAll('#vars .stack-frame')[1].click(); return true"
  await untilFocused 'editor'
  where = await cursor()
  check 'choosing a frame takes the cursor to its line, in the editor',
    (await focused()) is 'editor' and where.line is 5 and where.column is 3 and (await errorLine()) is 5,
    "focus=#{await focused()} cursor=#{JSON.stringify where} marked=#{await errorLine()}"

  await setDoc quick
  await wait 400
  await click 'runFresh'
  await settle()
  shown = await stack()
  check 'the next run clears the stack and the mark',
    not shown.shown and (await errorLine()) is null, "stack=#{JSON.stringify shown} marked=#{await errorLine()}"

  # --- a frame from another sketch opens that sketch ---------------------------

  # A region of scratch defines the helper; another sketch calls it through
  # the live image. The innermost frame is scratch's, so nothing is marked in
  # the sketch that is open, and choosing that frame opens scratch.
  other = path.join paths.sketches, 'focus-other.coffee'
  await setDoc "boomer = -> undefined.x\n"
  await wait 400
  await js "Editor.view().dispatch({selection: {anchor: 0}}); return true"
  await evalRegion()
  await settle()
  await fsp.writeFile other, "boomer()\n", 'utf8'
  await js "await Editor.load('focus-other'); return true"
  await handleEx 'eval'
  await settle()
  shown = await stack()
  check 'a frame from another sketch says which',
    shown.frames.length is 2 and shown.frames[0].includes('scratch') and (await errorLine()) is null,
    "#{JSON.stringify shown} marked=#{await errorLine()}"
  await js "document.querySelector('#vars .stack-frame').click(); return true"
  await untilFocused 'editor'
  opened = await js "return Editor.name()"
  check 'choosing it opens that sketch at the line',
    opened is 'scratch' and (await cursor()).line is 1 and (await errorLine()) is 1,
    "opened=#{opened} cursor=#{JSON.stringify await cursor()}"

  await js "await Editor.load('scratch'); return true"
  await fsp.rm other, force: yes
