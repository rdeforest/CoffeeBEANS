# Shared memory layout. Loaded by both the renderer and the worker, so it
# publishes onto globalThis rather than exporting.

HEADER =
  CONTROL:     0
  FRONT:       1     # which buffer index is currently on screen
  SWAP:        2     # 1 = worker is waiting for a frame to be presented
  INTERRUPT:   3     # 1 = unwind the sketch at the next yield point
  WIDTH:       4
  HEIGHT:      5
  MODE:        6
  DOUBLE:      7     # 1 = double buffered
  FPS:         8     # 0 = present as fast as the display allows
  FRAME:       9
  MOUSE_X:    10
  MOUSE_Y:    11
  MOUSE_BTN:  12
  MOUSE_WHEEL:13     # accumulates; the sketch consumes it by reading
  KEYS:       16     # 16..23, one bit per key: held right now
  KEYS_HIT:   24     # 24..31, sticky: went down since the sketch last looked

MAX_WIDTH    = 3840
MAX_HEIGHT   = 2160
MAX_PIXELS   = MAX_WIDTH * MAX_HEIGHT
HEADER_WORDS = 64        # 32..63 spare: wheel modes, gamepads, whatever comes
BUFFERS      = 2

globalThis.LAYOUT =
  HEADER:       HEADER
  KEY_WORDS:    8
  MAX_WIDTH:    MAX_WIDTH
  MAX_HEIGHT:   MAX_HEIGHT
  MAX_PIXELS:   MAX_PIXELS
  HEADER_WORDS: HEADER_WORDS
  BUFFERS:      BUFFERS
  TOTAL_BYTES:  (HEADER_WORDS + BUFFERS * MAX_PIXELS) * 4
  bufferWords:  (index) -> HEADER_WORDS + index * MAX_PIXELS
