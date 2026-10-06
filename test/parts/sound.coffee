# Sound. Nobody is listening during a test run, so these read what the audio
# thread says it is doing: how many notes it has begun, which voices are busy,
# and how loud the last few milliseconds were. Waits are polls on those, never
# guesses at how long a note takes to start.

module.exports = (t) ->
  {wait, check, setDoc, evalAll, consoleText, clearConsole, js,
   status, settled, ask, click} = t

  until_ = (probe, limit = 5000) ->
    deadline = Date.now() + limit
    loop
      value = await probe()
      return value if value
      return null if Date.now() > deadline
      await wait 10

  started = -> js "return Sound.started()"
  busy    = -> js "return Sound.busy()"
  peak    = -> js "return Sound.peak()"

  run = (source) ->
    await setDoc source
    await wait 400
    await clearConsole()
    await evalAll()
    await settled()

  # 1. the audio thread is up
  rate = await until_ -> js "return Sound.rate()"
  check 'the audio thread is running', rate > 0, "rate=#{rate}"

  # 2. a note queues and returns at once, then plays and ends
  before = await started()
  text = await run "t = performance.now()\nsound 440, 0.3\nprint 'took=' + round(performance.now() - t)\n"
  took = Number /took=(\d+)/.exec(text)?[1] ? 999
  began = await until_ -> (await started()) > before
  loud  = await until_ -> (await peak()) > 0.05
  over  = await until_ (-> (await busy()) is 0 and (await peak()) is 0), 3000
  check 'sound returns at once, then the note plays and ends',
    took < 50 and began and loud and over, "took=#{took}ms began=#{began} loud=#{loud} over=#{over}"

  # 3. notes on one voice play in turn
  before = await started()
  await run "sound 'C4', 0.25\nsound 'E4', 0.25\n"
  first  = await until_ -> (await started()) is before + 1
  await wait 60
  single = (await started()) is before + 1
  second = await until_ -> (await started()) is before + 2
  check 'notes on one voice play one after another', first and single and second,
    "first=#{first} stillOne=#{single} second=#{second}"
  await until_ -> (await busy()) is 0

  # 4. voices play together
  await run "sound 'C4', 0.4\nsound 'E4', 0.4, voice: 1\nsound 'G4', 0.4, voice: 2\n"
  chord = await until_ -> (await busy()) is 3
  check 'three voices sound at once', chord, "busy=#{await busy()}"
  await until_ -> (await busy()) is 0

  # 5. functions in every slot, and note names
  text = await run """
sound 'A3', 0.2, volume: ((t, u) -> 1 - u), wave: (phase) -> sin(phase * 2 * pi)
sound ((t) -> 300 + 100 * t), 0.2, wave: [0, 1, 0, -1]
print 'a4=' + sound.hz('A4') + ' c4=' + sound.hz('C4').toFixed(2) + ' bb3=' + sound.hz('Bb3').toFixed(2)
"""
  shaped = await until_ -> (await peak()) > 0.01
  check 'functions and arrays shape a note; names are notes',
    shaped and text.includes('a4=440 c4=261.63 bb3=233.08'), JSON.stringify text.trim()
  await until_ -> (await busy()) is 0

  # 6. mistakes are caught at the line that made them
  for [source, expect] in [
    ["sound 440, 0.1, wave: 'wobble'", 'no wave called']
    ["sound 'H4', 0.1",                'not a frequency or a note name']
    ["sound 440, 0",                   'seconds must be']
    ["sound 440, 0.1, voice: {}",      'a voice is a number or a name']
    ["sound 440, volume: (t) -> t",    'a note with no length takes plain values']
    ["n = sound 440, 0.1\nn.stop -1",  'a fade must be']
  ]
    text = await run source
    check "a bad note says why: #{expect}", text.includes(expect) and /line [12]\b/.test(text), JSON.stringify text.trim()

  # 6b. voices are made on first use, as many as you like, by number or name
  await run "sound 200 + i * 40, 0.5, voice: 'v' + i, volume: 0.1 for i in [0...12]\n"
  many = await until_ -> (await busy()) is 12
  check 'twelve named voices sound at once', many, "busy=#{await busy()}"
  await until_ -> (await busy()) is 0

  # 6c. a note with no length plays until it is stopped
  await run "held = sound 330, voice: 'key'\n"
  on_ = await until_ -> (await busy()) is 1 and (await peak()) > 0.05
  await wait 500
  still = (await busy()) is 1 and (await peak()) > 0.05
  await ask 'held.stop()'
  ended = await until_ (-> (await busy()) is 0), 1000
  check 'a note with no length plays until stopped', on_ and still and ended,
    "on=#{on_} still=#{still} ended=#{ended}"

  # 6d. and can be changed while it plays
  await run "held = sound 330\n"
  await until_ -> (await peak()) > 0.05
  await ask 'held.volume = 0'
  hushed = await until_ -> (await peak()) is 0 and (await busy()) is 1
  await ask "held.volume = 1; held.frequency = 'E5'"
  loud = await until_ -> (await peak()) > 0.05
  check 'a playing note can be changed', hushed and loud, "hushed=#{hushed} loud=#{loud}"

  # 6e. a stop can fade
  await ask 'held.stop 0.4'
  await wait 150
  fading = (await busy()) is 1
  gone = await until_ (-> (await busy()) is 0), 1500
  check 'a stop with a fade takes that long', fading and gone, "fading=#{fading} gone=#{gone}"

  # 6f. a voice can be stopped, queue and all, and so can everything
  before = await started()
  await run "sound 220, voice: 'a'\nsound 440, 1, voice: 'a'\nsound 330, voice: 'b'\n"
  await until_ -> (await busy()) is 2
  await ask "sound.stop 'a'"
  one = await until_ -> (await busy()) is 1
  await wait 150
  noQueue = (await busy()) is 1 and (await started()) is before + 2
  await ask 'sound.stop()'
  none = await until_ -> (await busy()) is 0
  check 'sound.stop takes a voice with its queue, or everything', one and noQueue and none,
    "one=#{one} queueDropped=#{noQueue} none=#{none} started=#{(await started()) - before}"

  # 6g. a note stopped before its turn never plays
  before = await started()
  await run "a = sound 440, 0.2\nb = sound 550, 0.2\nb.stop()\n"
  await until_ -> (await started()) > before
  await wait 450
  check 'a queued note that is stopped never starts', (await started()) is before + 1,
    "started #{(await started()) - before}"

  # 7. Stop silences at once, not when the note would have ended
  await setDoc "sound 220, 10\nloop\n  buffer.swap\n"
  await wait 400
  await evalAll()
  await until_ -> (await busy()) is 1
  await click 'stop'
  quiet = await until_ (-> (await busy()) is 0 and (await peak()) is 0), 1000
  check 'stop silences a long note at once', quiet, "busy=#{await busy()} peak=#{await peak()}"
  await t.settle()

  # 7b. a note that outlives its sketch is silenced by Stop, and Stop with
  # nothing running leaves the prompt working
  text = await run "sound 262, voice: 'drone'\nprint 'finished'\n"
  # The button lights for a sounding voice on the console's next tick, and a
  # click on it while it is still gray does nothing.
  lingering = await until_ -> (await busy()) is 1 and not await js "return document.getElementById('stop').disabled"
  await click 'stop'
  hushed = await until_ -> (await busy()) is 0
  asked = await ask '6 * 7'
  check 'stop silences a note that outlived its sketch',
    text.includes('finished') and lingering and hushed and asked.includes('42'),
    "lingering=#{lingering} hushed=#{hushed} asked=#{JSON.stringify asked.trim()}"

  # 8. and a note typed at the prompt after a Stop still plays
  before = await started()
  await ask 'sound 330, 0.1'
  typed = await until_ -> (await started()) > before
  check 'the prompt can play a note after a stop', typed

  # 9. a pause holds the sound with the picture, and continue lets it go
  await setDoc "screen 320, 200\nbuffer.on\nsound 220, 10\nloop\n  buffer.swap\n"
  await wait 400
  await evalAll()
  await until_ -> (await peak()) > 0.05
  await t.pause()
  held = await until_ -> (await peak()) is 0
  await wait 100
  still = (await busy()) is 1 and (await peak()) is 0
  await t.go()
  back = await until_ -> (await peak()) > 0.05
  check 'a pause holds the note, continue plays it on', held and still and back,
    "held=#{held} still=#{still} back=#{back}"

  # 10. a fresh run drops whatever the last one queued
  await setDoc "print 'fresh'\n"
  await wait 400
  await click 'runFresh'
  await t.settle()
  gone = await until_ (-> (await busy()) is 0), 1000
  check 'run starts in silence', gone, "busy=#{await busy()}"

  # 11. Run over a sketch that keeps queueing notes. The new worker's epoch
  # drops what was queued, but the old worker went on for two seconds after
  # terminate() (Chromium only forces a busy worker then), and every note it
  # queued in that time played over the new run.
  await setDoc """
screen 320, 200
buffer.fps 20
loop
  sound 440, 0.04
  buffer.swap
"""
  await wait 400
  await evalAll()
  playing = await until_ (-> (await busy()) > 0), 3000
  await setDoc "print 'quiet'\n"
  await wait 400
  await click 'runFresh'
  hushed = await until_ (-> (await busy()) is 0 and (await peak()) is 0), 1000
  begun  = await started()
  await wait 600
  after  = await started()
  check 'run over a sketch queueing notes: nothing it queues afterwards plays',
    playing and hushed and after is begun and (await busy()) is 0,
    "playing=#{playing} hushed=#{hushed} started #{begun} then #{after} busy=#{await busy()}"
  await t.settle()
