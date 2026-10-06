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

  # 3b. A run asked for straight after a Stop arms the debugger first -- the
  # Stop set breakpoints aside -- and Stop is live for that too. Read in the
  # same turn as the click, as in 2, but here the word is known.
  armed = await js """
    const b = document.getElementById('stop')
    document.getElementById('runFresh').click()
    return { status: document.getElementById('status').textContent, disabled: b.disabled }
  """
  check 'Stop is live while a run waits on arming the debugger',
    armed.status is 'arming' and not armed.disabled, JSON.stringify armed
  await becomes 'running'
  await click 'stop'
  await settle()

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
  try
    await load "screen 320, 200\nball = null\nball.x\n"
    await t.evalAll()
    held   = await becomes 'error paused', 10000
    paused = await stopState()
    await click 'stop'
    ended = await becomes 'error'
  finally
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

  # What the prompt answers once a Stop has gone through: a line with a yield
  # point in it, so a flag the Stop left raised answers 'stopped' instead.
  answers = -> t.ask 'buffer.swap; 7'
  answered = (text) -> /7$/.test(text) and not /stopped/.test text

  # 10. A runaway prompt line at an idle worker: Stop is live for it, and
  # ends it at its next yield point. Once it has answered, the prompt works.
  # A line with no yield point (`loop then 0`) cannot be ended this way, and
  # is not checked.
  await js "Prompt.ask('buffer.swap while true'); return true"
  out    = await t.waitFor "return Prompt.pending()"
  lit    = await live()
  idle   = await status()
  await click 'stop'
  back   = await t.waitFor "return !Prompt.pending()"
  unless back                          # still spinning: only a new worker ends it
    await click 'runFresh'
    await settle()
  await t.quiet()                      # its 'stopped' is printed, not counted below
  after  = await answers()
  check 'Stop ends a runaway prompt line at an idle worker, and the prompt works after',
    out and lit and idle is 'ready' and back and answered(after),
    JSON.stringify {out, lit, idle, back, after}

  # 11. Stop while the worker boots for a run drops the run, and there is
  # nothing else on that worker to unwind -- so nothing is left raised for
  # the prompt to trip on once it is ready. Both clicks in one turn, so the
  # Stop lands on `booting`.
  await t.clearConsole()
  await load "screen 320, 200\nprint 'never'\n"
  booting = await js """
    document.getElementById('runFresh').click()
    const status = document.getElementById('status').textContent
    document.getElementById('stop').click()
    return status
  """
  ready = await becomes 'ready', 10000
  after = await answers()
  check 'Stop while booting drops the run and leaves the prompt working',
    booting is 'booting' and ready and answered(after) and not /never/.test(await t.consoleText()),
    JSON.stringify {booting, ready, after}

  # 12. The hold button at an idle worker frame-pauses nothing, and Stop from
  # there puts the status back to ready -- which is idle too.
  await click 'pauseFrame'
  held  = await status()
  lit   = await stopState()
  await click 'stop'
  idle  = await status()
  after = await answers()
  check 'Stop after a hold at an idle worker leaves the prompt working',
    held is 'frame paused' and isLive(lit) and idle is 'ready' and answered(after),
    JSON.stringify {held, lit, idle, after}

  # 13. A worker booting with no run asked for leaves Stop gray. The app's
  # first boot is one, but a page's first boot is over before anything here
  # can look at it; the restart after a sketch with no yield point is the
  # same start() with nothing pending, and can be watched. The status line is
  # observed rather than polled: a boot can be shorter than a poll, and the
  # observer sees the button as setStatus left it.
  await load "n = 0\nloop then n += 1\n"
  await t.evalAll()
  await becomes 'running'
  await js """
    window.stopSeen = []
    window.stopWatch = new MutationObserver(() => window.stopSeen.push([
      document.getElementById('status').textContent,
      document.getElementById('stop').disabled]))
    window.stopWatch.observe(document.getElementById('status'), { childList: true, characterData: true, subtree: true })
    return true
  """
  await click 'stop'
  ready = await becomes 'ready', 10000
  seen  = await js "window.stopWatch.disconnect(); return window.stopSeen"
  booted = (state for state in seen when state[0] is 'booting')
  check 'Stop is gray while a worker boots with no run asked for',
    ready and booted.length > 0 and booted.every((state) -> state[1]),
    JSON.stringify seen

  # 14. A sketch that ends under a hold, which ends the hold too. Ctrl-. from
  # there (the button is gray) has an idle worker to deal with: a hold left
  # in place, let go first, would read 'running', and 250ms later shoot the
  # worker for having no yield point, its image with it.
  await t.clearConsole()
  await load "screen 320, 200\nkept = 42\nends = Date.now() + 1000\nnull while Date.now() < ends\nprint 'over'\n"
  await t.evalAll()
  await becomes 'running'
  await click 'pauseFrame'
  held  = await status()
  ended = await becomes 'ready', 10000
  await js """
    const stage = document.getElementById('stage')
    stage.focus()
    stage.dispatchEvent(new KeyboardEvent('keydown', { key: '.', code: 'Period', ctrlKey: true, bubbles: true, cancelable: true }))
    return true
  """
  shot = await t.waitFor "return /terminated/.test(document.getElementById('console').textContent)", 1500
  kept = await t.ask 'kept'
  check 'Stop after a sketch ended under a hold keeps the image',
    held is 'frame paused' and ended and not shot and /42$/.test(kept),
    JSON.stringify {held, ended, shot, kept}

  # 15. A hold pressed while the worker boots holds the run it boots for, at
  # its first frame, and says so. Until 2026-10-06 'ready', and the run it
  # sends, wrote over the hold: the sketch read 'running' held at its first
  # frame with `resumeTo` still 'booting' (23 checks that). Stop from there
  # ends it. The first Run is only there so the second neither arms nor finds
  # a hold. 19 is the same with a sketch that catches its stop.
  await t.clearConsole()
  await load "screen 320, 200\nprint 'warm'\nloop\n  buffer.swap\n"
  await click 'runFresh'
  await becomes 'running'
  await t.waitFor "return /warm/.test(document.getElementById('console').textContent)"
  await t.clearConsole()             # so the 'warm' waited for below is the second run's
  boot = await js """
    document.getElementById('runFresh').click()
    const before = document.getElementById('status').textContent
    document.getElementById('pauseFrame').click()
    return [before, document.getElementById('status').textContent]
  """
  warm    = await t.waitFor "return /warm/.test(document.getElementById('console').textContent)", 10000
  held    = await status()
  await click 'stop'
  ended   = await becomes 'ready', 10000
  check 'Stop ends a sketch held from its boot',
    boot[0] is 'booting' and boot[1] is 'frame paused' and warm and held is 'frame paused' and ended,
    JSON.stringify {boot, warm, held, ended, status: await status()}

  # 16. Stop while a run waits on arming the debugger cancels that run: it is
  # not a run yet, and once armed nothing would stop it going ahead. 15's
  # Stop set breakpoints aside, so this Run arms first. Nothing runs under
  # it, so the prompt works after, too. The run going ahead would show as
  # the status leaving ready.
  await t.clearConsole()
  await load "screen 320, 200\nprint 'armed and ran'\n"
  arming = await js """
    document.getElementById('runFresh').click()
    const status = document.getElementById('status').textContent
    document.getElementById('stop').click()
    return status
  """
  ran   = await t.waitFor "return document.getElementById('status').textContent !== 'ready'", 1500
  after = await answers()
  check 'Stop at arming cancels the run, and leaves the prompt working',
    arming is 'arming' and not ran and answered(after) and not /armed and ran/.test(await t.consoleText()),
    JSON.stringify {arming, ran, after, status: await status()}

  # 17. A prompt line asked while the worker boots waits, unclaimed, to be
  # served once it is ready. Stop at booting takes it back, says so, and the
  # line never runs. What it would print is not in its echo.
  await t.clearConsole()
  await load LOOPS
  booting = await js """
    document.getElementById('runFresh').click()
    const status = document.getElementById('status').textContent
    Prompt.ask("print ['took', 'it'].join '-'; buffer.swap while true")
    document.getElementById('stop').click()
    return status
  """
  ready = await becomes 'ready', 10000
  after = await answers()
  text  = await t.consoleText()
  check 'Stop at booting takes back a prompt line not yet claimed, which never runs',
    booting is 'booting' and ready and answered(after) and /\*\*\* stopped \*\*\*/.test(text) and not /took-it/.test(text),
    JSON.stringify {booting, ready, after, text}

  # What `n` reads at the prompt once it has passed `from`, or where it was
  # when the time ran out. The sketch below counts its frames in it.
  COUNTS  = "screen 320, 200\nn = 0\nloop\n  n += 1\n  buffer.swap\n"
  reads   = -> Number (await t.ask 'n').match(/(\d+)\s*$/)?[1]
  counted = (from) ->
    deadline = Date.now() + 3000
    loop
      seen = await reads()
      return seen if seen > from or Date.now() > deadline
  typed = (text) -> """
    const v = Editor.view()
    v.dispatch({ changes: { from: 0, to: v.state.doc.length, insert: #{JSON.stringify text} } })
  """
  saw = (pattern, limit) -> t.waitFor "return #{pattern}.test(document.getElementById('console').textContent)", limit

  # 18. A sketch that ends under a hold, without reaching a swap, ends the
  # hold with it. Left in place, the hold froze the next run at its first
  # frame under a status that said 'running'.
  await load "screen 320, 200\nends = Date.now() + 1000\nnull while Date.now() < ends\n"
  await t.evalAll()
  await becomes 'running'
  await click 'pauseFrame'
  held    = await status()
  ended   = await becomes 'ready', 10000
  holding = await js "return Stepping.paused()"
  await load COUNTS
  await t.evalAll()
  running = await becomes 'running'
  n       = await counted 1
  await click 'stop'
  await settle()
  check 'a hold ends with the sketch it held, and the next run is not held',
    held is 'frame paused' and ended and not holding and running and n > 1,
    JSON.stringify {held, ended, holding, running, n}

  # 19. 15 again, with a sketch that catches its stop, so only the 250ms
  # deadline ends it. The deadline waits on 'running'; Stop let the hold go
  # as the 'booting' it remembered, the deadline gave up at once, and the
  # worker spun on with the status reading booting and Stop gray. The hold
  # remembers 'running' for its run now (runState), and Stop lets it go as
  # 'running' whatever it remembers.
  await t.clearConsole()
  await load "screen 320, 200\nprint 'warm'\nspins = 0\nloop\n  try\n    buffer.swap\n  catch e\n    spins += 1\n"
  await click 'runFresh'
  await becomes 'running'
  await saw '/warm/'
  await t.clearConsole()
  boot = await js """
    document.getElementById('runFresh').click()
    const before = document.getElementById('status').textContent
    document.getElementById('pauseFrame').click()
    return [before, document.getElementById('status').textContent]
  """
  warm  = await saw '/warm/', 10000
  held  = await status()
  await click 'stop'
  ended = await becomes 'ready', 10000
  shot  = await saw '/no yield point/'
  check 'Stop ends a sketch held from its boot that catches its stop',
    boot[0] is 'booting' and boot[1] is 'frame paused' and warm and held is 'frame paused' and ended and shot,
    JSON.stringify {boot, warm, held, ended, shot, status: await status()}

  # 20. Two evals in one tick over a running sketch, `breakpoint` new in the
  # buffer, so the first arms. The second meets the arming and must still
  # find the worker busy: sent, it sat in the worker's inbox and ran the
  # moment the Stop below ended the first sketch, under a status of 'ready'.
  await t.clearConsole()
  await load LOOPS
  await t.evalAll()
  await becomes 'running'
  first = await js """
    #{typed "screen 320, 200\nprint 'second ran'\nloop\n  buffer.swap\n# breakpoint\n"}
    Editor.command('/eval')
    const status = document.getElementById('status').textContent
    Editor.command('/eval')
    return status
  """
  refused = await saw '/already running/'
  await click 'stop'
  await settle()
  ran = await saw '/second ran/', 1500
  check 'a run asked while another is armed over a busy worker is refused, not queued',
    first is 'arming' and refused and not ran and (await status()) is 'ready',
    JSON.stringify {first, refused, ran, status: await status()}

  # 21. A run being armed, cancelled by a Stop, and another asked for while
  # the first is still arming. The first leaves the status to the second:
  # putting back its own 'running' over the idle worker, it made the
  # second's run refused as already running. A real arming takes about 4ms,
  # so the suite's hook in main stretches each one for this check, and the
  # second eval must come while the first is still arming.
  STRETCH = 1000
  await t.clearConsole()
  await load LOOPS
  await t.evalAll()
  await becomes 'running'
  t.debugHooks.arming = -> wait STRETCH
  try
    cancelled = await js """
      #{typed "screen 320, 200\nprint 'third ran'\nloop\n  buffer.swap\n# breakpoint\n"}
      const at = performance.now()
      document.getElementById('runFresh').click()
      const status = document.getElementById('status').textContent
      document.getElementById('stop').click()
      return { at, status }
    """
    stopped = await becomes 'ready'
    again   = await js """
      const at = performance.now()
      Editor.command('/eval')
      return { at, status: document.getElementById('status').textContent }
    """
    ran = await saw '/third ran/', 3 * STRETCH
  finally
    t.debugHooks.arming = null
  inside = again.at - cancelled.at < STRETCH
  text   = await t.consoleText()
  check 'a cancelled arming leaves the status to the arming after it, whose run goes ahead',
    cancelled.status is 'arming' and stopped and again.status is 'arming' and inside and ran and
      (await status()) is 'running' and not /already running/.test(text),
    JSON.stringify {cancelled, stopped, again, inside, ran, status: await status(), text}
  await click 'stop'
  await settle()

  # 22. A hold pressed while a run is armed over a running sketch holds the
  # sketch, and letting it go puts it back to running. Remembering 'arming',
  # letting go left the status there for good. The run is refused once
  # armed, as it would be at any hold. Pressed in the same turn as the eval,
  # so no stretch is needed.
  await t.clearConsole()
  await load COUNTS
  await t.evalAll()
  await becomes 'running'
  pressed = await js """
    #{typed COUNTS + "# breakpoint\n"}
    Editor.command('/eval')
    const before = document.getElementById('status').textContent
    document.getElementById('pauseFrame').click()
    return [before, document.getElementById('status').textContent]
  """
  refused = await saw '/already running/'
  held    = await status()
  from    = await reads()
  await click 'pauseFrame'
  going   = await becomes 'running'
  n       = await counted from
  await click 'stop'
  ended   = await becomes 'ready'
  check 'a hold pressed while a run is armed is let go to running',
    pressed[0] is 'arming' and pressed[1] is 'frame paused' and refused and held is 'frame paused' and going and n > from and ended,
    JSON.stringify {pressed, refused, held, going, from, n, ended}

  # 23. A hold pressed while the worker boots, for the run it boots for. The
  # 'ready' that ends the boot and the run it sends wrote their status over
  # the hold: the sketch sat at its first frame under 'running', and the
  # hold button, which reads the status, held again rather than let go --
  # nothing moved (found by a Claude review of main at 404fb07). The first
  # Run is only there so the second neither arms nor finds a hold.
  WARMS = "screen 320, 200\nn = 0\nprint 'warm'\nloop\n  n += 1\n  buffer.swap\n"
  await t.clearConsole()
  await load WARMS
  await click 'runFresh'
  await becomes 'running'
  await saw '/warm/'
  await t.clearConsole()
  boot = await js """
    document.getElementById('runFresh').click()
    const before = document.getElementById('status').textContent
    document.getElementById('pauseFrame').click()
    return [before, document.getElementById('status').textContent]
  """
  warm  = await saw '/warm/', 10000
  held  = await status()
  first = await reads()
  await click 'pauseFrame'
  going = await becomes 'running'
  n     = await counted first
  await click 'stop'
  ended = await becomes 'ready'
  check 'a hold pressed while the worker boots reads as a hold once its run starts, and one press lets it go',
    boot[0] is 'booting' and boot[1] is 'frame paused' and warm and held is 'frame paused' and first is 1 and
      going and n > first and ended,
    JSON.stringify {boot, warm, held, first, going, n, ended}

  # 24. The same at an idle worker: a hold taken at 'ready' holds the next
  # run. An Eval asked whether the worker was busy of the status line, which
  # said 'frame paused', and was refused as already running.
  await t.clearConsole()
  await load WARMS
  await click 'pauseFrame'
  idle  = await status()
  await t.evalAll()
  warm  = await saw '/warm/', 10000
  held  = await status()
  first = await reads()
  await click 'pauseFrame'
  going = await becomes 'running'
  n     = await counted first
  text  = await t.consoleText()
  await click 'stop'
  ended = await becomes 'ready'
  check 'an Eval after a hold at an idle worker runs, held at its first frame, and one press lets it go',
    idle is 'frame paused' and warm and held is 'frame paused' and first is 1 and going and n > first and ended and
      not /already running/.test(text),
    JSON.stringify {idle, warm, held, first, going, n, ended, text}

  # 25. The status line is as wide as its widest word, so the header does not
  # shift as it changes -- in whatever monospace font the platform gives it.
  # In this machine's, 6rem held `error paused` with 2px to spare (measured
  # by Claude, 2026-10-06), so the check stands in a wider font by setting a
  # larger size on the line alone, which a width in rem does not follow.
  # Each word is measured in place and the line put back in the same turn,
  # before anything can draw it.
  widths = await js """
    const line = document.getElementById('status')
    const was  = line.textContent
    const seen = {}
    for (const size of ['', '20px']) {
      line.style.fontSize = size
      for (const word of ['ready', 'booting', 'arming', 'running', 'error', 'frame paused', 'line paused', 'error paused']) {
        line.textContent = word
        seen[`${word} ${size || 'as set'}`] = line.getBoundingClientRect().width
      }
    }
    line.style.fontSize = ''
    line.textContent = was
    return seen
  """
  sizes = (size) -> new Set(width for name, width of widths when name.endsWith size).size
  check 'the status line is as wide for every word it shows, in a wider font too, so the header does not shift',
    sizes('as set') is 1 and sizes('20px') is 1, JSON.stringify widths
