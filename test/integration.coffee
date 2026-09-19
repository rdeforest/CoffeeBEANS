# Drives the real app through executeJavaScript. Covers the parts that can
# break without anything visibly failing: the disk bridge, region extraction,
# and whether the worker is genuinely a persistent image.
fsp  = require 'fs/promises'
path = require 'path'
{Menu} = require 'electron'
seeding = require '../src/main/data'

wait = (ms) -> new Promise (resolve) -> setTimeout resolve, ms

module.exports = (win, paths) ->
  scratch = path.join paths.sketches, 'scratch.coffee'
  guarded = path.join paths.sketches, 'hello.coffee'
  await fsp.writeFile scratch, "print 'scratch'\n", 'utf8'
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

  # 13a. the status line counts source lines, and a :target flags the overrun.
  # Goes through the real ex parser, the same path :help uses.
  handleEx  = (cmd) -> js "CM.Vim.handleEx(CM.getCM(Editor.view()), #{JSON.stringify cmd}); return true"
  linesText = -> js "return document.getElementById('lines').textContent"
  overLine  = -> js "return (document.querySelector('.cm-over-limit') || {}).textContent ?? null"
  overRed   = -> js "return document.getElementById('lines').classList.contains('over')"

  await setDoc "# a comment\nprint 'one'\n\nprint 'two'\n"
  await wait 300
  check 'status line counts only source lines', (await linesText()) is '2 lines', JSON.stringify await linesText()

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
  inPicker = await js "return [...document.getElementById('sketch').options].some((o) => o.value === 'ecreate')"
  check ':e newname creates, opens, and lists the sketch',
    (await js "return Editor.name()") is 'ecreate' and made and inPicker,
    "name=#{await js "return Editor.name()"} disk=#{made} picker=#{inPicker}"

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

  # 19. the data directory was seeded from examples/
  seeded   = (await fsp.readdir paths.sketches).filter (name) -> name.endsWith '.coffee'
  examples = (await fsp.readdir path.join paths.root, 'examples').filter (name) -> name.endsWith '.coffee'
  missing  = (name for name in examples when name not in seeded)
  check 'data directory seeded from examples', missing.length is 0, "have #{seeded.join ', '}"

  # 20. the File menu can get the user to their own files
  menu = Menu.getApplicationMenu()
  file = menu?.items.find (item) -> item.label is 'File'
  open = file?.submenu?.items.find (item) -> item.label is 'Open Data Folder'
  check 'File menu opens the data folder', open? and open.enabled, "#{file?.submenu?.items.length} items under File"

  # 21. the shape primitives put pixels where they claim to
  shapes = """
screen 320, 200
cls()
line 10, 10, 100, 10, COLORS.white
rect 150, 20, 200, 60, COLORS.red
rectFill 220, 20, 260, 60, COLORS.lime
circle 60, 140, 30, COLORS.cyan
circleFill 160, 140, 30, COLORS.yellow
print 'lineStart='   + (pget(10, 10)   is COLORS.white)
print 'lineEnd='     + (pget(100, 10)  is COLORS.white)
print 'rectEdge='    + (pget(150, 20)  is COLORS.red)
print 'rectHollow='  + (pget(175, 40)  is COLORS.red)
print 'fillCentre='  + (pget(240, 40)  is COLORS.lime)
print 'circleRim='   + (pget(60, 110)  is COLORS.cyan)
print 'circleHollow='+ (pget(60, 140)  is COLORS.cyan)
print 'discCentre='  + (pget(160, 140) is COLORS.yellow)
"""
  await setDoc shapes
  await wait 500
  await clearConsole()
  await runAll()
  await wait 800
  text   = await consoleText()
  wanted = ['lineStart=true', 'lineEnd=true', 'rectEdge=true', 'rectHollow=false',
            'fillCentre=true', 'circleRim=true', 'circleHollow=false', 'discCentre=true']
  absent = (want for want in wanted when not text.includes want)
  check 'shapes land where they claim', absent.length is 0, "missing #{absent.join ', '}"

  # 22. clipping, not iterating: a line across a billion pixels is cheap
  await setDoc "screen 320, 200\ncls()\nt = performance.now()\nline -1e9, -1e9, 1e9, 1e9, COLORS.white\nline 400, 400, 900, 900, COLORS.red\nprint 'ms=' + round(performance.now() - t)\nprint 'diagonal=' + (pget(160, 160) is COLORS.white)\nprint 'offscreen=' + (pget(319, 199) is COLORS.red)\n"
  await wait 500
  await clearConsole()
  await runAll()
  await wait 800
  text = await consoleText()
  elapsed = Number /ms=(\d+)/.exec(text)?[1] ? 9999
  check 'line clips instead of iterating', elapsed < 50 and text.includes('diagonal=true') and text.includes('offscreen=false'), JSON.stringify text.trim()

  # 23. a sketch that is not there must not take the boot sequence with it
  missingName = 'definitely-not-a-sketch'
  await js "return (async () => { try { await beans.read('#{missingName}') } catch (e) { return 'threw' } })()"
  await clearConsole()
  await js "await Editor.load('scratch'); return true"
  alive = await js """
    document.getElementById('runAll').click()
    return true
  """
  await wait 600
  check 'a failed read does not stop the app', alive is true and (await js "return typeof Panels.size('editor')") is 'number'

  # 24. seeding offers each example once, and never at the cost of your edits
  sandbox  = path.join paths.data, 'seedcheck'
  fakeEx   = path.join sandbox, 'examples'
  fakeData = path.join sandbox, 'data'
  await fsp.mkdir fakeEx, recursive: yes
  await fsp.writeFile path.join(fakeEx, 'one.coffee'), 'print 1\n', 'utf8'

  first = await seeding.prepare fakeData, fakeEx
  check 'seeding copies a new example', first.added.join(',') is 'one.coffee', first.added.join ','

  mine = path.join fakeData, 'sketches', 'one.coffee'
  await fsp.writeFile mine, 'print "mine"\n', 'utf8'
  await fsp.writeFile path.join(fakeEx, 'two.coffee'), 'print 2\n', 'utf8'
  second = await seeding.prepare fakeData, fakeEx
  kept   = await fsp.readFile mine, 'utf8'
  check 'a new example arrives without clobbering an edited one',
    second.added.join(',') is 'two.coffee' and kept is 'print "mine"\n',
    "added=#{second.added.join ','} kept=#{JSON.stringify kept}"

  await fsp.rm path.join(fakeData, 'sketches', 'two.coffee')
  third = await seeding.prepare fakeData, fakeEx
  gone  = not (await fsp.readdir path.join fakeData, 'sketches').includes 'two.coffee'
  check 'a deleted example stays deleted', third.added.length is 0 and gone,
    "added=#{third.added.join ','} gone=#{gone}"

  # A data directory predating the manifest must not have its contents
  # treated as never-offered, or an upgrade would overwrite every edit.
  legacy = path.join sandbox, 'legacy'
  await fsp.mkdir path.join(legacy, 'sketches'), recursive: yes
  await fsp.writeFile path.join(legacy, 'sketches', 'one.coffee'), 'print "old"\n', 'utf8'
  fourth = await seeding.prepare legacy, fakeEx
  survived = await fsp.readFile path.join(legacy, 'sketches', 'one.coffee'), 'utf8'
  check 'a pre-manifest data folder keeps its edits',
    survived is 'print "old"\n' and fourth.added.join(',') is 'two.coffee',
    "added=#{fourth.added.join ','} kept=#{JSON.stringify survived}"

  # 25. surfaces: capture, redraw, retarget, blit modes, collision
  surfaces = """
screen 320, 200
cls()

# get / put round trip
rectFill 10, 10, 19, 19, COLORS.red
grabbed = get 10, 10, 19, 19
print 'grabSize=' + grabbed.width + 'x' + grabbed.height
cls()
print 'cleared=' + (pget(12, 12) isnt COLORS.red)
put grabbed, 100, 100
print 'restored=' + (pget(102, 102) is COLORS.red)

# drawTo redirects every primitive, and the block form restores
canvas = surface 8, 8
drawTo canvas, ->
  cls 0x00000000
  rectFill 2, 2, 5, 5, COLORS.lime
print 'offscreen=' + (drawTo(canvas, -> pget 3, 3) is COLORS.lime)
print 'screenUntouched=' + (pget(3, 3) isnt COLORS.lime)
drawTo canvas, -> null
point 3, 3, COLORS.yellow
print 'restoredTarget=' + (pget(3, 3) is COLORS.yellow)

# transparency: over skips clear pixels, copy does not
cls COLORS.blue
put canvas, 200, 100
print 'transparentKept=' + (pget(200, 100) is COLORS.blue)
print 'opaqueDrawn=' + (pget(203, 103) is COLORS.lime)

# xor twice is identity
before = pget 210, 100
put canvas, 208, 98, 'xor'
put canvas, 208, 98, 'xor'
print 'xorRoundTrip=' + (pget(210, 100) is before)

# pixel-accurate collision: boxes overlap, pixels do not
left  = surface 8, 8
right = surface 8, 8
drawTo left,  -> cls 0x00000000; rectFill 0, 0, 2, 2, COLORS.white
drawTo right, -> cls 0x00000000; rectFill 5, 5, 7, 7, COLORS.white
print 'boxOnly=' + overlaps(left, 0, 0, right, 0, 0)
print 'pixels=' + overlaps(left, 0, 0, right, -5, -5)
"""
  await setDoc surfaces
  await wait 500
  await clearConsole()
  await runAll()
  await wait 900
  text   = await consoleText()
  wanted = ['grabSize=10x10', 'cleared=true', 'restored=true',
            'offscreen=true', 'screenUntouched=true', 'restoredTarget=true',
            'transparentKept=true', 'opaqueDrawn=true', 'xorRoundTrip=true',
            'boxOnly=false', 'pixels=true']
  absent = (want for want in wanted when not text.includes want)
  check 'surfaces capture, retarget, blit and collide', absent.length is 0,
    if absent.length then "missing #{absent.join ', '}" else 'all ten'

  # 26. put clips at every edge instead of wrapping or throwing
  await setDoc "screen 320, 200\ncls()\ns = surface 8, 8\ndrawTo s, -> cls COLORS.white\nput s, -4, -4\nput s, 316, 196\nput s, -100, -100\nput s, 1000, 1000\nprint 'topLeft=' + (pget(0, 0) is COLORS.white)\nprint 'bottomRight=' + (pget(319, 199) is COLORS.white)\nprint 'survived=true'\n"
  await wait 500
  await clearConsole()
  await runAll()
  await wait 800
  text = await consoleText()
  check 'put clips at the edges', text.includes('topLeft=true') and text.includes('bottomRight=true') and text.includes('survived=true'), JSON.stringify text.trim()

  # 27. stamp: identity matches put, and scale and rotation land where geometry says
  stamping = """
screen 320, 200
cls()

mark = surface 4, 4
drawTo mark, ->
  cls 0x00000000
  rectFill 0, 0, 3, 3, COLORS.red
  point 0, 0, COLORS.lime          # a corner we can follow through a rotation

# identity stamp must equal put
cls()
put   mark, 20, 20
a = pget 20, 20
cls()
stamp mark, 20, 20
print 'identity=' + (pget(20, 20) is a)
print 'identityCorner=' + (pget(20, 20) is COLORS.lime)

# doubling in size: the lime corner covers a 2x2 block
cls()
stamp mark, 50, 50, scale: 2
print 'scaledCorner=' + (pget(51, 51) is COLORS.lime)
print 'scaledExtent=' + (pget(57, 57) is COLORS.red)
print 'scaledPast=' + (pget(59, 59) isnt COLORS.red)

# a quarter turn about the centre puts the lime corner where red was
cls()
stamp mark, 100, 100, angle: pi / 2, anchorX: 2, anchorY: 2
print 'rotatedSomething=' + (pget(100, 100) is COLORS.red or pget(101, 101) is COLORS.red)
print 'rotatedCornerMoved=' + (pget(100, 98) isnt COLORS.lime)

# a degenerate scale must not divide by zero or hang
stamp mark, 10, 10, scale: 0
print 'zeroScaleSurvived=true'
"""
  await setDoc stamping
  await wait 500
  await clearConsole()
  await runAll()
  await wait 900
  text   = await consoleText()
  wanted = ['identity=true', 'identityCorner=true', 'scaledCorner=true',
            'scaledExtent=true', 'scaledPast=true', 'rotatedSomething=true',
            'zeroScaleSurvived=true']
  absent = (want for want in wanted when not text.includes want)
  check 'stamp scales and rotates', absent.length is 0,
    if absent.length then "missing #{absent.join ', '}" else 'all seven'

  # 28. the recursive-feedback loop actually grows branches
  tree = """
screen 320, 200
canvas = surface 320, 200
drawTo canvas, ->
  cls 0x00000000
  line 160, 199, 160, 148, COLORS.coffee
  for generation in [1..3]
    whole = get 0, 0, 319, 199
    for side in [-1, 1]
      stamp whole, 160, 148, scale: 0.7, angle: 0.5 * side, anchorX: 160, anchorY: 199
cls()
put canvas, 0, 0

print 'trunk=' + (pget(160, 190) is COLORS.coffee)

above = 0
offAxis = 0
for y in [0...148] by 1
  for x in [0...320] by 1
    continue unless pget(x, y) is COLORS.coffee
    above += 1
    offAxis += 1 if abs(x - 160) > 6
print 'above=' + above
print 'offAxis=' + offAxis
print 'branched=' + (above > 100 and offAxis > 50)
"""
  await setDoc tree
  await wait 500
  await clearConsole()
  await runAll()
  await wait 1500
  text = await consoleText()
  check 'recursive feedback grows branches',
    text.includes('trunk=true') and text.includes('branched=true'),
    JSON.stringify text.trim()

  # 29. text: glyph shape, cursor, scaling, wrapping, and drawTo
  texting = """
screen 320, 200
cls()
color COLORS.white

# 'A' is 0C1E33333F333300: the top row lights bits 2 and 3 only
textAt 0, 0, 'A'
print 'glyphOn=' + (pget(2, 0) is COLORS.white and pget(3, 0) is COLORS.white)
print 'glyphOff=' + (pget(0, 0) isnt COLORS.white)
print 'width=' + textWidth('hello')

# locate puts the cursor on cell boundaries
cls()
locate 2, 3
text 'A'
print 'located=' + (pget(2 * 8 + 2, 3 * 8) is COLORS.white)

# scaling doubles every pixel
cls()
textScale 2
textAt 0, 0, 'A'
print 'scaled=' + (pget(4, 0) is COLORS.white and pget(5, 1) is COLORS.white)
print 'scaledWidth=' + textWidth('AB')
textScale 1

# wrapping at the right edge
cls()
locate 39, 0
text 'AB'
print 'wrapped=' + (pget(2, 8) is COLORS.white)

# text obeys drawTo like everything else
sheet = surface 32, 16
drawTo sheet, ->
  cls 0x00000000
  textAt 0, 0, 'A'
print 'onSurface=' + (drawTo(sheet, -> pget 2, 0) is COLORS.white)
print 'screenClean=' + (pget(2, 0) isnt COLORS.white)

# an unknown character still draws something
cls()
textAt 0, 0, 'a-with-accent-here'.charAt(0)
textAt 40, 0, String.fromCharCode(233)
print 'missingBox=' + (pget(40, 0) is COLORS.white and pget(47, 0) is COLORS.white)

print 'timing=' + (elapsed >= 0 and frames >= 0)
"""
  await setDoc texting
  await wait 500
  await clearConsole()
  await runAll()
  await wait 900
  text2  = await consoleText()
  wanted = ['glyphOn=true', 'glyphOff=true', 'width=40', 'located=true',
            'scaled=true', 'scaledWidth=32', 'wrapped=true',
            'onSurface=true', 'screenClean=true', 'missingBox=true', 'timing=true']
  absent = (want for want in wanted when not text2.includes want)
  check 'text renders, positions, scales and retargets', absent.length is 0,
    if absent.length then "missing #{absent.join ', '}" else 'all eleven'

  # 30. load: real bytes, real decode, correct channel order, cached to disk
  assets = path.join paths.data, 'assets'
  await fsp.mkdir assets, recursive: yes
  await fsp.copyFile path.join(paths.root, 'test', 'fixtures', 'swatch.png'),
                     path.join assets, 'swatch.png'

  loading = """
screen 320, 200
cls()
swatch = load 'assets/swatch.png'
print 'size=' + swatch.width + 'x' + swatch.height
print 'red='   + (drawTo(swatch, -> pget 0, 0) is COLORS.red)
print 'green=' + (drawTo(swatch, -> pget 1, 0) is COLORS.lime)
print 'blue='  + (drawTo(swatch, -> pget 0, 1) is COLORS.blue)
print 'clear=' + (drawTo(swatch, -> pget 1, 1) is 0)

# transparency survives the trip: over must skip the clear pixel
cls COLORS.yellow
put swatch, 10, 10
print 'keptUnder=' + (pget(11, 11) is COLORS.yellow)
print 'drewOver='  + (pget(10, 10) is COLORS.red)

try
  load 'assets/definitely-missing.png'
  print 'missing=no error'
catch error
  print 'missing=' + (error.message.length > 0)
"""
  await setDoc loading
  await wait 500
  await clearConsole()
  await runAll()
  await wait 2000
  text3  = await consoleText()
  wanted = ['size=2x2', 'red=true', 'green=true', 'blue=true', 'clear=true',
            'keptUnder=true', 'drewOver=true', 'missing=true']
  absent = (want for want in wanted when not text3.includes want)
  check 'load decodes an image with the right channel order', absent.length is 0,
    if absent.length then "missing #{absent.join ', '} -- got #{JSON.stringify text3.trim()}" else 'all eight'

  # 31. a remote image is cached, so the second run needs no network
  cachedFiles = await fsp.readdir assets
  check 'assets folder is where downloads land', cachedFiles.includes('swatch.png'),
    cachedFiles.join ', '

  # 32. nothing in the worker's own bootstrap may shadow a runtime global
  await setDoc "print(name + '=' + typeof globalThis[name]) for name in ['load', 'get', 'put', 'text', 'surface', 'stamp', 'line']\n"
  await wait 500
  await clearConsole()
  await runAll()
  await wait 700
  text4 = await consoleText()
  shadowed = (name for name in ['load', 'get', 'put', 'text', 'surface', 'stamp', 'line'] \
              when not text4.includes "#{name}=function")
  check 'runtime globals are not shadowed by the bootstrap', shadowed.length is 0,
    if shadowed.length then "shadowed: #{shadowed.join ', '}" else 'all reachable'

  # 33. a stop must not poison the live worker: the next region that swaps runs
  click = (id) -> js "document.getElementById('#{id}').click(); return true"
  status = -> js "return document.getElementById('status').textContent"
  await setDoc "screen 320, 200\nbuffer.on\nloop\n  buffer.swap\n"
  await wait 500
  await runAll()
  await wait 300
  await click 'stop'
  await wait 300
  await clearConsole()
  await setDoc "buffer.swap\nprint 'ALIVE'\n"
  await wait 500
  await runAll()
  await wait 500
  text = await consoleText()
  check 'stop does not poison the next run', text.includes('ALIVE') and not text.includes('stopped'), JSON.stringify text.trim()

  # 34. a run while a sketch is running is refused, not queued: the buttons
  # grey out, and the keyboard path says so
  await setDoc "screen 320, 200\nbuffer.on\nloop\n  buffer.swap\n"
  await wait 500
  await clearConsole()
  await runAll()
  await wait 300
  greyed = await js "return document.getElementById('runAll').disabled && document.getElementById('run').disabled"
  await js "Editor.runRegion(); return true"
  await wait 300
  text = await consoleText()
  await click 'stop'
  await wait 300
  idle    = await status()
  enabled = await js "return !document.getElementById('runAll').disabled"
  check 'run while running is refused', greyed and text.includes('already running') and idle is 'ready' and enabled, "#{JSON.stringify text.trim()} status=#{idle} greyed=#{greyed} enabled=#{enabled}"

  # 35. a restart right after a stop must not be killed by the stop's deadline
  await setDoc "loop\n  0\n"
  await wait 500
  await clearConsole()
  await runAll()
  await wait 200
  await click 'stop'
  await wait 50
  await setDoc "screen 320, 200\nbuffer.on\nprint 'RESTARTED'\nloop\n  buffer.swap\n"
  await click 'restart'
  await wait 800
  text = await consoleText()
  live = await status()
  check 'restart during a stop deadline survives', text.includes('RESTARTED') and not text.includes('no yield point') and live is 'running', "#{JSON.stringify text.trim()} status=#{live}"
  await click 'stop'
  await wait 300

  # 36. a flood of prints is capped, and the last line still arrives
  await setDoc "print i for i in [1..200000]\nprint 'LAST'\n"
  await wait 500
  await clearConsole()
  await runAll()
  await wait 2500
  count = await js "return document.getElementById('console').childElementCount"
  text  = await consoleText()
  check 'console caps a flood and keeps the tail', count <= 2000 and text.includes('LAST'), "#{count} lines"

  # 37. fractional corners land on whole rows instead of mid-row
  await setDoc "screen 320, 200\ncls()\nrectFill 0, 2.5, 10, 5.5, COLORS.white\nprint 'inside=' + (pget(5, 4) is COLORS.white)\nprint 'rowStart=' + (pget(0, 3) is COLORS.white)\nprint 'wrapped=' + (pget(300, 2) is COLORS.white)\n"
  await wait 500
  await clearConsole()
  await runAll()
  await wait 700
  text = await consoleText()
  check 'rectFill rounds fractional corners', text.includes('inside=true') and text.includes('rowStart=true') and text.includes('wrapped=false'), JSON.stringify text.trim()

  # 38. a stopped double-buffered sketch must not leave the next sketch
  # drawing into the buffer that is not on screen, or over its leftovers
  await setDoc "screen 320, 200\nbuffer.on\nloop\n  cls()\n  point 10, 10, COLORS.red\n  buffer.swap\n"
  await wait 500
  await runAll()
  await wait 400
  await click 'stop'
  await wait 300
  await clearConsole()
  await setDoc "screen 320, 200\ncls()\npoint 20, 20, COLORS.white\nprint 'onScreen=' + display.onScreen\nprint 'oldGone=' + (pget(10, 10) isnt COLORS.red)\n"
  await wait 500
  await runAll()
  await wait 600
  text = await consoleText()
  check 'next sketch after a stopped double-buffered one draws on screen', text.includes('onScreen=true') and text.includes('oldGone=true'), JSON.stringify text.trim()

  # 39. a runtime error reports the CoffeeScript line it happened on
  await setDoc "a = 1\n\nboom = ->\n  throw new Error 'kaboom'\n\nboom()\n"
  await wait 500
  await clearConsole()
  await runAll()
  await wait 700
  text = await consoleText()
  check 'a runtime error names its CoffeeScript line',
    text.includes('line 4') and text.includes('kaboom'), JSON.stringify text.trim()

  # and a compile error still reports its own
  await setDoc "x = 1\n  y = 2\n"
  await wait 500
  await clearConsole()
  await runAll()
  await wait 700
  text = await consoleText()
  check 'a compile error names its line', /line \d/.test(text), JSON.stringify text.trim()

  # 40. screen refuses dimensions the renderer cannot make an image from
  await setDoc "try\n  screen 0, 200\n  print 'accepted'\ncatch error\n  print 'refused=' + error.message\nscreen 320, 200\ncls()\nprint 'stillAlive=true'\n"
  await wait 500
  await clearConsole()
  await runAll()
  await wait 700
  text = await consoleText()
  check 'screen refuses bad dimensions without wedging the renderer',
    text.includes('refused=') and text.includes('width must be') and text.includes('stillAlive=true'),
    JSON.stringify text.trim()

  # 41. buffer.fps actually paces swaps instead of only storing a number
  await setDoc "screen 320, 200\nbuffer.on\nbuffer.fps 10\nbuffer.swap\nstart = elapsed\nn = 0\nwhile elapsed - start < 1\n  buffer.swap\n  n += 1\nprint 'swaps=' + n\nbuffer.fps 0\n"
  await wait 500
  await clearConsole()
  await runAll()
  await wait 2500
  text  = await consoleText()
  swaps = Number /swaps=(\d+)/.exec(text)?[1] ? -1
  check 'buffer.fps paces swaps', 4 <= swaps <= 25, "#{swaps} swaps in a second at fps 10"

  # 42. display.onScreen tells a sketch where its drawing is landing
  await setDoc "screen 320, 200\nprint 'single=' + display.onScreen\nbuffer.on\nprint 'doubled=' + display.onScreen\nbuffer.swap\nprint 'afterSwap=' + display.onScreen\n"
  await wait 500
  await clearConsole()
  await runAll()
  await wait 800
  text = await consoleText()
  check 'display.onScreen distinguishes the buffers',
    text.includes('single=true') and text.includes('doubled=false') and text.includes('afterSwap=false'),
    JSON.stringify text.trim()

  # 43. fromHSV, in degrees, beside fromRGB
  await setDoc "print 'red='   + (COLORS.fromHSV(0)   is COLORS.red)\nprint 'lime='  + (COLORS.fromHSV(120) is COLORS.lime)\nprint 'blue='  + (COLORS.fromHSV(240) is COLORS.blue)\nprint 'white=' + (COLORS.fromHSV(0, 0, 1) is COLORS.white)\nprint 'black=' + (COLORS.fromHSV(0, 0, 0) is COLORS.black)\nprint 'wraps=' + (COLORS.fromHSV(370) is COLORS.fromHSV(10))\nprint 'negative=' + (COLORS.fromHSV(-120) is COLORS.fromHSV(240))\n"
  await wait 500
  await clearConsole()
  await runAll()
  await wait 700
  text   = await consoleText()
  wanted = ['red=true', 'lime=true', 'blue=true', 'white=true', 'black=true', 'wraps=true', 'negative=true']
  absent = (want for want in wanted when not text.includes want)
  check 'COLORS.fromHSV converts and wraps', absent.length is 0,
    if absent.length then "missing #{absent.join ', '}" else 'all seven'

  # 44. seeding never writes over a sketch already on disk
  guardDir = path.join sandbox, 'guarded'
  await fsp.mkdir path.join(guardDir, 'sketches'), recursive: yes
  await fsp.writeFile path.join(guardDir, 'sketches', 'two.coffee'), "print 'not yours'\n", 'utf8'
  await fsp.writeFile path.join(guardDir, '.seeded'), "one.coffee\n", 'utf8'
  guarded2 = await seeding.prepare guardDir, fakeEx
  survivor = await fsp.readFile path.join(guardDir, 'sketches', 'two.coffee'), 'utf8'
  recorded = await fsp.readFile path.join(guardDir, '.seeded'), 'utf8'
  check 'seeding does not overwrite a sketch already on disk',
    survivor is "print 'not yours'\n" and recorded.includes('two.coffee') and guarded2.added.length is 0,
    "added=#{guarded2.added.join ','} kept=#{guarded2.kept.join ','}"

  # 45. saving leaves no staging files behind in the sketches folder
  await js "await Editor.load('scratch'); return true"
  await setDoc "print 'atomic'\n"
  await wait 700
  strays = (await fsp.readdir paths.sketches).filter (name) -> not name.endsWith '.coffee'
  check 'atomic save leaves nothing behind', strays.length is 0, strays.join ', '

  # 46. a print is visible while the sketch is still busy. postMessage could
  # never do this: a worker in a tight loop delivers nothing until it yields.
  await setDoc "print 'EARLY'\nstart = elapsed\nspun = 0\nwhile elapsed - start < 1.5\n  spun += 1\nprint 'LATE'\n"
  await wait 500
  await clearConsole()
  await runAll()
  await wait 700
  midRun  = await consoleText()
  running = await status()
  await wait 1600
  after = await consoleText()
  check 'a print arrives while the sketch is still running',
    midRun.includes('EARLY') and not midRun.includes('LATE') and running is 'running' and after.includes('LATE'),
    "mid=#{JSON.stringify midRun.trim()} status=#{running}"

  # 47. a sketch's own names never reach globalThis
  await setDoc "mySketchThing = 42\nprint 'local=' + mySketchThing\nprint 'leaked=' + globalThis.mySketchThing?\n"
  await wait 500
  await clearConsole()
  await runAll()
  await wait 700
  text = await consoleText()
  check 'sketch names stay out of globalThis',
    text.includes('local=42') and text.includes('leaked=false'), JSON.stringify text.trim()

  # 48. shadowing a command still works, but cannot damage the command
  await setDoc "line = 5\nprint 'shadowed=' + typeof line\nprint 'apiIntact=' + typeof globalThis.line\n"
  await wait 500
  await clearConsole()
  await runAll()
  await wait 700
  text = await consoleText()
  shadowed = text.includes('shadowed=number') and text.includes('apiIntact=function')

  # the shadow lives in the image, so a later region still sees it
  await setDoc "print 'persists=' + typeof line\n"
  await wait 500
  await runAll()
  await wait 600
  text = await consoleText()
  persists = text.includes('persists=number')

  # and a restart drops the image, leaving the API pristine
  await setDoc "print 'afterRestart=' + typeof line\n"
  await wait 500
  await clearConsole()
  await click 'restart'
  await wait 1200
  text = await consoleText()
  check 'a shadowed command is restored by a restart',
    shadowed and persists and text.includes('afterRestart=function'),
    "shadowed=#{shadowed} persists=#{persists} after=#{JSON.stringify text.trim()}"

  # 49. a sketch that throws keeps whatever it managed to define
  await setDoc "keeper = 7\nthrow new Error 'halt'\n"
  await wait 500
  await clearConsole()
  await runAll()
  await wait 700
  await setDoc "print 'kept=' + keeper\n"
  await wait 500
  await runAll()
  await wait 600
  text = await consoleText()
  check 'definitions survive a sketch that throws', text.includes('kept=7'), JSON.stringify text.trim()

  # 50. fill: the default rule, boundaries, custom predicates, and the traps
  filling = """
screen 320, 200

# default rule: spread over what matches the seed, stop at anything else
cls COLORS.black
rect 10, 10, 40, 40, COLORS.white
fill 25, 25, COLORS.red
print 'inside='  + (pget(25, 25) is COLORS.red)
print 'edgeKept=' + (pget(10, 10) is COLORS.white)
print 'outside=' + (pget(5, 5) is COLORS.black)

# it does not leak through a gap in the outline
cls COLORS.black
rect 10, 10, 40, 40, COLORS.white
point 25, 10, COLORS.black          # punch a hole in the top edge
fill 25, 25, COLORS.red
print 'leaked=' + (pget(5, 5) is COLORS.red)

# border: cross anything that is not the border colour
cls COLORS.black
rect 10, 10, 40, 40, COLORS.white
point 20, 20, COLORS.blue           # an island the default rule would refuse
point 30, 30, COLORS.lime
fill 25, 25, COLORS.red, border COLORS.white
print 'crossedBlue=' + (pget(20, 20) is COLORS.red)
print 'crossedLime=' + (pget(30, 30) is COLORS.red)
print 'stoppedAtBorder=' + (pget(10, 10) is COLORS.white)

# matching: only pixels of one colour, wherever the walk reaches
cls COLORS.black
rectFill 0, 0, 60, 60, COLORS.blue
fill 30, 30, COLORS.red, matching COLORS.blue
print 'matched=' + (pget(30, 30) is COLORS.red)

# where: a predicate over the probe
cls COLORS.black
rectFill 0, 0, 60, 60, COLORS.fromHSV 200, 1, 0.3
rect 0, 0, 60, 60, COLORS.white
fill 30, 30, COLORS.yellow, where (p) -> p.value < 0.5
print 'byValue=' + (pget(30, 30) is COLORS.yellow)
print 'valueStopped=' + (pget(0, 0) is COLORS.white)

# the probe carries position, channels and neighbours
cls COLORS.black
probed = null
fill 5, 5, COLORS.red, where (p) ->
  probed ?= {x: p.x, y: p.y, red: p.red, blue: p.blue, seed: p.seed, up: p.up}
  p.color is p.seed
print 'probeXY='    + (probed.x is 5 and probed.y is 5)
print 'probeChan='  + (probed.red is 0 and probed.blue is 0)
print 'probeSeed='  + (probed.seed is COLORS.black)
print 'probeEdge='  + (probed.up is COLORS.black)

# filling with the colour already there terminates instead of spinning
cls COLORS.black
fill 100, 100, COLORS.black
print 'noSpin=true'

# a seed outside the screen does nothing
fill -5, -5, COLORS.red
fill 9999, 9999, COLORS.red
print 'offscreen=true'

# fill obeys drawTo like every other primitive
sheet = surface 16, 16
drawTo sheet, ->
  cls COLORS.black
  fill 8, 8, COLORS.lime
print 'onSurface='   + (drawTo(sheet, -> pget 8, 8) is COLORS.lime)
print 'screenClean=' + (pget(8, 8) isnt COLORS.lime)
"""
  await setDoc filling
  await wait 500
  await clearConsole()
  await runAll()
  await wait 1500
  text   = await consoleText()
  wanted = ['inside=true', 'edgeKept=true', 'outside=true', 'leaked=true',
            'crossedBlue=true', 'crossedLime=true', 'stoppedAtBorder=true',
            'matched=true', 'byValue=true', 'valueStopped=true',
            'probeXY=true', 'probeChan=true', 'probeSeed=true', 'probeEdge=true',
            'noSpin=true', 'offscreen=true', 'onSurface=true', 'screenClean=true']
  absent = (want for want in wanted when not text.includes want)
  check 'fill walks, stops and retargets', absent.length is 0,
    if absent.length then "missing #{absent.join ', '}" else 'all eighteen'

  # 51. the paint axis reaches every primitive, not just fill
  painting = """
screen 320, 200

stripe = maker (p) -> if (p.x %% 8) < 4 then COLORS.red else COLORS.blue

# a maker as an argument, on each kind of primitive
cls COLORS.black
rectFill 0, 0, 15, 3, stripe
print 'rectFill=' + (pget(1, 1) is COLORS.red and pget(5, 1) is COLORS.blue)

cls COLORS.black
circleFill 40, 40, 10, stripe
print 'circleFill=' + (pget(40, 40) is COLORS.blue or pget(40, 40) is COLORS.red)

cls COLORS.black
line 0, 100, 15, 100, stripe
print 'line=' + (pget(1, 100) is COLORS.red and pget(5, 100) is COLORS.blue)

cls COLORS.black
color COLORS.white
textAt 0, 120, 'A'
cls COLORS.black
color stripe
textAt 0, 120, 'A'
print 'text=' + (pget(2, 120) is COLORS.red)

cls stripe
print 'cls=' + (pget(1, 1) is COLORS.red and pget(5, 1) is COLORS.blue)

# and as the current colour, so nothing needs an argument at all
cls COLORS.black
color stripe
rectFill 0, 0, 15, 3
print 'asColour=' + (pget(1, 1) is COLORS.red and pget(5, 1) is COLORS.blue)
color COLORS.white

# a maker sees the pixel it is replacing
cls COLORS.blue
rectFill 0, 0, 9, 9, maker (p) -> if p.color is COLORS.blue then COLORS.lime else COLORS.red
print 'seesUnder=' + (pget(5, 5) is COLORS.lime)

# and it is the same probe the rules take
cls COLORS.black
rectFill 0, 0, 9, 9, maker (p) -> if p.value < 0.5 then COLORS.yellow else COLORS.red
print 'sameProbe=' + (pget(5, 5) is COLORS.yellow)

# fill, with a maker, through the rule it already had
cls COLORS.black
rect 20, 20, 60, 60, COLORS.white
fill 40, 40, stripe
print 'filled=' + (pget(25, 40) is COLORS.red or pget(25, 40) is COLORS.blue)
print 'fillKeptEdge=' + (pget(20, 20) is COLORS.white)

# tile repeats a surface
patch = surface 2, 2
drawTo patch, ->
  point 0, 0, COLORS.red
  point 1, 0, COLORS.lime
  point 0, 1, COLORS.blue
  point 1, 1, COLORS.yellow
cls COLORS.black
rectFill 0, 0, 7, 7, tile patch
print 'tile=' + (pget(0, 0) is COLORS.red and pget(3, 0) is COLORS.lime and pget(2, 3) is COLORS.blue and pget(3, 3) is COLORS.yellow)

# gradient ramps along an angle
cls COLORS.black
rectFill 0, 0, 100, 4, gradient COLORS.black, COLORS.white, length: 100
print 'gradFrom=' + (pget(0, 1) is COLORS.black)
print 'gradMid='  + (pget(50, 1) is COLORS.fromRGB256 128, 128, 128)
print 'gradTo='   + (pget(100, 1) is COLORS.white)

# radial measures distance instead
cls COLORS.black
circleFill 50, 50, 50, radial COLORS.white, COLORS.black, x: 50, y: 50, radius: 50
print 'radialCentre=' + (pget(50, 50) is COLORS.white)

# HSV setters on the builder
print 'setValue=' + (COLORS.create().setRed(1).setValue(0.5).valueOf() is COLORS.fromRGB256 128, 0, 0)
print 'setHue='   + (COLORS.create().setRed(1).setHue(120).valueOf() is COLORS.lime)
print 'toHSV='    + (round(COLORS.toHSV(COLORS.lime).hue) is 120)

# a solid colour still takes the fast path and is unchanged
cls COLORS.black
rectFill 0, 0, 9, 9, COLORS.red
print 'solid=' + (pget(5, 5) is COLORS.red)
"""
  await setDoc painting
  await wait 500
  await clearConsole()
  await runAll()
  await wait 1500
  text   = await consoleText()
  wanted = ['rectFill=true', 'circleFill=true', 'line=true', 'text=true', 'cls=true',
            'asColour=true', 'seesUnder=true', 'sameProbe=true',
            'filled=true', 'fillKeptEdge=true', 'tile=true',
            'gradFrom=true', 'gradMid=true', 'gradTo=true', 'radialCentre=true',
            'setValue=true', 'setHue=true', 'toHSV=true', 'solid=true']
  absent = (want for want in wanted when not text.includes want)
  check 'paints reach every primitive', absent.length is 0,
    if absent.length then "missing #{absent.join ', '} -- #{JSON.stringify text.trim()}" else 'all nineteen'

  # 52. the solid path stays fast. The bound is deliberately far below what
  # the machine does, so this is a canary for a primitive quietly falling
  # onto the per-pixel path, not a benchmark.
  await setDoc "screen 320, 200\ncls()\nt = performance.now()\npoint i %% 320, (i / 320) %% 200, COLORS.red for i in [0...2000000] by 1\nrate = 2000000 / ((performance.now() - t) / 1000)\nprint 'rate=' + round(rate / 1000000)\n"
  await wait 500
  await clearConsole()
  await runAll()
  await wait 4000
  text = await consoleText()
  rate = Number /rate=(\d+)/.exec(text)?[1] ? 0
  check 'solid drawing stays on the fast path', rate >= 3, "#{rate}M points/sec"

  # the suite owns scratch.coffee and nothing else
  after = await fsp.readFile guarded, 'utf8'
  check 'suite does not touch real sketches', after is before, "hello.coffee #{after.length} bytes"

  # leave the user's layout the way we found it
  await js "localStorage.removeItem('panel.editor'); localStorage.removeItem('panel.console'); return true"

  console.log "\n#{if failures then "#{failures} FAILED" else 'all passed'}"

  # Only ever remove a data directory the test run created inside the repo.
  disposable = process.env.BEANS_DATA_HOME and paths.data.startsWith paths.root + path.sep
  if disposable and not failures
    await fsp.rm paths.data, recursive: yes, force: yes
    console.log "removed #{paths.data}"
  else if disposable
    console.log "left #{paths.data} in place for troubleshooting"

  failures
