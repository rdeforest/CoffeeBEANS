# Polled, not evented -- a worker parked in Atomics.wait cannot receive a
# message, so the main thread writes shared memory and the sketch reads it.
# That is also the shape BASIC had, and `if keys.down 'space'` inside a loop
# reads the way INKEY$ did.

H     = LAYOUT.HEADER
WORDS = LAYOUT.KEY_WORDS

state = null
hits  = new Uint32Array WORDS

anySet = (read, bits) ->
  for bit in bits
    return true if (read(bit >>> 5) & (1 << (bit & 31))) isnt 0
  false

held = (word) -> Atomics.load state.i32, H.KEYS + word

keys =
  down: (name) -> anySet held,               KEYTABLE.bitsFor name
  hit:  (name) -> anySet ((w) -> hits[w]),   KEYTABLE.bitsFor name
  any:  -> (held(word) isnt 0 for word in [0...WORDS]).some Boolean

# Hits are sticky in shared memory until claimed, so a tap that begins and
# ends between two frames still registers. Claiming is per frame: swap does
# it, and a sketch that never swaps can do it by hand.
claimHits = ->
  hits[word] = Atomics.exchange state.i32, H.KEYS_HIT + word, 0 for word in [0...WORDS]
  undefined

Object.defineProperty keys, 'poll', get: -> claimHits()

mouse = {}

reader = (index) -> -> Atomics.load state.i32, index
button = (mask) -> -> (Atomics.load(state.i32, H.MOUSE_BTN) & mask) isnt 0

Object.defineProperty mouse, 'x',      get: reader H.MOUSE_X
Object.defineProperty mouse, 'y',      get: reader H.MOUSE_Y
Object.defineProperty mouse, 'left',   get: button 1
Object.defineProperty mouse, 'right',  get: button 2
Object.defineProperty mouse, 'middle', get: button 4
Object.defineProperty mouse, 'down',   get: -> Atomics.load(state.i32, H.MOUSE_BTN) isnt 0
# Reading consumes: wheel movement is a delta since you last asked.
Object.defineProperty mouse, 'wheel',  get: -> Atomics.exchange state.i32, H.MOUSE_WHEEL, 0

globalThis.INPUT =
  attach: (shared) ->
    state = shared
    claimHits()
    {keys, mouse}
  claimHits: claimHits
