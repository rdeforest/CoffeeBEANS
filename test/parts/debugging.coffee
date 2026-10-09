# Line stepping. The debugger lives in the main process and drives the worker
# over the inspector protocol, so these checks go through the real thing: it
# is armed for every run, and every pause is a V8 pause.
#
# Waits are on the app, never the clock. A pause arrives when V8 says so, and
# each one is numbered, so "a new pause" is a number going up rather than a
# status line that might still be showing the last one.

module.exports = (t) ->
  {wait, check, setDoc, evalAll, consoleText, clearConsole, js,
   status, settle, settled, ask, click} = t

  # Polled, like everything in this suite.
  until_ = (probe, limit = 10000) ->
    deadline = Date.now() + limit
    loop
      value = await probe()
      return value if value
      return null if Date.now() > deadline
      await wait 25

  pauseNumber = -> js "return Stepping.linePaused()"
  pausedText  = -> js "return (document.querySelector('.cm-paused-line') || {}).textContent ?? null"
  paneText    = -> js "const v = document.getElementById('vars'); return v.hidden ? null : v.textContent"
  paneValue   = (name) -> js """
    for (const row of document.querySelectorAll('#vars .var')) {
      const n = row.querySelector('.var-name')
      if (n && n.textContent === #{JSON.stringify name}) return row.querySelector('.var-value').textContent
    }
    return null
  """

  # The next pause after `since`, and the line it shows.
  nextPause = (since, limit) ->
    seq = await until_ (-> n = await pauseNumber(); n if n and n > since), limit
    await until_ paneText              # the pane fills after the status does
    seq

  addAngle = """
screen 320, 200
total = 0
addAngle = (a, b) ->
  breakpoint
  sum = a + b
  sum
for i in [1..3]
  total = addAngle total, i
print 'total=' + total
"""

  # 1. `breakpoint` stops in the author's code, not inside our getter: on the
  # line after it, which is the line about to run -- what the highlight means
  # everywhere else too.
  await setDoc addAngle
  await wait 500
  await clearConsole()
  await evalAll()
  first = await nextPause 0
  check 'breakpoint pauses in the author\'s code, before the next line',
    first and (await status()) is 'line paused' and (await pausedText())?.trim() is 'sum = a + b',
    "seq=#{first} status=#{await status()} line=#{JSON.stringify await pausedText()}"

  # 2. the pane holds that call's parameters and the sketch's own names --
  # and none of the wrapper's plumbing
  pane = await paneText()
  check 'the pane shows the frame\'s locals and the sketch\'s names',
    (await paneValue 'a') is '0' and (await paneValue 'b') is '1' and
      (await paneValue 'total') is '0' and pane.includes('addAngle') and not pane.includes('__'),
    JSON.stringify pane

  # 3. the prompt answers against the paused frame, and can change it
  answer = await ask 'a + b + 100'
  check 'the prompt answers against the paused frame', answer.includes('101'), JSON.stringify answer
  await ask 'b = 10'
  await ask 'total = 0'
  check 'an assignment at the prompt reaches the frame, and the pane says so',
    (await paneValue 'b') is '10' and (await paneValue 'total') is '0',
    "b=#{await paneValue 'b'} total=#{await paneValue 'total'}"

  # 4. a line step goes to the next line that runs, and out to the caller
  await js "Stepping.line(); return true"
  second = await nextPause first
  stepped = (await pausedText())?.trim()
  sum     = await paneValue 'sum'
  await js "Stepping.line(); return true"
  third = await nextPause second
  check 'a line step moves one line at a time, and back out to the caller',
    stepped is 'sum' and sum is '10' and (await pausedText())?.trim() is 'for i in [1..3]',
    "#{JSON.stringify stepped} sum=#{sum} then #{JSON.stringify await pausedText()}"

  # 5. continue runs to the next breakpoint -- the next call
  await js "Stepping.resume(); return true"
  fourth = await nextPause third
  check 'continue runs on to the breakpoint in the next call',
    (await paneValue 'a') is '10' and (await paneValue 'b') is '2',
    "a=#{await paneValue 'a'} b=#{await paneValue 'b'}"

  # 6. Stop while line paused must not shoot the worker: it is let go, runs to
  # its end or its next yield point, and the image survives
  await clearConsole()
  await click 'stop'
  idle = await until_ -> s = await status(); s if s is 'ready'
  await t.quiet()
  said = await consoleText()
  kept = await ask 'total'
  check 'stop at a breakpoint keeps the image and blames nothing',
    idle is 'ready' and not said.includes('no yield point') and /\d/.test(kept) and
      (await paneText()) is null and (await pausedText()) is null,
    "status=#{idle} said=#{JSON.stringify said.trim()} total=#{JSON.stringify kept.trim()}"

  # 7. the prompt did not wedge: the worker serves it again
  check 'the prompt works again once the pause is over', (await ask '6 * 7').includes('42')

  # 8. suspend a running sketch that has no breakpoint at all
  await setDoc """
screen 320, 200
buffer.on
n = 0
loop
  n += 1
  buffer.swap
"""
  await wait 500
  await evalAll()
  await until_ -> (await status()) is 'running'
  await wait 200
  base = (await pauseNumber()) ? 0
  await js "Stepping.suspend(); return true"
  got  = await nextPause base
  line = (await pausedText())?.trim()
  check 'suspend stops a running sketch on one of its own lines',
    got and line in ['loop', 'n += 1', 'buffer.swap'] and /^\d+$/.test(await paneValue 'n'),
    "line=#{JSON.stringify line} n=#{await paneValue 'n'} pane=#{JSON.stringify await paneText()}"

  # 9. from a line pause, a frame step runs on to the next frame and holds
  await js "Stepping.step(); return true"
  held = await until_ -> (await status()) is 'frame paused'
  check 'a frame step from a line pause holds at the next frame',
    held and (await paneText()) is null, "status=#{await status()}"

  # 10. and from a frame pause, a line step finds the next line
  before = (await pauseNumber()) ? got
  await js "Stepping.line(); return true"
  again = await nextPause got
  check 'a line step from a frame pause stops on a line', again and (await status()) is 'line paused',
    "status=#{await status()}"

  # 11. continue from a line pause runs freely again
  await js "Stepping.resume(); return true"
  await until_ -> (await status()) is 'running'
  n1 = await ask 'n'
  await wait 300
  n2 = await ask 'n'
  num = (text) -> Number /(\d+)/.exec(text)?[1] ? -1
  check 'continue lets it run on', (await status()) is 'running' and num(n2) > num(n1),
    "#{JSON.stringify n1.trim()} -> #{JSON.stringify n2.trim()}"
  await click 'stop'
  await until_ -> (await status()) is 'ready'

  # 12. opening an object never runs its getters
  await setDoc """
screen 320, 200
o = {x: 1}
Object.defineProperty o, 'boom', enumerable: yes, get: -> print 'RAN'; 1
breakpoint
print 'after'
"""
  await wait 500
  await clearConsole()
  seen = (await pauseNumber()) ? 0
  await evalAll()
  await nextPause seen
  await js """
    for (const row of document.querySelectorAll('#vars .var.openable'))
      if (row.querySelector('.var-name').textContent === 'o') row.click()
    return true
  """
  boom = await until_ -> paneValue 'boom'
  await t.quiet()
  check 'opening an object shows a getter without running it',
    boom is '(getter, not run)' and (await paneValue 'x') is '1' and not (await consoleText()).includes('RAN'),
    "boom=#{JSON.stringify boom} console=#{JSON.stringify (await consoleText()).trim()}"

  # 13. Run while line paused throws the stopped worker away, and the fresh
  # one stops at the same breakpoint as a new pause
  before = await pauseNumber()
  await click 'runFresh'
  again = await nextPause before
  check 'run from a line pause starts a fresh worker that stops again',
    again and (await status()) is 'line paused' and (await pausedText())?.trim() is "print 'after'",
    "seq #{before} -> #{again} status=#{await status()} line=#{JSON.stringify await pausedText()}"
  await click 'stop'
  await until_ -> (await status()) is 'ready'

  # 14. The buffer has no say in arming. Since pausing on errors the
  # debugger is armed for every run whatever the buffer says (Robert,
  # 2026-10-05), so a `breakpoint` the buffer cannot see still stops, even
  # after a buffer that never said it at all. Until then this checked that
  # the buffer armed and disarmed it by itself; until 2026-10-08, when the
  # buffer's verdict was retired (Robert), it also read that verdict.
  await setDoc "print 'plain'\n"
  await wait 500
  await evalAll()
  plain = (await settled()).includes 'plain'
  await setDoc "w = 'break' + 'point'\nglobalThis[w]\nprint 'after'\n"
  await wait 500
  seen = (await pauseNumber()) ? 0
  await evalAll()
  hidden = await nextPause seen
  check 'with no breakpoint in the buffer the debugger is still armed: one spelled in pieces stops',
    plain and hidden and (await status()) is 'line paused' and (await pausedText())?.trim() is "print 'after'",
    "plain=#{plain} seq #{seen} -> #{hidden} status=#{await status()}"
  await click 'stop'
  await until_ -> (await status()) is 'ready'

  # 15. a region's line numbers are the buffer's: errors say where in the file
  await setDoc "a = 1\n\nboom = ->\n  throw new Error 'kaboom'\n\nboom()\n"
  await wait 500
  await clearConsole()
  await t.cursorOnLine 6
  await t.evalRegion()
  text = await settled()
  check 'a region reports buffer line numbers', text.includes('(line 6)'), JSON.stringify text.trim()

  # 16. An endless expression at the prompt, then a step. The step used to
  # reach V8 while it was still inside the evaluation and the renderer
  # segfaulted. It must wait its turn, and the evaluation must give up.
  await setDoc """
screen 320, 200
n = 0
breakpoint
print 'after'
"""
  await wait 500
  await clearConsole()
  await evalAll()
  start = await nextPause 0
  await js "Prompt.ask('n = 0; loop then n += 1'); return true"
  await until_ -> js "return Prompt.pending()"
  await js "Stepping.line(); return true"
  alive = await until_ (-> js("return Prompt.pending() === false").catch(-> null)), 15000
  await t.quiet()
  text  = await consoleText()
  check 'a step while the prompt is still evaluating waits, and the evaluation gives up',
    alive and (await status()) is 'line paused' and (await pauseNumber()) is start and
      text.includes('still evaluating') and text.includes('gave up'),
    "alive=#{alive} status=#{await status()} seq #{start} -> #{await pauseNumber()} console=#{JSON.stringify text.trim()}"
  # the loop's assignments reached the frame before it was cut off
  check 'the paused frame still answers after an evaluation gives up',
    (await ask 'n > 1000').includes('true'), JSON.stringify (await consoleText()).trim()

  # Stop cannot be refused, so it waits the evaluation out instead
  await js "Prompt.ask('loop then n += 1'); return true"
  await until_ -> js "return Prompt.pending()"
  await click 'stop'
  stoppedOk = await until_ (-> (await status()) is 'ready'), 15000
  check 'Stop during an endless evaluation still stops', stoppedOk, "status=#{await status()}"
  await until_ -> (await status()) is 'ready'

  # 17. A getter in the pane runs when clicked, once a click, and never
  # otherwise. `count` is the getter's own tally, read back at the prompt, so
  # a run nobody saw -- by expanding, by redrawing, by a click let through
  # late -- shows up as a number that went too far.
  await setDoc """
screen 320, 200
count = 0
spin = ->
  null while yes
  0
o = {x: 1}
Object.defineProperty o, 'tick',  enumerable: yes, get: -> count += 1
Object.defineProperty o, 'bad',   enumerable: yes, get: -> throw new Error 'nope'
Object.defineProperty o, 'stuck', enumerable: yes, get: spin
Object.defineProperty o, 'seen',  enumerable: yes, get: -> count
Object.defineProperty o, Symbol('foo'), enumerable: yes, get: -> count += 1
p = {y: 2}
breakpoint
print 'after'
done = 1
"""
  await wait 500
  await clearConsole()
  seen = (await pauseNumber()) ? 0
  await evalAll()
  getterPause = await nextPause seen
  clickRow = (name, times = 1) -> js """
    for (const row of document.querySelectorAll('#vars .var'))
      if (row.querySelector('.var-name')?.textContent === #{JSON.stringify name})
        for (let i = 0; i < #{times}; i++) row.click()
    return true
  """
  thrownRow = (name) -> js """
    for (const row of document.querySelectorAll('#vars .var'))
      if (row.querySelector('.var-name')?.textContent === #{JSON.stringify name})
        return row.querySelector('.var-value').classList.contains('thrown')
    return null
  """
  rowHas = (name, cls) -> js """
    for (const row of document.querySelectorAll('#vars .var'))
      if (row.querySelector('.var-name')?.textContent === #{JSON.stringify name})
        return row.classList.contains(#{JSON.stringify cls})
    return null
  """
  counted = -> ask "'count=' + count"
  # A value other than `was`, once the pane has been redrawn with one.
  becomes = (name, was, limit) -> until_ (-> v = await paneValue name; v if v? and v isnt was), limit

  # Opened by hand unless check 12 left it open: the pane remembers by path.
  await js """
    for (const row of document.querySelectorAll('#vars .var.openable:not(.open)'))
      if (row.querySelector('.var-name').textContent === 'o') row.click()
    return true
  """
  opened = await until_ -> paneValue 'tick'
  before = await counted()
  await becomes 'tick', null           # the prompt's answer redrew the pane
  await clickRow 'tick'
  ran = await becomes 'tick', '(getter, not run)'
  after = await counted()
  check 'a getter in the pane is not run by opening its object, and a click runs it once',
    opened is '(getter, not run)' and before.includes('count=0') and
      ran is '1' and after.includes('count=1'),
    "opened=#{JSON.stringify opened} before=#{JSON.stringify before.trim()} ran=#{JSON.stringify ran} after=#{JSON.stringify after.trim()}"

  # A symbol cannot be named in the expression that would run it.
  symbol = await paneValue 'Symbol(foo)'
  check 'a symbol-keyed getter is listed but not offered to run',
    symbol is '(getter, not run)' and (await rowHas 'Symbol(foo)', 'runnable') is false,
    "value=#{JSON.stringify symbol} runnable=#{await rowHas 'Symbol(foo)', 'runnable'}"

  # two clicks before the first has answered: the second is refused
  await becomes 'tick', null
  await clearConsole()
  await clickRow 'tick', 2
  twice = await becomes 'tick', '(getter, not run)'
  await t.quiet()
  said  = await consoleText()
  check 'a second click while the first is still running is refused',
    twice is '2' and said.includes('still evaluating') and (await counted()).includes('count=2'),
    "tick=#{JSON.stringify twice} console=#{JSON.stringify said.trim()}"

  # a click while the prompt is evaluating is refused, and not run afterwards
  await becomes 'tick', null
  await clearConsole()
  await js "Prompt.ask('null while yes'); return true"
  await until_ -> js "return Prompt.pending()"
  await clickRow 'tick'
  await until_ (-> js "return Prompt.pending() === false"), 15000
  await t.quiet()
  said = await consoleText()
  late = await counted()
  check 'a click while the prompt is evaluating is refused, not queued',
    said.includes('still evaluating') and said.includes('gave up') and late.includes('count=2') and
      (await pauseNumber()) is getterPause,
    "console=#{JSON.stringify said.trim()} then #{JSON.stringify late.trim()}"

  # a getter that throws reads as an error, in the pane's own row
  await becomes 'bad', null
  await clickRow 'bad'
  bad = await becomes 'bad', '(getter, not run)'
  check 'a getter that throws shows as an error',
    /^threw Error: nope/.test(bad) and (await thrownRow 'bad'),
    "bad=#{JSON.stringify bad} thrown=#{await thrownRow 'bad'}"

  # one that never returns is given up on, like the prompt, and the frame
  # survives it -- and redrawing the pane after it ran nothing else
  await becomes 'stuck', null
  await clearConsole()
  await clickRow 'stuck'
  await until_ -> js "return Prompt.pending()"
  await clickRow 'p'
  openedEarly = await rowHas 'p', 'open'
  await js "Prompt.ask('1 + 1'); return true"
  stuck = await becomes 'stuck', '(getter, not run)', 15000
  check 'a getter that never returns is given up on, and the pause goes on',
    /gave up/.test(stuck) and (await thrownRow 'stuck') and (await counted()).includes('count=2') and
      (await pauseNumber()) is getterPause,
    "stuck=#{JSON.stringify stuck} status=#{await status()}"

  # Listing an object's members is a request to V8 too, so it waits as well;
  # and the redraw the stuck getter brought must not open it after all.
  await t.quiet()
  said = await consoleText()
  check 'opening an object while a getter is still running is refused',
    openedEarly is false and (await rowHas 'p', 'open') is false and said.includes('still evaluating'),
    "early=#{openedEarly} now=#{await rowHas 'p', 'open'} console=#{JSON.stringify said.trim()}"
  # A line, too, and the refusal names what is out rather than blaming a
  # line at the prompt. Counted, because the click on `p` says the same: a
  # line let through late, after the getter gave up, would leave one refusal
  # and an answer.
  refusals = said.split('*** still evaluating in the paused frame ***').length - 1
  check 'a line while a getter is running is refused as an evaluation in the paused frame',
    refusals is 2 and not said.includes('last line') and not said.includes('at the prompt'),
    "refusals=#{refusals} console=#{JSON.stringify said.trim()}"

  # after a step, what a click got is not shown as if it were still true
  await becomes 'tick', null
  await clickRow 'tick'
  third = await becomes 'tick', '(getter, not run)'
  await js "Stepping.line(); return true"
  await nextPause getterPause
  await becomes 'tick', null
  check 'after a step a getter goes back to not run',
    third is '3' and (await paneValue 'tick') is '(getter, not run)' and (await counted()).includes('count=3'),
    "clicked=#{JSON.stringify third} now=#{JSON.stringify await paneValue 'tick'}"

  # nor after another getter ran, which may have changed what this one says
  await becomes 'seen', null
  await clickRow 'seen'
  seenRan = await becomes 'seen', '(getter, not run)'
  await clickRow 'tick'
  fourth = await becomes 'tick', '(getter, not run)'
  check 'running one getter puts every other back to not run',
    seenRan is '3' and fourth is '4' and (await paneValue 'seen') is '(getter, not run)',
    "seen=#{JSON.stringify seenRan} then tick=#{JSON.stringify fourth} seen=#{JSON.stringify await paneValue 'seen'}"

  await click 'stop'
  await until_ -> (await status()) is 'ready'

  # 18. Step waits for the pane's member listings. Held by the main process's
  # own handler, gated here, so the listing is out for as long as the check
  # says and no longer: `beans` is frozen in the page, and nothing in V8 can
  # make Runtime.getProperties slow. `_invokeHandlers` is Electron's private
  # table of ipcMain.handle handlers (a Map in Electron 44, checked by a
  # Claude fixer 2026-10-05); the real handlers go back in whatever happens.
  {ipcMain} = require 'electron'
  handlers  = ipcMain._invokeHandlers
  realList  = handlers.get 'debug:members'
  realStep  = handlers.get 'debug:step'
  order     = []
  release   = null
  gate      = new Promise (resolve) -> release = resolve
  swap = (channel, handler) ->
    ipcMain.removeHandler channel
    ipcMain.handle channel, handler
  try
    swap 'debug:members', (event, args...) ->
      await gate
      order.push 'listed'
      realList event, args...
    swap 'debug:step', (event, args...) ->
      order.push 'step'
      realStep event, args...
    await setDoc """
q = {z: 3}
breakpoint
print 'one'
print 'two'
"""
    await wait 500
    seen = (await pauseNumber()) ? 0
    await evalAll()
    listPause = await nextPause seen
    await clickRow 'q'
    listingOut = await js "return Prompt.pending()"
    await js "Stepping.line(); return true"
    # Long enough for a step that does not wait to reach main, which is
    # milliseconds; the order below is what the check reads, not this wait.
    early = await until_ (-> order.length > 0), 500
    release()
    stepped = await nextPause listPause
  finally
    release()
    swap 'debug:members', realList
    swap 'debug:step',    realStep
  # Every listing out when step was pressed is in before it goes. There may
  # be more than one: clickRow clicks every row named `q` (two, when a Claude
  # fixer ran it on 2026-10-05), and each re-opens after the step.
  stepAt = order.indexOf 'step'
  check 'a step waits for a member listing still out, then goes',
    listPause and listingOut and not early and stepAt > 0 and
      order[...stepAt].every((what) -> what is 'listed') and stepped > listPause,
    "paused=#{listPause} pending=#{listingOut} early=#{early} order=#{order.join()} stepped=#{stepped}"
  await click 'stop'
  await until_ -> (await status()) is 'ready'

  # 19. Run from a line pause leaves the old worker nothing to do. Chromium's
  # terminate() only forces a busy worker two seconds later, and terminating
  # lets a line-paused one go, so it used to run on: printing into the new
  # console and taking the new sketch's frames. `k` counts the new sketch's
  # swaps against the frames presented since it began, one for one when the
  # frames are all its own (AGENTS.md); a zombie halved it.
  await setDoc """
screen 320, 200
n = 0
breakpoint
print 'OLD ran on'
loop
  n += 1
  print 'OLD ' + n if n %% 30 is 0
  buffer.swap
"""
  await wait 500
  await clearConsole()
  await evalAll()
  await nextPause 0
  await setDoc """
screen 320, 200
f0 = frames
k  = 0
loop
  k += 1
  buffer.swap
"""
  await wait 500
  await click 'runFresh'
  await until_ -> (await status()) is 'running'
  shown = 0
  await until_ (-> shown = Number /(\d+)\s*$/.exec(await ask 'frames - f0')?[1]; shown >= 100), 15000
  [mine, presented] = (Number n for n in /(\d+) (\d+)"\s*$/.exec(await ask "k + ' ' + (frames - f0)")?[1..2] ? [])
  await t.quiet()
  said = await consoleText()
  check 'run from a line pause: the old worker prints nothing and takes no frames',
    not said.includes('OLD') and mine / presented > 0.8,
    "swaps #{mine} of #{presented} frames, console=#{JSON.stringify said.trim()[-300..]}"
  await click 'stop'
  await until_ -> (await status()) is 'ready'

  # 20. No name a sketch picks can hide the debugger's own. Setting a pause up
  # evaluates in the paused frame, and it used to name `globalThis` there: a
  # parameter of that name turned every pause into "could not pause", and a
  # top-level one, kept in the image, every later run's as well (a reviewer
  # of 5d16bc3, 2026-10-06). A fresh worker for each, so the first cannot
  # spoil the second.
  shadows =
    'a top-level globalThis':       "globalThis = {}\nbreakpoint\nprint 'after'"
    'a parameter named globalThis': "f = (globalThis) ->\n  breakpoint\n  print 'in f'\nf 1"
  for what, source of shadows
    await setDoc source
    await wait 500
    await clearConsole()
    await click 'runFresh'
    ended = await t.settle 10000
    await t.quiet()
    said = await consoleText()
    check "#{what} does not stop a breakpoint pausing",
      ended is 'line paused' and not said.includes('could not'),
      "status=#{ended} console=#{JSON.stringify said.trim()}"
    await click 'stop'
    await until_ -> (await status()) is 'ready'

  # 21. A Stop tells V8 to skip every pause until the next run, and the next
  # run has to know to take that back. A Stop waiting out an endless line at
  # the prompt only sets the skip once the line gives up, about 3s later; an
  # arm in that wait -- an Eval, a Run, and until 2026-10-08 an edit adding
  # or removing `breakpoint` -- found nothing skipped yet, the renderer then
  # believed nothing was, and the run after it went past its breakpoint
  # without a word (a reviewer of E1, 2026-10-06; it predates E1). The edit
  # case became a Run when the buffer stopped arming anything.
  stopWhileAsking = ->
    await setDoc "n = 0\nbreakpoint\nprint 'after'"
    await wait 500
    await click 'runFresh'
    await t.settle 10000
    await js "Prompt.ask('loop then n += 1'); return true"
    await until_ -> js "return Prompt.pending()"
    await click 'stop'
  pausesAfter = (what) ->
    await until_ (-> (await status()) is 'ready'), 15000
    await setDoc "q = 0\nbreakpoint\nprint 'q ran'"
    await wait 500
    await clearConsole()
    await evalAll()
    ended = await t.settle 10000
    await t.quiet()
    said = await consoleText()
    check "the run after a Stop pauses at its breakpoint, #{what}",
      ended is 'line paused' and not said.includes('q ran'),
      "status=#{ended} console=#{JSON.stringify said.trim()}"
    await click 'stop'
    await until_ -> (await status()) is 'ready'

  await stopWhileAsking()
  await setDoc "print 'ran'"
  await wait 500
  await click 'runFresh'
  await pausesAfter 'though a Run came while the Stop waited'

  await stopWhileAsking()
  await wait 300
  await evalAll()
  await pausesAfter 'though an Eval came while the Stop waited'
