# The Stop button: gray when there is nothing for it to end, live otherwise
# (Robert, 2026-10-05). "Nothing to end" is not "no sketch running": a note
# with no length outlives its sketch and Stop is how it is hushed, and a
# prompt line can still be out at an idle worker. Each live state is checked
# with the gray on one side of it, so a button that never grays fails here.
#
# Polled, never slept: the status grays and lights it at once, but a voice or
# a prompt line is only seen on the console's next tick.

module.exports = (t) ->
  {wait, check, setDoc, js, status, settle, click} = t

  stopState = -> js """
    const b = document.getElementById('stop')
    return { disabled: b.disabled, title: b.title }
  """
  isGray = (state) -> state.disabled and state.title.startsWith 'Nothing to stop'
  isLive = (state) -> not state.disabled and state.title.includes 'Ctrl-.'
  gray   = -> t.waitFor "const b = document.getElementById('stop'); return b.disabled && b.title.startsWith('Nothing to stop')"
  live   = -> t.waitFor "const b = document.getElementById('stop'); return !b.disabled && b.title.includes('Ctrl-.')"
  becomes = (wanted, limit) -> t.waitFor "return document.getElementById('status').textContent === #{JSON.stringify wanted}", limit

  load = (source) ->
    await setDoc source
    await wait 500                     # past the autosave debounce, as every part does

  LOOPS = "screen 320, 200\nloop\n  buffer.swap\n"

  # 1. Ready, silent, nothing asked: gray, and the title says why.
  rested = await gray()
  check 'Stop is gray when nothing is running, and its title says why',
    rested and (await status()) is 'ready', JSON.stringify {status: await status(), stop: await stopState()}

  # 2. A run lights it from the moment it is asked for -- before the worker
  # has booted -- and keeps it lit while it runs. Read in the same turn as
  # the click, so the boot is seen whichever word it goes by.
  await load LOOPS
  boot = await js """
    const b = document.getElementById('stop')
    const before = b.disabled
    document.getElementById('runFresh').click()
    return { before, status: document.getElementById('status').textContent, disabled: b.disabled }
  """
  running = await becomes 'running'
  during  = await stopState()
  check 'Stop goes live as a run is asked for, and stays live while it runs',
    boot.before and boot.status in ['arming', 'booting'] and not boot.disabled and running and isLive(during),
    JSON.stringify {boot, during}

  # 3. Stopped, it grays again at once: the status says so in the same turn.
  await click 'stop'
  await settle()
  after = await stopState()
  check 'Stop is gray again once the sketch has stopped',
    (await status()) is 'ready' and isGray(after), JSON.stringify after

  # 4. A frame pause: the sketch is parked on a swap, and Stop ends it.
  await load LOOPS
  await t.evalAll()
  await becomes 'running'
  await t.pause()
  held   = await becomes 'frame paused'
  paused = await stopState()
  await click 'stop'
  await settle()
  check 'Stop is live at a frame pause, and ends it',
    held and isLive(paused) and (await status()) is 'ready' and isGray(await stopState()),
    JSON.stringify {held, paused, after: await stopState(), status: await status()}

  # 5. A line pause: stopped in V8 on the author's line.
  await load "screen 320, 200\nbreakpoint\nloop\n  buffer.swap\n"
  await t.evalAll()
  held   = await becomes 'line paused', 10000
  paused = await stopState()
  await click 'stop'
  # Not settle(): a line pause counts as settled, and Stop lets the sketch go
  # only once main has answered.
  ended = await becomes 'ready'
  check 'Stop is live at a line pause, and ends it',
    held and isLive(paused) and ended and isGray(await stopState()),
    JSON.stringify {held, ended, paused, after: await stopState(), status: await status()}

  # 6. An error pause. Error stops are off in every part but pauseonerror
  # (t.reset); this check is about the button at one, so it turns them on
  # for itself alone.
  await t.stopOnErrors yes
  await load "screen 320, 200\nball = null\nball.x\n"
  await t.evalAll()
  held   = await becomes 'error paused', 10000
  paused = await stopState()
  await click 'stop'
  ended = await becomes 'error'
  await t.stopOnErrors no
  check 'Stop is live at an error pause, and gray once the run has ended as the error',
    held and isLive(paused) and ended and isGray(await stopState()),
    JSON.stringify {held, ended, paused, after: await stopState(), status: await status()}

  # 7. A note with no length, sounding after its sketch has finished. The
  # status says ready; only the audio thread knows better.
  await load "sound 262, voice: 'drone'\nprint 'finished'\n"
  await t.evalAll()
  await settle()
  sounding = await t.waitFor "return Sound.busy() === 1"
  lit      = await live()
  idle     = await status()
  await click 'stop'
  hushed = await t.waitFor "return Sound.busy() === 0"
  grayed = await gray()
  check 'Stop is live while a note outlives its sketch, and gray once it is hushed',
    sounding and idle is 'ready' and lit and hushed and grayed,
    JSON.stringify {sounding, idle, lit, hushed, stop: await stopState()}

  # 8. A prompt line still out at an idle worker. It waits on a key the check
  # holds, with no yield point, so it is out until the check lets it go.
  await js "Prompt.ask(\"null until keys.down 'space'\"); return true"
  out   = await t.waitFor "return Prompt.pending()"
  lit   = await live()
  idle  = await status()
  await t.key 'keydown', 'Space'
  back  = await t.waitFor "return !Prompt.pending()"
  await t.key 'keyup', 'Space'
  grayed = await gray()
  check 'Stop is live while a prompt line is out, and gray once it is answered',
    out and idle is 'ready' and lit and back and grayed,
    JSON.stringify {out, idle, lit, back, stop: await stopState()}

  # 9. Ctrl-. reaches stop with the button gray: a note queued but not yet
  # begun is not sounding, so the button cannot be what decides. With
  # nothing to end, a stop only drops whatever is queued, which is the
  # epoch going up.
  await gray()
  before = await js "return Sound.epoch()"
  state  = await stopState()
  await js """
    const stage = document.getElementById('stage')
    stage.focus()
    stage.dispatchEvent(new KeyboardEvent('keydown', { key: '.', code: 'Period', ctrlKey: true, bubbles: true, cancelable: true }))
    return true
  """
  after = await js "return Sound.epoch()"
  check 'Ctrl-. still stops while the button is gray',
    isGray(state) and after is before + 1, "epoch #{before} -> #{after} stop=#{JSON.stringify state}"
