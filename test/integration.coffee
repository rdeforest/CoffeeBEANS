# Drives the real app through executeJavaScript. Covers the parts that can
# break without anything visibly failing: the disk bridge, region extraction,
# and whether the worker is genuinely a persistent image.
fsp  = require 'fs/promises'
path = require 'path'

wait = (ms) -> new Promise (resolve) -> setTimeout resolve, ms

module.exports = (win, ROOT) ->
  scratch = path.join ROOT, 'sketches', 'scratch.coffee'
  guarded = path.join ROOT, 'sketches', 'hello.coffee'
  before  = await fsp.readFile guarded, 'utf8'
  js      = (code) -> win.webContents.executeJavaScript "(async () => { #{code} })()", yes
  failures = 0

  check = (name, ok, detail = '') ->
    failures += 1 unless ok
    console.log "#{if ok then 'PASS' else 'FAIL'}  #{name}#{if detail then "   #{detail}" else ''}"

  setDoc = (text) -> js """
    const v = Editor.view()
    v.dispatch({ changes: { from: 0, to: v.state.doc.length, insert: #{JSON.stringify text} } })
    return v.state.doc.length
  """

  cursorOnLine = (n) -> js """
    const v = Editor.view()
    v.dispatch({ selection: { anchor: v.state.doc.line(#{n}).from } })
    return #{n}
  """

  selectLines = (a, b) -> js """
    const v = Editor.view()
    v.dispatch({ selection: { anchor: v.state.doc.line(#{a}).from, head: v.state.doc.line(#{b}).to } })
    return true
  """

  runAll = -> js "document.getElementById('runAll').click(); return true"

  consoleText = -> js "return document.getElementById('console').textContent"
  clearConsole = -> js "document.getElementById('console').innerHTML = ''; return true"

  await wait 1200

  # 1. editor is mounted and vim is driving it
  mounted = await js "return !!document.querySelector('.cm-editor')"
  fatCursor = await js "return !!document.querySelector('.cm-fat-cursor') || !!document.querySelector('.cm-vim-panel')"
  check 'editor mounts',        mounted
  check 'vim mode active',      fatCursor, '(block cursor present)'

  await js "await Editor.load('scratch'); return true"

  # 2. edits reach disk without an explicit save
  await setDoc "print 'autosave check'\n"
  await wait 600
  onDisk = await fsp.readFile scratch, 'utf8'
  check 'autosave writes to disk', onDisk is "print 'autosave check'\n", JSON.stringify onDisk

  # 3. eval-region runs only the paragraph under the cursor
  await setDoc "print 'FIRST'\n\nprint 'SECOND'\n"
  await wait 500
  await clearConsole()
  await cursorOnLine 3
  await js "Editor.runRegion(); return true"
  await wait 500
  text = await consoleText()
  check 'region runs paragraph at cursor', text.includes('SECOND') and not text.includes('FIRST'), JSON.stringify text.trim()

  # 4. a cursor inside a definition runs the whole definition
  await setDoc "sketchy = ->\n  print 'CALLED'\n\nsketchy()\n"
  await wait 500
  await clearConsole()
  await cursorOnLine 2
  await js "Editor.runRegion(); return true"
  await wait 400
  defined = await consoleText()
  await cursorOnLine 4
  await js "Editor.runRegion(); return true"
  await wait 400
  text = await consoleText()
  check 'cursor in a definition runs the definition', defined.trim() is '' and text.includes('CALLED'), JSON.stringify text.trim()

  # 5. an explicitly selected indented region is dedented before it compiles
  await setDoc "if true\n  print 'INDENTED'\n  print 'STILL'\n"
  await wait 500
  await clearConsole()
  await selectLines 2, 3
  await js "Editor.runRegion(); return true"
  await wait 500
  text = await consoleText()
  check 'selected indented region dedents', text.includes('INDENTED') and text.includes('STILL') and not text.toLowerCase().includes('error'), JSON.stringify text.trim()

  # 6. the worker is a live image: define in one region, call from another
  await setDoc "greet = (who) -> print \"hi \#{who}\"\n\ngreet 'robert'\n"
  await wait 500
  await clearConsole()
  await cursorOnLine 1
  await js "Editor.runRegion(); return true"
  await wait 400
  await cursorOnLine 3
  await js "Editor.runRegion(); return true"
  await wait 500
  text = await consoleText()
  check 'worker keeps state between runs', text.includes('hi robert'), JSON.stringify text.trim()

  # 7. a sketch cannot sever the worker's inbox by naming a variable onmessage
  await setDoc "onmessage = 'clobbered'\nprint 'BEFORE'\n"
  await wait 500
  await clearConsole()
  await js "Editor.runRegion(); return true"
  await wait 400
  await setDoc "print 'AFTER'\n"
  await wait 500
  await js "Editor.runRegion(); return true"
  await wait 500
  text = await consoleText()
  check 'sketch cannot clobber the worker inbox', text.includes('AFTER'), JSON.stringify text.trim()

  # 8. a write from outside (vim) is picked up
  await fsp.writeFile scratch, "print 'FROM VIM'\n", 'utf8'
  await wait 700
  doc = await js "return Editor.all()"
  check 'external write reloads editor', doc is "print 'FROM VIM'\n", JSON.stringify doc

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

  # 10. a swap in single-buffer mode must not flip away the drawing
  await setDoc "screen 320, 200\ncls()\npoint 10, 10, COLORS.white\nwait 1\nprint 'pget=' + pget(10, 10)\n"
  await wait 500
  await clearConsole()
  await runAll()
  await wait 700
  text = await consoleText()
  check 'wait keeps the drawing in single-buffer mode',
    text.includes('pget=') and not text.includes('pget=0'), JSON.stringify text.trim()

  # 11. double buffering must still flip: after a swap you are drawing
  # into the buffer that was on screen, not the one you just filled.
  await setDoc "screen 320, 200\ncls()\nbuffer.on\ncls()\npoint 10, 10, COLORS.white\nbefore = pget(10, 10)\nbuffer.swap\nprint 'flipped=' + (pget(10, 10) isnt before)\n"
  await wait 500
  await clearConsole()
  await runAll()
  await wait 700
  text = await consoleText()
  check 'double buffering flips on swap', text.includes('flipped=true'), JSON.stringify text.trim()

  # 12. pget must return the color point was given, not the stored byte order
  await setDoc "screen 320, 200\ncls()\npoint 5, 5, COLORS.red\nprint 'roundtrip=' + (pget(5, 5) is COLORS.red)\n"
  await wait 500
  await clearConsole()
  await runAll()
  await wait 700
  text = await consoleText()
  check 'pget round-trips a color', text.includes('roundtrip=true'), JSON.stringify text.trim()

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

  # 14. panels resize, clamp at both ends, and remember the last size
  await js "Panels.set('editor', 400); return true"
  await wait 150
  width = await js "return Math.round(Panels.size('editor'))"
  check 'editor panel resizes', width is 400, "#{width}px"

  await js "Panels.set('editor', 10); return true"
  await wait 150
  narrow = await js "return Math.round(Panels.size('editor'))"
  check 'editor panel clamps to a minimum', narrow >= 200 and narrow < 400, "#{narrow}px"

  await js "Panels.set('editor', 99999); return true"
  await wait 150
  wide  = await js "return Math.round(Panels.size('editor'))"
  total = await js "return window.innerWidth"
  check 'editor panel clamps to available room', wide < total - 100, "#{wide}px of #{total}px"

  await js "Panels.set('console', 200); return true"
  await wait 150
  tall = await js "return Math.round(Panels.size('console'))"
  remembered = await js "return Number(localStorage.getItem('panel.console'))"
  check 'console panel resizes and is remembered', tall is 200 and remembered is 200, "#{tall}px stored=#{remembered}"

  # 15. keyboard state reaches the sketch, and clears on keyup
  key = (kind, code) -> js """
    const stage = document.getElementById('stage')
    stage.focus()
    stage.dispatchEvent(new KeyboardEvent('#{kind}', { code: '#{code}', bubbles: true }))
    return true
  """

  await setDoc "print 'down=' + keys.down('a')\n"
  await wait 500
  await key 'keydown', 'KeyA'
  await clearConsole()
  await runAll()
  await wait 600
  text = await consoleText()
  check 'keys.down sees a held key', text.includes('down=true'), JSON.stringify text.trim()

  await key 'keyup', 'KeyA'
  await clearConsole()
  await runAll()
  await wait 600
  text = await consoleText()
  check 'keys.down clears on keyup', text.includes('down=false'), JSON.stringify text.trim()

  # 16. a tap between frames is still caught, and claimed only once
  await setDoc "keys.poll\nprint 'hit=' + keys.hit('b')\n"
  await wait 500
  await key 'keydown', 'KeyB'
  await key 'keyup',   'KeyB'
  await clearConsole()
  await runAll()
  await wait 600
  text = await consoleText()
  check 'keys.hit catches a tap between frames', text.includes('hit=true'), JSON.stringify text.trim()

  await clearConsole()
  await runAll()
  await wait 600
  text = await consoleText()
  check 'keys.hit is claimed once', text.includes('hit=false'), JSON.stringify text.trim()

  # 17. losing focus must not leave a key stuck down
  await setDoc "print 'stuck=' + keys.down('c')\n"
  await wait 500
  await key 'keydown', 'KeyC'
  # Dispatched rather than calling .blur(), which does nothing when the
  # Electron window is not the OS-focused window. This exercises the
  # handler; that a real blur fires it is browser behaviour.
  await js "document.getElementById('stage').dispatchEvent(new FocusEvent('blur')); return true"
  await clearConsole()
  await runAll()
  await wait 600
  text = await consoleText()
  check 'blur releases held keys', text.includes('stuck=false'), JSON.stringify text.trim()

  # 18. mouse position arrives in screen pixels, not window pixels
  await setDoc "print 'at=' + mouse.x + ',' + mouse.y\n"
  await wait 500
  await js """
    const c = document.getElementById('screen')
    const r = c.getBoundingClientRect()
    document.getElementById('stage').dispatchEvent(new PointerEvent('pointermove', {
      clientX: r.left + r.width * 0.25, clientY: r.top + r.height * 0.5, bubbles: true }))
    return true
  """
  await clearConsole()
  await runAll()
  await wait 600
  text = await consoleText()
  check 'mouse maps into screen pixels', text.includes('at=80,100'), JSON.stringify text.trim()

  # the suite owns scratch.coffee and nothing else
  after = await fsp.readFile guarded, 'utf8'
  check 'suite does not touch real sketches', after is before, "hello.coffee #{after.length} bytes"

  # leave the user's layout the way we found it
  await js "localStorage.removeItem('panel.editor'); localStorage.removeItem('panel.console'); return true"

  console.log "\n#{if failures then "#{failures} FAILED" else 'all passed'}"
  failures
