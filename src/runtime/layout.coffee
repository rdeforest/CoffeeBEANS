# Shared memory layout. Loaded by both the renderer and the worker, so it
# publishes onto globalThis rather than exporting.

HEADER =
  CONTROL:     0
  FRONT:       1     # which buffer index is currently on screen
  SWAP:        2     # 1 = worker is waiting for a frame to be presented, 2 = the same without a flip
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
  ASK_STATE:  40     # 0 idle, 1 a question is waiting, 2 answered, 3 threw, 4 being answered
  ASK_LEN:    41     # bytes of the question, then of the answer
  SOUND_HEAD: 42     # floats; written only by the worker
  SOUND_TAIL: 43     # floats; written only by the audio thread
  SOUND_EPOCH:44     # bumped by the renderer on a new worker: drop everything queued
  SOUND_HOLD: 45     # 1 = a pause of either kind; the audio clock stands still
  SOUND_STARTED: 46  # notes begun since the audio thread started; for tests and meters
  SOUND_PEAK: 47     # loudest sample of the last render quantum, in millionths
  SOUND_BUSY: 48     # how many voices have a note sounding
  SOUND_RATE: 49     # the audio thread's sample rate, once it is running
  KEYS_UP:    50     # 50..57, sticky: went up since the sketch last looked
  ASK_KIND:   58     # what the question in the ask buffer wants; see ASK_FOR

MAX_WIDTH    = 3840
MAX_HEIGHT   = 2160
MAX_PIXELS   = MAX_WIDTH * MAX_HEIGHT
HEADER_WORDS = 64        # 59..63 spare: gamepads, whatever comes
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

# A console line on its way to the worker and its answer on its way back.
# Its own region rather than a corner of the transfer one: a sketch can be
# parked inside `load` when a question arrives, and the two must not share a
# buffer. Shared memory for the same reason printing uses it -- a worker busy
# in a loop, or asleep in Atomics.wait, receives no messages, but it can still
# read memory at a yield point.
ASK_BYTES = 1 << 16

# Notes on their way to the audio thread, as floats: the same single-producer
# single-consumer ring as the console, for the same reason. The worker cannot
# be messaged while it is busy, and the audio thread must never wait on
# anybody, so neither side ever blocks the other.
SOUND_FLOATS = 1 << 20

PRINT_OFFSET = (HEADER_WORDS + BUFFERS * MAX_PIXELS + TRANSFER_PIXELS) * 4
ASK_OFFSET   = PRINT_OFFSET + PRINT_BYTES
SOUND_OFFSET = ASK_OFFSET + ASK_BYTES

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
  printOffset:     PRINT_OFFSET
  ASK_BYTES:       ASK_BYTES
  askOffset:       ASK_OFFSET
  # A line to evaluate, answered with what it shows as; or Tab's question,
  # {path, word}, answered with the names that fit, as JSON.
  ASK_FOR:         {value: 0, completion: 1}
  SOUND_FLOATS:    SOUND_FLOATS
  soundOffset:     SOUND_OFFSET
  CONTROL_RATE:    500     # samples a second for a note's frequency and volume curves
  # What travels on the sound ring; the worker writes these and the audio
  # thread switches on them.
  SOUND_OP:        {note: 1, set: 2, stopNote: 3, stopVoice: 4, stopAll: 5}
  SOUND_FIELD:     {frequency: 0, volume: 1}
  SOUND_HELD:      -1      # the length of a note with no length
  TOTAL_BYTES:     SOUND_OFFSET + SOUND_FLOATS * 4
  bufferWords:  (index) -> HEADER_WORDS + index * MAX_PIXELS
