# The colour and paint axis: fill rules, makers, tiles, gradients, HSV.

module.exports = (t) ->
  {wait, check, setDoc, runAll, consoleText, clearConsole, settled} = t
  # 43. fromHSV, in degrees, beside fromRGB
  await setDoc "print 'red='   + (COLORS.fromHSV(0)   is COLORS.red)\nprint 'lime='  + (COLORS.fromHSV(120) is COLORS.lime)\nprint 'blue='  + (COLORS.fromHSV(240) is COLORS.blue)\nprint 'white=' + (COLORS.fromHSV(0, 0, 1) is COLORS.white)\nprint 'black=' + (COLORS.fromHSV(0, 0, 0) is COLORS.black)\nprint 'wraps=' + (COLORS.fromHSV(370) is COLORS.fromHSV(10))\nprint 'negative=' + (COLORS.fromHSV(-120) is COLORS.fromHSV(240))\n"
  await wait 500
  await clearConsole()
  await runAll()
  text   = await settled()
  wanted = ['red=true', 'lime=true', 'blue=true', 'white=true', 'black=true', 'wraps=true', 'negative=true']
  absent = (want for want in wanted when not text.includes want)
  check 'COLORS.fromHSV converts and wraps', absent.length is 0,
    if absent.length then "missing #{absent.join ', '}" else 'all seven'

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
  text   = await settled()
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
  text   = await settled()
  wanted = ['rectFill=true', 'circleFill=true', 'line=true', 'text=true', 'cls=true',
            'asColour=true', 'seesUnder=true', 'sameProbe=true',
            'filled=true', 'fillKeptEdge=true', 'tile=true',
            'gradFrom=true', 'gradMid=true', 'gradTo=true', 'radialCentre=true',
            'setValue=true', 'setHue=true', 'toHSV=true', 'solid=true']
  absent = (want for want in wanted when not text.includes want)
  check 'paints reach every primitive', absent.length is 0,
    if absent.length then "missing #{absent.join ', '} -- #{JSON.stringify text.trim()}" else 'all nineteen'
