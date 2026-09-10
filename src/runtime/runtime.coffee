# The drawing API. Runs inside the worker, where blocking is legal.

H      = LAYOUT.HEADER
MAXPIX = LAYOUT.MAX_PIXELS

class Interrupted extends Error
  constructor: -> super 'stopped'

state =
  i32:     null
  u32:     null
  width:   320
  height:  200
  double:  no
  base:    LAYOUT.bufferWords 0
  native:  0

checkInterrupt = ->
  throw new Interrupted() if Atomics.load(state.i32, H.INTERRUPT) is 1

refreshBase = ->
  front     = Atomics.load state.i32, H.FRONT
  state.base = LAYOUT.bufferWords if state.double then 1 - front else front

setDouble = (value) ->
  state.double = value
  Atomics.store state.i32, H.DOUBLE, if value then 1 else 0
  refreshBase()
  undefined

doSwap = ->
  checkInterrupt()
  Atomics.store state.i32, H.SWAP, 1
  while Atomics.load(state.i32, H.SWAP) is 1
    Atomics.wait state.i32, H.SWAP, 1, 100
    checkInterrupt()
  refreshBase()
  INPUT.claimHits()      # a frame boundary is also an input boundary
  undefined

# --- commands ---------------------------------------------------------------

screen = (width, height) ->
  state.width  = width
  state.height = height
  Atomics.store state.i32, H.WIDTH,  width
  Atomics.store state.i32, H.HEIGHT, height
  # A sketch that reads the mouse before it has moved should get somewhere
  # sensible, and a resolution change must not leave it out of bounds.
  centre = (index, limit) ->
    at = Atomics.load state.i32, index
    Atomics.store state.i32, index, limit >> 1 if at < 0 or at >= limit
  centre H.MOUSE_X, width
  centre H.MOUSE_Y, height
  cls()
  undefined

color = (value) ->
  state.native = toNative toColor value, state.native
  undefined

cls = (value) ->
  fill = if value? then toNative toColor value else 0xFF000000
  state.u32.fill fill, state.base, state.base + state.width * state.height
  undefined

point = (x, y, value) ->
  x |= 0
  y |= 0
  return undefined if x < 0 or y < 0 or x >= state.width or y >= state.height
  state.u32[state.base + y * state.width + x] = resolve value
  undefined

# --- shapes -----------------------------------------------------------------

# All of these write the buffer directly. Going through point() would pay for
# a bounds check plus a base lookup per pixel, which is the whole reason to
# have primitives at all.
resolve = (value) -> if value? then toNative toColor value else state.native

plot = (x, y, pixel) ->
  return if x < 0 or y < 0 or x >= state.width or y >= state.height
  state.u32[state.base + y * state.width + x] = pixel
  undefined

span = (y, from, to, pixel) ->
  return if y < 0 or y >= state.height
  left  = Math.max 0,                 Math.min from, to
  right = Math.min state.width - 1,   Math.max from, to
  return if left > right
  start = state.base + y * state.width + left
  state.u32.fill pixel, start, start + (right - left + 1)
  undefined

OUT = {LEFT: 1, RIGHT: 2, BOTTOM: 4, TOP: 8}

# Clipping first, so a line drawn from -1e9 to 1e9 costs the same as any
# other line instead of iterating a billion times off screen.
CLIPS = [
  [OUT.TOP,    (a, b, maxX, maxY) -> [a.x + (b.x - a.x) * (maxY - a.y) / (b.y - a.y), maxY]]
  [OUT.BOTTOM, (a, b, maxX, maxY) -> [a.x + (b.x - a.x) * (0    - a.y) / (b.y - a.y), 0]]
  [OUT.RIGHT,  (a, b, maxX, maxY) -> [maxX, a.y + (b.y - a.y) * (maxX - a.x) / (b.x - a.x)]]
  [OUT.LEFT,   (a, b, maxX, maxY) -> [0,    a.y + (b.y - a.y) * (0    - a.x) / (b.x - a.x)]]
]

outcode = (x, y, maxX, maxY) ->
  code  = 0
  code |= OUT.LEFT   if x < 0
  code |= OUT.RIGHT  if x > maxX
  code |= OUT.BOTTOM if y < 0
  code |= OUT.TOP    if y > maxY
  code

clipLine = (a, b) ->
  maxX = state.width  - 1
  maxY = state.height - 1
  return null unless isFinite(a.x) and isFinite(a.y) and isFinite(b.x) and isFinite(b.y)
  codeA = outcode a.x, a.y, maxX, maxY
  codeB = outcode b.x, b.y, maxX, maxY
  for attempt in [0...8] by 1
    return null    if codeA & codeB
    return [a, b]  unless codeA or codeB
    outside = if codeA then codeA else codeB
    for [bit, cut] in CLIPS when outside & bit
      [x, y] = cut a, b, maxX, maxY
      break
    return null unless isFinite(x) and isFinite(y)
    if outside is codeA
      a = {x, y}
      codeA = outcode x, y, maxX, maxY
    else
      b = {x, y}
      codeB = outcode x, y, maxX, maxY
  null

line = (x1, y1, x2, y2, value) ->
  clipped = clipLine {x: x1, y: y1}, {x: x2, y: y2}
  return undefined unless clipped
  [a, b] = clipped
  pixel  = resolve value

  x  = Math.round a.x
  y  = Math.round a.y
  ex = Math.round b.x
  ey = Math.round b.y
  dx =  Math.abs ex - x
  dy = -Math.abs(ey - y)
  sx = if x < ex then 1 else -1
  sy = if y < ey then 1 else -1
  error = dx + dy

  loop
    plot x, y, pixel
    break if x is ex and y is ey
    doubled = 2 * error
    if doubled >= dy
      error += dy
      x     += sx
    if doubled <= dx
      error += dx
      y     += sy
  undefined

rectFill = (x1, y1, x2, y2, value) ->
  pixel = resolve value
  top    = Math.max 0,                 Math.min y1, y2
  bottom = Math.min state.height - 1,  Math.max y1, y2
  span y, x1, x2, pixel for y in [top..bottom] by 1 if top <= bottom
  undefined

rect = (x1, y1, x2, y2, value) ->
  pixel  = resolve value
  top    = Math.min y1, y2
  bottom = Math.max y1, y2
  span top,    x1, x2, pixel
  span bottom, x1, x2, pixel
  left  = Math.min x1, x2
  right = Math.max x1, x2
  for y in [Math.max(0, top)..Math.min(state.height - 1, bottom)] by 1
    plot left,  y, pixel
    plot right, y, pixel
  undefined

# Scanline rather than midpoint: the loops are bounded by the screen, so a
# radius of a million costs nothing extra and cannot spin.
ellipseFill = (cx, cy, rx, ry, value) ->
  return undefined unless rx > 0 and ry > 0
  pixel  = resolve value
  top    = Math.max 0,                Math.ceil  cy - ry
  bottom = Math.min state.height - 1, Math.floor cy + ry
  for y in [top..bottom] by 1
    ratio = (y - cy) / ry
    continue if ratio * ratio > 1
    half = rx * Math.sqrt 1 - ratio * ratio
    span y, Math.round(cx - half), Math.round(cx + half), pixel
  undefined

# The union of the extreme x per row and the extreme y per column, which is
# connected everywhere and clips for free.
ellipse = (cx, cy, rx, ry, value) ->
  return undefined unless rx > 0 and ry > 0
  pixel = resolve value

  for y in [Math.max(0, Math.ceil cy - ry)..Math.min(state.height - 1, Math.floor cy + ry)] by 1
    ratio = (y - cy) / ry
    continue if ratio * ratio > 1
    half = rx * Math.sqrt 1 - ratio * ratio
    plot Math.round(cx - half), y, pixel
    plot Math.round(cx + half), y, pixel

  for x in [Math.max(0, Math.ceil cx - rx)..Math.min(state.width - 1, Math.floor cx + rx)] by 1
    ratio = (x - cx) / rx
    continue if ratio * ratio > 1
    half = ry * Math.sqrt 1 - ratio * ratio
    plot x, Math.round(cy - half), pixel
    plot x, Math.round(cy + half), pixel
  undefined

circle     = (cx, cy, r, value) -> ellipse     cx, cy, r, r, value
circleFill = (cx, cy, r, value) -> ellipseFill cx, cy, r, r, value

pget = (x, y) ->
  x |= 0
  y |= 0
  return 0 if x < 0 or y < 0 or x >= state.width or y >= state.height
  fromNative state.u32[state.base + y * state.width + x]

print = (args...) ->
  postMessage type: 'print', text: args.join ' '
  undefined

wait = (frames = 1) ->
  doSwap() for i in [1..frames] by 1
  undefined

buffer = {}
Object.defineProperty buffer, 'on',   get: -> setDouble yes
Object.defineProperty buffer, 'off',  get: -> setDouble no
Object.defineProperty buffer, 'swap', get: -> doSwap()

buffer.fps = (n) ->
  Atomics.store state.i32, H.FPS, n | 0
  undefined

# --- install ----------------------------------------------------------------

installMath = ->
  for name in Object.getOwnPropertyNames Math
    continue if name in ['constructor']
    globalThis[name.toLowerCase()] = Math[name]
  globalThis.rnd = (n) -> if n? then Math.random() * n else Math.random()
  undefined

globalThis.attach = (sab) ->
  state.i32 = new Int32Array  sab, 0, LAYOUT.HEADER_WORDS
  state.u32 = new Uint32Array sab
  state.native = toNative COLORS.white
  installMath()
  {keys, mouse} = INPUT.attach state
  Object.assign globalThis, {
    screen, color, cls, point, pget, print, wait, buffer, keys, mouse
    line, rect, rectFill, ellipse, ellipseFill, circle, circleFill
  }
  globalThis.Interrupted = Interrupted
  setDouble no          # a restart must not inherit the last sketch's mode
  screen 320, 200
  undefined
