# Sound, the paint way round: a number is the simple case and a function is
# the unlimited one, in every slot.
#
#   sound 440, 0.5                                 # Hz, seconds
#   sound 'C4', 0.5, voice: 1, wave: 'square', volume: 0.3
#   sound ((t) -> 440 + 20 * sin(t * 30)), 2        # vibrato
#   sound 'A3', 1, volume: (t, u) -> 1 - u          # t seconds in, u from 0 to 1
#   sound 110, 1, wave: (phase) -> if phase < 0.25 then 1 else -1
#
# `sound` queues and returns. Each voice plays its notes in order, so one
# voice is a melody and several are harmony, with no timing code in sight.
# A voice is any number or name, made the first time it is used.
#
# Leave out the length and the note plays until it is stopped. Either way
# `sound` hands back the note, which can be changed or stopped while it plays:
#
#   held = sound 'C4', voice: key
#   held.frequency = 'D4'
#   held.stop 0.2                                   # a 0.2s fade
#   sound.stop 'bass'                               # a voice, queue and all
#
# Functions run here, in the sketch's worker, when the note is queued, and
# travel as samples: a curve at CONTROL_RATE, a waveform as one period. The
# audio thread never runs sketch code -- it cannot see the sketch's names,
# and a slow function there would be a click, not a slow frame.

H = LAYOUT.HEADER

CONTROL_RATE = LAYOUT.CONTROL_RATE    # 2ms steps, under any ear
TABLE        = 1024            # one period of a waveform made by a function
MAX_TABLE    = 4096            # longest waveform array taken as given

# The order is the audio thread's too: it switches on the number.
WAVES  = ['sine', 'square', 'triangle', 'saw', 'noise']
CUSTOM = WAVES.length

OP    = LAYOUT.SOUND_OP
FIELD = LAYOUT.SOUND_FIELD
HELD  = LAYOUT.SOUND_HELD

NOTE  = /^([A-Ga-g])([#b]?)(-?\d)$/
STEPS = {c: 0, d: 2, e: 4, f: 5, g: 7, a: 9, b: 11}

# A note name to Hz, equal tempered from A4 = 440. `C#4` and `Db4` are the same
# key; octaves change at C, as on a piano.
hz = (value) ->
  return value if typeof value is 'number' and isFinite value
  found = NOTE.exec String value
  throw new Error "sound: not a frequency or a note name: #{JSON.stringify value}" unless found
  [_, letter, accidental, octave] = found
  step = STEPS[letter.toLowerCase()] + (if accidental is '#' then 1 else if accidental is 'b' then -1 else 0)
  midi = 12 * (Number(octave) + 1) + step
  440 * 2 ** ((midi - 69) / 12)

level = (value) ->
  throw new Error "sound: volume must be a number, got #{JSON.stringify value}" unless typeof value is 'number' and isFinite value
  value

# A slot's value as samples: one for a constant, a curve for a function.
curve = (value, seconds, convert) ->
  return [convert value] unless typeof value is 'function'
  # A note with no length has no end to sample towards.
  throw new Error "sound: a note with no length takes plain values -- give it a length, or change it through the note" if seconds is HELD
  count = Math.max 2, Math.ceil(seconds * CONTROL_RATE) + 1
  for i in [0...count] by 1
    t = Math.min i / CONTROL_RATE, seconds
    convert value t, (if seconds > 0 then t / seconds else 1)

waveOf = (wave) ->
  if typeof wave is 'string'
    kind = WAVES.indexOf wave
    throw new Error "sound: no wave called #{JSON.stringify wave} -- try #{WAVES.join ', '}" if kind < 0
    return {kind, table: []}
  if typeof wave is 'function'
    return {kind: CUSTOM, table: (Number(wave i / TABLE) or 0 for i in [0...TABLE] by 1)}
  if Array.isArray(wave) or ArrayBuffer.isView(wave)
    throw new Error "sound: a wave array needs 1..#{MAX_TABLE} numbers" unless 0 < wave.length <= MAX_TABLE
    return {kind: CUSTOM, table: (Number(sample) or 0 for sample in wave)}
  throw new Error "sound: wave must be a name, an array or a function"

fade = (seconds) ->
  return 0 unless seconds?
  throw new Error "sound: a fade must be 0 or more seconds, got #{JSON.stringify seconds}" unless typeof seconds is 'number' and seconds >= 0
  seconds

state =
  i32:        null
  ring:       null
  yieldPoint: null
  voices:     new Map       # a sketch's name for a voice -> the number the audio thread uses
  notes:      0

attach = (sab, yieldPoint) ->
  state.i32  = new Int32Array sab, 0, LAYOUT.HEADER_WORDS
  state.ring = new Float32Array sab, LAYOUT.soundOffset, LAYOUT.SOUND_FLOATS
  state.yieldPoint = yieldPoint
  undefined

# Any number or name is a voice. Names are kept as given, so `1` and `'1'`
# are the same voice and `'bass'` is another; the audio thread only ever
# sees small numbers, made on first use.
voiceOf = (name) ->
  unless typeof name in ['number', 'string'] and String(name).length
    throw new Error "sound: a voice is a number or a name, got #{JSON.stringify name}"
  key = String name
  state.voices.set key, state.voices.size unless state.voices.has key
  state.voices.get key

# Waits for room rather than dropping: a note is not a console line, and a
# melody missing its middle is worse than a sketch that pauses to queue it.
# The wait is a yield point, so Stop and the prompt still get through.
reserve = (size) ->
  N = LAYOUT.SOUND_FLOATS
  loop
    head = Atomics.load state.i32, H.SOUND_HEAD
    tail = Atomics.load state.i32, H.SOUND_TAIL
    return head if N - 1 - ((head - tail + N) % N) >= size
    state.yieldPoint()
    Atomics.wait state.i32, H.SOUND_TAIL, tail, 20

post = (message) ->
  throw new Error "sound: that note is too long to queue -- split it into shorter ones" if message.length > LAYOUT.SOUND_FLOATS / 4
  N    = LAYOUT.SOUND_FLOATS
  head = reserve message.length
  state.ring[(head + i) % N] = value for value, i in message
  # Published only once it is all there: the audio thread reads up to HEAD.
  Atomics.store state.i32, H.SOUND_HEAD, (head + message.length) % N
  undefined

# What `sound` hands back. Changing it or stopping it reaches the audio
# thread within a render quantum, a few milliseconds. Once the note is over
# all of these quietly do nothing, so a sketch need not track which of its
# notes have finished.
class Note
  constructor: (@id, @voice, @seconds) ->

  stop: (seconds) ->
    post [OP.stopNote, @id, fade seconds]
    undefined

# Setters, so a change reads as an assignment. A function is fine on a note
# with a length -- it is sampled over the whole note, as at the start.
change = (note, field, samples) ->
  post [OP.set, note.id, field, samples.length, samples...]

Object.defineProperty Note.prototype, 'frequency',
  set: (value) -> change this, FIELD.frequency, curve value, @seconds, hz
Object.defineProperty Note.prototype, 'volume',
  set: (value) -> change this, FIELD.volume, curve value, @seconds, level

# The second argument is optional, so `sound 'C4', voice: key` reads the way
# it looks: the options have simply moved up a place.
sound = (frequency, seconds, options = {}) ->
  state.yieldPoint()
  [seconds, options] = [HELD, seconds] if seconds? and typeof seconds is 'object'
  seconds ?= HELD
  unless seconds is HELD or (typeof seconds is 'number' and seconds > 0)
    throw new Error "sound: seconds must be a number above 0, got #{JSON.stringify seconds}"
  voice = voiceOf options.voice ? 0
  pitch = curve frequency, seconds, hz
  loud  = curve options.volume ? 1, seconds, level
  {kind, table} = waveOf options.wave ? 'sine'
  id = ++state.notes
  post [OP.note, voice, id, seconds, kind, pitch.length, loud.length, table.length, pitch..., loud..., table...]
  new Note id, options.voice ? 0, seconds

# Everything, or one voice with its queue. A voice nobody has used is already
# silent, so stopping it is not a mistake.
sound.stop = (voice, seconds) ->
  if voice?
    post [OP.stopVoice, voiceOf(voice), fade seconds]
  else
    post [OP.stopAll, fade seconds]
  undefined

sound.hz = hz

globalThis.SOUND = {attach, sound, WAVES}
