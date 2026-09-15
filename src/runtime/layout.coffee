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
  SKETCH_US:  32     # microseconds the sketch spent building the last frame
  LOAD_STATE: 33     # 0 idle, 1 asked, 2 pixels ready, 3 failed
  LOAD_W:     34     # width, or the error message length when state is 3
  LOAD_H:     35
  LOAD_ID:    36
  PRINT_HEAD: 37     # bytes; written only by the worker
  PRINT_TAIL: 38     # bytes; written only by the renderer
  PRINT_LOST: 39     # lines dropped because the ring was full

MAX_WIDTH    = 3840
MAX_HEIGHT   = 2160
MAX_PIXELS   = MAX_WIDTH * MAX_HEIGHT
HEADER_WORDS = 64        # 37..63 spare: gamepads, audio, whatever comes
BUFFERS      = 2

# Where a loaded image lands on its way from the main process to the worker.
# Big enough for a 2048-square image, which is far past anything this toy
# wants to be blitting around.
TRANSFER_PIXELS = 2048 * 2048

# Console text, as a single-producer single-consumer ring. postMessage could
# not work here: a worker busy in a loop, or parked in Atomics.wait, delivers
# nothing until it yields, so a print could sit invisible for as long as the
# sketch was busy. Shared memory is readable whatever the worker is doing.
PRINT_BYTES = 1 << 20

globalThis.LAYOUT =
  HEADER:       HEADER
  KEY_WORDS:    8
  MAX_WIDTH:    MAX_WIDTH
  MAX_HEIGHT:   MAX_HEIGHT
  MAX_PIXELS:   MAX_PIXELS
  HEADER_WORDS: HEADER_WORDS
  BUFFERS:      BUFFERS
  TRANSFER_PIXELS: TRANSFER_PIXELS
  transferWords:   HEADER_WORDS + BUFFERS * MAX_PIXELS
  PRINT_BYTES:     PRINT_BYTES
  printOffset:    (HEADER_WORDS + BUFFERS * MAX_PIXELS + TRANSFER_PIXELS) * 4
  TOTAL_BYTES:    (HEADER_WORDS + BUFFERS * MAX_PIXELS + TRANSFER_PIXELS) * 4 + PRINT_BYTES
  bufferWords:  (index) -> HEADER_WORDS + index * MAX_PIXELS
