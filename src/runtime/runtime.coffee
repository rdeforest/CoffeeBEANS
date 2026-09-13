# The drawing API. Runs inside the worker, where blocking is legal.

H      = LAYOUT.HEADER
MAXPIX = LAYOUT.MAX_PIXELS

class Interrupted extends Error
  constructor: -> super 'stopped'

state =
  i32:        null
  u32:        null
  double:     no
  native:     0
  frameStart: null
  started:    0

# Everything that draws writes to `target`. The screen is just the target
# that happens to live in shared memory; a Surface is one that does not, so
# every primitive works off screen for free.
display =
  pixels: null
  base:   LAYOUT.bufferWords 0
  width:  320
  height: 200

target = display

checkInterrupt = ->
  throw new Interrupted() if Atomics.load(state.i32, H.INTERRUPT) is 1

refreshBase = ->
  front        = Atomics.load state.i32, H.FRONT
  display.base = LAYOUT.bufferWords if state.double then 1 - front else front

setDouble = (value) ->
  state.double = value
  Atomics.store state.i32, H.DOUBLE, if value then 1 else 0
  refreshBase()
  undefined

doSwap = ->
  flushPrint()
  checkInterrupt()
  # Time from the previous swap returning to this one being asked for: the
  # cost of the sketch's own frame, which is the number worth tuning.
  now = performance.now()
  Atomics.store state.i32, H.SKETCH_US, Math.round (now - state.frameStart) * 1000 if state.frameStart?
  Atomics.store state.i32, H.SWAP, 1
  try
    while Atomics.load(state.i32, H.SWAP) is 1
      Atomics.wait state.i32, H.SWAP, 1, 100
      checkInterrupt()
  finally
    # Whether the frame landed or a stop got there first, the renderer may
    # have flipped; a stale base would have the next run draw on screen.
    refreshBase()
  INPUT.claimHits()      # a frame boundary is also an input boundary
  state.frameStart = performance.now()
  undefined

# --- commands ---------------------------------------------------------------

# Like BASIC's SCREEN, this also resets the page mode. Modes persist in the
# live worker, so without this a sketch run after a stopped double-buffered
# one would draw into the back buffer, never swap, and show nothing but the
# old sketch's last frame. Put `buffer.on` after `screen`.
screen = (width, height) ->
  display.width  = width
  display.height = height
  Atomics.store state.i32, H.WIDTH,  width
  Atomics.store state.i32, H.HEIGHT, height
  setDouble no
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
  target.pixels.fill fill, target.base, target.base + target.width * target.height
  undefined

point = (x, y, value) ->
  x |= 0
  y |= 0
  return undefined if x < 0 or y < 0 or x >= target.width or y >= target.height
  target.pixels[target.base + y * target.width + x] = resolve value
  undefined

# --- shapes -----------------------------------------------------------------

# All of these write the buffer directly. Going through point() would pay for
# a bounds check plus a base lookup per pixel, which is the whole reason to
# have primitives at all.
resolve = (value) -> if value? then toNative toColor value else state.native

plot = (x, y, pixel) ->
  return if x < 0 or y < 0 or x >= target.width or y >= target.height
  target.pixels[target.base + y * target.width + x] = pixel
  undefined

span = (y, from, to, pixel) ->
  return if y < 0 or y >= target.height
  left  = Math.max 0,                 Math.min from, to
  right = Math.min target.width - 1,   Math.max from, to
  return if left > right
  start = target.base + y * target.width + left
  target.pixels.fill pixel, start, start + (right - left + 1)
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
  maxX = target.width  - 1
  maxY = target.height - 1
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

# The rect family and get take corners in pixels. Rounding here rather than
# in span keeps a fractional y from landing mid-row: y * width with y = 2.5
# is not a row start, it is halfway across one.
rectFill = (x1, y1, x2, y2, value) ->
  x1 = Math.round x1; y1 = Math.round y1; x2 = Math.round x2; y2 = Math.round y2
  pixel = resolve value
  top    = Math.max 0,                 Math.min y1, y2
  bottom = Math.min target.height - 1,  Math.max y1, y2
  span y, x1, x2, pixel for y in [top..bottom] by 1 if top <= bottom
  undefined

rect = (x1, y1, x2, y2, value) ->
  x1 = Math.round x1; y1 = Math.round y1; x2 = Math.round x2; y2 = Math.round y2
  pixel  = resolve value
  top    = Math.min y1, y2
  bottom = Math.max y1, y2
  span top,    x1, x2, pixel
  span bottom, x1, x2, pixel
  left  = Math.min x1, x2
  right = Math.max x1, x2
  for y in [Math.max(0, top)..Math.min(target.height - 1, bottom)] by 1
    plot left,  y, pixel
    plot right, y, pixel
  undefined

# Scanline rather than midpoint: the loops are bounded by the screen, so a
# radius of a million costs nothing extra and cannot spin.
ellipseFill = (cx, cy, rx, ry, value) ->
  return undefined unless rx > 0 and ry > 0
  pixel  = resolve value
  top    = Math.max 0,                Math.ceil  cy - ry
  bottom = Math.min target.height - 1, Math.floor cy + ry
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

  for y in [Math.max(0, Math.ceil cy - ry)..Math.min(target.height - 1, Math.floor cy + ry)] by 1
    ratio = (y - cy) / ry
    continue if ratio * ratio > 1
    half = rx * Math.sqrt 1 - ratio * ratio
    plot Math.round(cx - half), y, pixel
    plot Math.round(cx + half), y, pixel

  for x in [Math.max(0, Math.ceil cx - rx)..Math.min(target.width - 1, Math.floor cx + rx)] by 1
    ratio = (x - cx) / rx
    continue if ratio * ratio > 1
    half = ry * Math.sqrt 1 - ratio * ratio
    plot x, Math.round(cy - half), pixel
    plot x, Math.round(cy + half), pixel
  undefined

circle     = (cx, cy, r, value) -> ellipse     cx, cy, r, r, value
circleFill = (cx, cy, r, value) -> ellipseFill cx, cy, r, r, value

# --- surfaces ---------------------------------------------------------------

surface = (width, height) -> new SURFACE.Surface width, height

# GET in GW-BASIC, and the same corner-to-corner arguments as rect.
get = (x1, y1, x2, y2) ->
  x1 = Math.round x1; y1 = Math.round y1; x2 = Math.round x2; y2 = Math.round y2
  left   = Math.max 0,                 Math.min x1, x2
  top    = Math.max 0,                 Math.min y1, y2
  right  = Math.min target.width  - 1, Math.max x1, x2
  bottom = Math.min target.height - 1, Math.max y1, y2
  return surface 1, 1 if left > right or top > bottom

  taken = surface right - left + 1, bottom - top + 1
  for y in [0...taken.height] by 1
    from = target.base + (top + y) * target.width + left
    taken.pixels.set target.pixels.subarray(from, from + taken.width), y * taken.width
  taken

put = (source, x, y, mode) ->
  SURFACE.blit target, Math.round(x), Math.round(y), source, mode
  undefined

stamp = (source, x, y, options) ->
  SURFACE.stamp target, x, y, source, options
  undefined

overlaps = SURFACE.overlaps

# Bare, this is a mode, like the current colour. Given a body it is scoped,
# which is what you want almost every time -- forgetting to change back
# means the rest of your sketch draws somewhere you cannot see.
drawTo = (destination, body) ->
  previous = target
  target   = destination ? display
  return undefined unless body?
  try
    result = body()
  finally
    target = previous
  result

# --- loading ----------------------------------------------------------------

# Blocking, like buffer.swap, and for the same reason: a worker parked in
# Atomics.wait cannot receive a message, but it can still send one before it
# parks. So the request goes out, the worker sleeps, and the answer arrives
# in shared memory.
LOAD_TIMEOUT = 15000

loadFailure = ->
  length  = Atomics.load state.i32, H.LOAD_W
  bytes   = new Uint8Array state.u32.buffer, LAYOUT.transferWords * 4, length
  message = new TextDecoder().decode bytes
  Atomics.store state.i32, H.LOAD_STATE, 0
  new Error message

load = (url) ->
  Atomics.store state.i32, H.LOAD_ID, Atomics.load(state.i32, H.LOAD_ID) + 1
  Atomics.store state.i32, H.LOAD_STATE, 1
  postMessage {type: 'load', url: String url}

  deadline = performance.now() + LOAD_TIMEOUT
  while Atomics.load(state.i32, H.LOAD_STATE) is 1
    checkInterrupt()
    if performance.now() > deadline
      Atomics.store state.i32, H.LOAD_STATE, 0
      throw new Error "load timed out after #{LOAD_TIMEOUT / 1000}s: #{url}"
    Atomics.wait state.i32, H.LOAD_STATE, 1, 100

  throw loadFailure() if Atomics.load(state.i32, H.LOAD_STATE) is 3

  width  = Atomics.load state.i32, H.LOAD_W
  height = Atomics.load state.i32, H.LOAD_H
  loaded = surface width, height
  from   = LAYOUT.transferWords
  loaded.pixels.set state.u32.subarray from, from + width * height
  Atomics.store state.i32, H.LOAD_STATE, 0
  loaded

# --- text -------------------------------------------------------------------

# One cursor, in character cells, the way BASIC had it. Text goes through the
# same plot/span the shapes use, so it lands on a surface under drawTo too.
cursor =
  col:        0
  row:        0
  scale:      1
  background: null

cellWidth  = -> FONT.width  * cursor.scale
cellHeight = -> FONT.height * cursor.scale

drawGlyph = (character, x, y, pixel, background) ->
  rows  = FONT.rows character
  scale = cursor.scale
  for gy in [0...FONT.height] by 1
    bits = rows[gy]
    for gx in [0...FONT.width] by 1
      value = if (bits >> gx) & 1 then pixel else background
      continue unless value?
      if scale is 1
        plot x + gx, y + gy, value
      else
        left = x + gx * scale
        span y + gy * scale + row, left, left + scale - 1, value for row in [0...scale] by 1
  undefined

writeAt = (x, y, string, pixel, background) ->
  for character in string
    drawGlyph character, x, y, pixel, background
    x += cellWidth()
  undefined

locate = (col, row) ->
  cursor.col = col | 0
  cursor.row = row | 0
  undefined

textScale = (scale) ->
  cursor.scale = Math.max 1, scale | 0
  undefined

textBackground = (value) ->
  cursor.background = value ? null
  undefined

textWidth = (string) -> String(string).length * cellWidth()

text = (parts...) ->
  string     = parts.join ' '
  pixel      = state.native
  background = if cursor.background? then toNative toColor cursor.background else null
  columns    = Math.max 1, Math.floor target.width / cellWidth()

  for character in string
    if character is '\n'
      cursor.col = 0
      cursor.row += 1
      continue
    if cursor.col >= columns
      cursor.col = 0
      cursor.row += 1
    drawGlyph character, cursor.col * cellWidth(), cursor.row * cellHeight(), pixel, background
    cursor.col += 1
  undefined

textAt = (x, y, parts...) ->
  background = if cursor.background? then toNative toColor cursor.background else null
  writeAt x, y, parts.join(' '), state.native, background
  undefined

pget = (x, y) ->
  x |= 0
  y |= 0
  return 0 if x < 0 or y < 0 or x >= target.width or y >= target.height
  fromNative target.pixels[target.base + y * target.width + x]

# Prints are batched. One message per line was fine until a sketch printed
# every iteration of a tight loop and the renderer drowned in messages it
# could not append fast enough. A lone print still goes out at once; a burst
# rides in one message per frame. The batch also flushes at every swap and
# when the run ends, so nothing is held past a point the console could have
# shown it, and a flood keeps only its most recent lines.
PRINT_CAP   = 2000
PRINT_EVERY = 16           # ms, about one frame
printed     = []
printedAt   = -Infinity

flushPrint = ->
  return unless printed.length
  postMessage type: 'print', lines: printed
  printed   = []
  printedAt = performance.now()
  undefined

print = (args...) ->
  printed.push args.join ' '
  printed.splice 0, PRINT_CAP >> 1 if printed.length > PRINT_CAP
  flushPrint() if performance.now() - printedAt >= PRINT_EVERY
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
  display.pixels = state.u32
  state.native = toNative COLORS.white
  installMath()
  {keys, mouse} = INPUT.attach state
  Object.assign globalThis, {
    screen, color, cls, point, pget, print, wait, buffer, keys, mouse
    line, rect, rectFill, ellipse, ellipseFill, circle, circleFill
    surface, get, put, stamp, drawTo, overlaps, display
    locate, text, textAt, textScale, textBackground, textWidth, load
  }
  Object.defineProperty globalThis, 'elapsed', get: -> (performance.now() - state.started) / 1000
  Object.defineProperty globalThis, 'frames',  get: -> Atomics.load state.i32, H.FRAME
  globalThis.Interrupted = Interrupted
  state.started = performance.now()
  globalThis.RUNTIME     = {flushPrint}   # for worker-boot, at the end of a run
  setDouble no          # a restart must not inherit the last sketch's mode
  screen 320, 200
  undefined
