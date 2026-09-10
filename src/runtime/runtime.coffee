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
  undefined

# --- commands ---------------------------------------------------------------

screen = (width, height) ->
  state.width  = width
  state.height = height
  Atomics.store state.i32, H.WIDTH,  width
  Atomics.store state.i32, H.HEIGHT, height
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
  pixel = if value? then toNative toColor value else state.native
  state.u32[state.base + y * state.width + x] = pixel
  undefined

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
  Object.assign globalThis, {screen, color, cls, point, pget, print, wait, buffer}
  globalThis.Interrupted = Interrupted
  setDouble no          # a restart must not inherit the last sketch's mode
  screen 320, 200
  undefined
