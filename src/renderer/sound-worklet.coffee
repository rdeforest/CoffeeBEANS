# The audio thread. Reads notes off the shared ring, plays each voice's queue
# in order, and writes back a few numbers so the rest of the app can tell what
# it is doing. It never waits on anything and never runs sketch code: a
# function in a note arrives here already sampled.
#
# Loaded into the AudioWorklet scope with layout.coffee ahead of it, which is
# where LAYOUT comes from.

H = LAYOUT.HEADER

# Every note fades in and out over this long, whatever its volume says. A
# waveform cut off mid-swing is a click, and a click on every note is the
# sound of a beginner's first melody unless something prevents it.
EDGE = 0.005

# Summed voices go through tanh, so many at full volume bend rather than
# wrap; one voice at full volume sits comfortably below the ceiling. Past a
# few, turn each one down, as on a mixing desk.
DRIVE = 0.5

# Band-limiting for the two waves with a jump in them. Without it a square
# at a high note aliases into a whine an octave away from what was asked for.
polyBlep = (phase, step) ->
  if phase < step
    t = phase / step
    t + t - t * t - 1
  else if phase > 1 - step
    t = (phase - 1) / step
    t * t + t + t + 1
  else
    0

# The value of a sampled curve `t` seconds in, straight lines between
# samples. One sample is a constant.
at = (curve, t, rate) ->
  return curve[0] if curve.length is 1
  x = t * rate
  i = Math.floor x
  return curve[curve.length - 1] if i >= curve.length - 1
  curve[i] + (curve[i + 1] - curve[i]) * (x - i)

# A note plays out its length, or -- a note with no length -- until it is
# stopped. Stopping is a fade from wherever it is, never a cut.
class Voice
  constructor: ->
    @queue = []
    @note  = null
    @phase = 0
    @noise = 0

  sample: (dt, rate) ->
    unless @note
      return 0 unless @queue.length
      @note = @queue.shift()
      @note.t = 0
      @started = yes
    note = @note
    t    = note.t
    if t >= note.end
      @note = null
      @ended note
      return @sample dt, rate
    note.t += dt

    frequency = at note.pitch, t, rate
    volume    = at note.loud,  t, rate
    edge      = Math.min 1, t / EDGE, (note.end - t) / EDGE
    edge      = Math.min edge, 1 - (t - note.stopAt) / note.fade if note.stopAt?
    return 0 unless frequency > 0 and volume isnt 0

    step   = frequency * dt
    @phase = (@phase + step) % 1
    phase  = @phase
    value = switch note.kind
      when 0 then Math.sin 2 * Math.PI * phase
      when 1 then (if phase < 0.5 then 1 else -1) + polyBlep(phase, step) - polyBlep((phase + 0.5) % 1, step)
      when 2 then 1 - 4 * Math.abs(phase - 0.5)
      when 3 then 2 * phase - 1 - polyBlep(phase, step)
      when 4
        # Pitched noise: a new random value 32 times a period, so a low note
        # rumbles and a high one hisses.
        @noise = Math.random() * 2 - 1 if Math.floor((phase - step) * 32) isnt Math.floor(phase * 32)
        @noise
      else
        table = note.table
        x = phase * table.length
        i = Math.floor x
        a = table[i % table.length]
        a + (table[(i + 1) % table.length] - a) * (x - i)
    value * volume * Math.max 0, edge

  # Playing: fade out from here. Still queued: it never starts.
  stop: (note, seconds) ->
    if note is @note
      return if note.stopAt?                  # already on its way out
      note.fade   = Math.max seconds, EDGE
      note.stopAt = note.t
      note.end    = Math.min note.end, note.t + note.fade
    else
      @queue = (queued for queued in @queue when queued isnt note)
      @ended note

  stopAll: (seconds) ->
    @ended queued for queued in @queue
    @queue = []
    @stop @note, seconds if @note

class BeansSound extends AudioWorkletProcessor
  constructor: ->
    super()
    # Made on first use, dropped when idle: there is no limit on voices, and
    # a voice with nothing to play costs nothing.
    @voices = new Map         # the worker's number for a voice -> Voice
    @notes  = new Map         # note id -> the voice holding it, while it lives
    @live   = []
    @i32    = null
    @port.onmessage = ({data}) =>
      @i32  = new Int32Array data, 0, LAYOUT.HEADER_WORDS
      @ring = new Float32Array data, LAYOUT.soundOffset, LAYOUT.SOUND_FLOATS
      @epoch = Atomics.load @i32, H.SOUND_EPOCH
      Atomics.store @i32, H.SOUND_RATE, sampleRate

  voice: (number) ->
    unless @voices.has number
      voice = new Voice
      voice.ended = (note) => @notes.delete note.id
      @voices.set number, voice
    @voices.get number

  flush: ->
    @voices.clear()
    @notes.clear()
    Atomics.store @i32, H.SOUND_TAIL, Atomics.load @i32, H.SOUND_HEAD

  # Everything the worker has published: notes onto their voices' queues,
  # changes and stops onto the notes they name. A change for a note that has
  # already ended finds nothing, which is fine.
  take: ->
    N    = LAYOUT.SOUND_FLOATS
    OP   = LAYOUT.SOUND_OP
    ring = @ring
    head = Atomics.load @i32, H.SOUND_HEAD
    tail = Atomics.load @i32, H.SOUND_TAIL
    return if head is tail
    one = ->
      value = ring[tail]
      tail = (tail + 1) % N
      value
    read = (count) ->
      out = new Float32Array count
      out[i] = one() for i in [0...count] by 1
      out
    while tail isnt head
      switch one()
        when OP.note
          [number, id, seconds, kind, pitches, louds, tables] = read 7
          note  = {id, kind, pitch: read(pitches), loud: read(louds), table: read(tables)}
          note.end = if seconds is LAYOUT.SOUND_HELD then Infinity else seconds
          voice = @voice number
          voice.queue.push note
          @notes.set id, voice
        when OP.set
          [id, field, count] = read 3
          samples = read count
          note = @notes.get(id)?.note
          note = null unless note?.id is id
          # Queued notes are found in their voice's queue instead.
          note ?= (queued for queued in @notes.get(id)?.queue ? [] when queued.id is id)[0]
          if note
            if field is LAYOUT.SOUND_FIELD.frequency then note.pitch = samples else note.loud = samples
        when OP.stopNote
          [id, seconds] = read 2
          voice = @notes.get id
          if voice
            note = if voice.note?.id is id then voice.note else (queued for queued in voice.queue when queued.id is id)[0]
            voice.stop note, seconds if note
        when OP.stopVoice
          [number, seconds] = read 2
          @voices.get(number)?.stopAll seconds
        when OP.stopAll
          [seconds] = read 1
          voice.stopAll seconds for voice from @voices.values()
        else
          # A ring that says something we do not understand cannot be read
          # past; drop the rest rather than play garbage.
          tail = head
    Atomics.store  @i32, H.SOUND_TAIL, tail
    Atomics.notify @i32, H.SOUND_TAIL     # a worker waiting for room

  process: (inputs, outputs) ->
    out = outputs[0]
    return true unless @i32
    # A new worker, or a Stop: what was queued belongs to a sketch that is
    # gone, and must not play over the next one. Not the interrupt flag, which
    # stays raised after a Stop and would swallow a note typed at the prompt.
    epoch = Atomics.load @i32, H.SOUND_EPOCH
    if epoch isnt @epoch
      @epoch = epoch
      @flush()
    else
      @take()

    # Only voices with something to do are visited, and idle ones are let go.
    @live.length = 0
    for [number, voice] from @voices
      if voice.note or voice.queue.length then @live.push voice else @voices.delete number
    live = @live

    # Paused, the audio clock stands still with the frame clock.
    held = Atomics.load(@i32, H.SOUND_HOLD) is 1
    length = out[0].length
    peak = 0
    unless held
      dt = 1 / sampleRate
      rate = LAYOUT.CONTROL_RATE
      for n in [0...length] by 1
        sum = 0
        sum += voice.sample dt, rate for voice in live
        value = Math.tanh sum * DRIVE
        peak  = Math.max peak, Math.abs value
        channel[n] = value for channel in out
    busy = 0
    for voice in live
      busy += 1 if voice.note
      if voice.started
        voice.started = no
        Atomics.add @i32, H.SOUND_STARTED, 1
    Atomics.store @i32, H.SOUND_PEAK, Math.round peak * 1e6
    Atomics.store @i32, H.SOUND_BUSY, busy
    true

registerProcessor 'beans-sound', BeansSound
