# Pixels where the primitives claim to put them -- shapes, clipping,
# rounding, surfaces, blits, stamps and text.

module.exports = (t) ->
  {wait, check, setDoc, runAll, consoleText, clearConsole, settled} = t
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
  text   = await settled()
  wanted = ['lineStart=true', 'lineEnd=true', 'rectEdge=true', 'rectHollow=false',
            'fillCentre=true', 'circleRim=true', 'circleHollow=false', 'discCentre=true']
  absent = (want for want in wanted when not text.includes want)
  check 'shapes land where they claim', absent.length is 0, "missing #{absent.join ', '}"

  # 22. clipping, not iterating: a line across a billion pixels is cheap
  await setDoc "screen 320, 200\ncls()\nt = performance.now()\nline -1e9, -1e9, 1e9, 1e9, COLORS.white\nline 400, 400, 900, 900, COLORS.red\nprint 'ms=' + round(performance.now() - t)\nprint 'diagonal=' + (pget(160, 160) is COLORS.white)\nprint 'offscreen=' + (pget(319, 199) is COLORS.red)\n"
  await wait 500
  await clearConsole()
  await runAll()
  text = await settled()
  elapsed = Number /ms=(\d+)/.exec(text)?[1] ? 9999
  check 'line clips instead of iterating', elapsed < 50 and text.includes('diagonal=true') and text.includes('offscreen=false'), JSON.stringify text.trim()

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
  text   = await settled()
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
  text = await settled()
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
  text   = await settled()
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
  text = await settled()
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
  text2  = await settled()
  wanted = ['glyphOn=true', 'glyphOff=true', 'width=40', 'located=true',
            'scaled=true', 'scaledWidth=32', 'wrapped=true',
            'onSurface=true', 'screenClean=true', 'missingBox=true', 'timing=true']
  absent = (want for want in wanted when not text2.includes want)
  check 'text renders, positions, scales and retargets', absent.length is 0,
    if absent.length then "missing #{absent.join ', '}" else 'all eleven'

  # 37. fractional corners land on whole rows instead of mid-row
  await setDoc "screen 320, 200\ncls()\nrectFill 0, 2.5, 10, 5.5, COLORS.white\nprint 'inside=' + (pget(5, 4) is COLORS.white)\nprint 'rowStart=' + (pget(0, 3) is COLORS.white)\nprint 'wrapped=' + (pget(300, 2) is COLORS.white)\n"
  await wait 500
  await clearConsole()
  await runAll()
  text = await settled()
  check 'rectFill rounds fractional corners', text.includes('inside=true') and text.includes('rowStart=true') and text.includes('wrapped=false'), JSON.stringify text.trim()
