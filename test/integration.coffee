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
