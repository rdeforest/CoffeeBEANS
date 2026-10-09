# Frame stepping. Pausing is declining to clear the swap, so a paused sketch is
# parked in doSwap's Atomics.wait -- which wakes every 100ms, which is why the
# prompt still answers one. That property is the whole point and the easiest
# thing to break.

module.exports = (t) ->
  {wait, check, setDoc, evalAll, consoleText, clearConsole,
   click, status, settle, settled, ask, pause, step, go} = t

  count = (text) -> Number /(-?\d+)/.exec(text)?[1] ? -1

  ticker = """
screen 320, 200
buffer.on
ticks = 0
loop
  ticks += 1
  cls()
  point ticks %% 320, 100, COLORS.white
  buffer.swap
"""

  await setDoc ticker
  await wait 500
  await clearConsole()
  await evalAll()
  await wait 400
  went = await status()

  # 1. a pause holds it at a frame boundary
  await pause()
  held = await status()
  first = count await ask 'ticks'
  await wait 500
  same  = count await ask 'ticks'
  check 'pause holds a running sketch at a frame',
    went is 'running' and held is 'frame paused' and first > 0 and same is first,
    "status=#{held} ticks=#{first} then #{same}"

  # 2. the prompt answers a paused sketch -- it is parked in Atomics.wait, and
  # only the 100ms timeout in doSwap's loop makes this work at all
  # No digit in the expression: `count` takes the first number it finds and
  # the slice begins with the echoed line, so `ticks * 2` would count the 2.
  answer = await ask 'ticks + ticks'
  check 'the prompt answers while paused', count(answer) is same * 2,
    JSON.stringify answer.trim()

  # 3. a step lets exactly one frame through
  await step()
  await wait 300
  stepped = count await ask 'ticks'
  await wait 300
  stillStepped = count await ask 'ticks'
  check 'a step advances exactly one frame',
    stepped is same + 1 and stillStepped is stepped,
    "#{same} -> #{stepped}, then #{stillStepped}"

  # 4. continue lets it run again
  await go()
  running = await status()
  await wait 500
  loose = count await ask 'ticks'
  check 'continue lets it run again', running is 'running' and loose > stepped + 5,
    "status=#{running} #{stepped} -> #{loose}"

  # 5. a busy worker refuses an eval whether it is running or paused
  await pause()
  await clearConsole()
  await evalAll()
  await t.quiet()          # the refusal is said on a timer, like every line
  refused = await consoleText()
  greyed  = await t.js "return document.getElementById('evalRegion').disabled"
  check 'a paused sketch refuses an eval, like a running one',
    refused.includes('already running') and greyed,
    "#{JSON.stringify refused.trim()} greyed=#{greyed}"

  # 6. stop releases a paused worker without the watchdog, and clears the pause
  await clearConsole()
  await click 'stop'
  idle = await settle()
  await setDoc "print 'AFTER'\n"
  await wait 500
  await evalAll()
  after = await settled()
  check 'stop releases a paused sketch and clears the pause',
    idle is 'ready' and after.includes('AFTER') and not after.includes('no yield point'),
    "status=#{idle} #{JSON.stringify after.trim()}"

  # 7. A `breakpoint` left in a sketch always stops it. Until pausing on
  # errors this check said the opposite -- that the command cost nothing with
  # no debugger attached -- but the debugger is now armed for every run
  # (Robert, 2026-10-05; AGENTS.md, Decisions), so a debugger is always
  # attached. With DevTools open, which keeps ours out, it is still a no-op;
  # that is not tested here.
  linePaused = -> t.js "return Stepping.linePaused()"
  pausedAfter = (since) ->
    deadline = Date.now() + 10000
    loop
      seq = await linePaused()
      return seq if seq and seq > since or Date.now() > deadline
      await wait 25
  await setDoc """
screen 320, 200
print 'kind=' + typeof Object.getOwnPropertyDescriptor(globalThis, 'breakpoint').get
breakpoint
print 'ranOn=true'
each = (n) ->
  breakpoint
  n * 2
print 'inAFunction=' + each 21
"""
  await wait 500
  await clearConsole()
  await evalAll()
  atTop = await pausedAfter 0
  topStatus = await status()
  await t.js "Stepping.resume(); return true"
  inFunction = await pausedAfter atTop ? 0
  await t.js "Stepping.resume(); return true"
  # Not settled(): a line pause counts as settled, and the resume may not
  # have reached the status line yet.
  ended = await t.waitFor "return document.getElementById('status').textContent === 'ready'", 10000
  await t.quiet()
  text = await consoleText()
  check 'breakpoint always stops: the debugger is armed for every run',
    atTop and topStatus is 'line paused' and inFunction > atTop and ended and
      text.includes('kind=function') and text.includes('ranOn=true') and text.includes('inAFunction=42'),
    "pauses #{atTop} then #{inFunction} status=#{topStatus} console=#{JSON.stringify text.trim()}"

  # 8. the runtime modules are named, so a debugger can be told to ignore them
  # in one pattern -- and so that breakpoint.coffee can be left out of it.
  await setDoc """
screen 320, 200
try
  screen 0, 200
catch error
  print 'runtimeNamed=' + /beans-runtime\\//.test error.stack
  print 'sketchNamed='  + /beans-run-\\d+\\.coffee/.test error.stack
  print 'anonymous='    + /at eval \\(eval/.test error.stack
"""
  await wait 500
  await clearConsole()
  await evalAll()
  text = await settled()
  check 'the runtime is named so it can be ignore-listed',
    text.includes('runtimeNamed=true') and text.includes('sketchNamed=true'),
    JSON.stringify text.trim()

  # 9. The same for Run over a running sketch: no debugger at all, and the
  # old worker used to go on for two seconds, because Chromium's terminate()
  # waits that long before forcing a busy worker. `k` counts the new sketch's
  # swaps against the frames presented since it began; a zombie halved it.
  await setDoc """
screen 320, 200
n = 0
loop
  n += 1
  print 'OLD ' + n if n %% 30 is 0
  buffer.swap
"""
  await wait 500
  await evalAll()
  await wait 400
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
  deadline = Date.now() + 15000
  await wait 25 until (await status()) is 'running' or Date.now() > deadline
  # Not before the Run: it prints what the old worker wrote before it.
  await clearConsole()
  shown = 0
  until shown >= 100 or Date.now() > deadline
    shown = Number /(\d+)\s*$/.exec(await ask 'frames - f0')?[1]
  [mine, presented] = (Number n for n in /(\d+) (\d+)"\s*$/.exec(await ask "k + ' ' + (frames - f0)")?[1..2] ? [])
  await t.quiet()
  said = await consoleText()
  check 'run over a running sketch: the old worker prints nothing and takes no frames',
    not said.includes('OLD') and mine / presented > 0.8,
    "swaps #{mine} of #{presented} frames, console=#{JSON.stringify said.trim()[-300..]}"
  await click 'stop'
  await settle()

  # 10. Interrupted can be caught. A loop that catches everything goes round
  # again after the one that ends it, and for the two seconds before Chromium
  # forces the worker it used to draw red over the new run, resize its screen
  # and turn on double buffering -- unless the old worker has let go of the
  # shared memory. `bad` counts the new sketch's frames whose pixel is not the
  # one it drew; the canvas width is what the renderer reads from the header.
  #
  # The line is asked in the same tick as the Run, while the old worker is
  # still spinning: it must wait for the new sketch, which answers from its
  # own names at its first yield point, and the old one must not take it.
  await setDoc """
screen 100, 80
who = 'old'
loop
  try
    screen 100, 80
    buffer.on
    buffer.fps 5
    cls COLORS.red
    buffer.swap
  catch e
    null
"""
  await wait 500
  await evalAll()
  deadline = Date.now() + 15000
  await wait 25 until (await status()) is 'running' or Date.now() > deadline
  await wait 400
  await setDoc """
screen 200, 120
who = 'new'
cls COLORS.lime
bad  = 0
seen = 0
loop
  seen += 1
  bad  += 1 unless pget(5, 5) is COLORS.lime
  buffer.swap
"""
  await wait 500
  await clearConsole()
  await t.js """
    document.getElementById('runFresh').click()
    Prompt.ask('who')
    return true
  """
  deadline = Date.now() + 10000
  await wait 25 while (await t.js "return Prompt.pending()") and Date.now() < deadline
  await t.quiet()
  answered = await consoleText()
  widths = new Set
  for i in [0...20]
    widths.add await t.js "return document.getElementById('screen').width"
    await wait 25
  counts = await ask "bad + ' ' + seen"
  [bad, seen] = (Number n for n in /(\d+) (\d+)"\s*$/.exec(counts)?[1..2] ? [])
  check 'a line asked as Run is pressed is answered by the new sketch, not the old',
    answered.includes('"new"') and not answered.includes('old'),
    JSON.stringify answered.trim()[-200..]
  check 'an old worker that catches its stop draws nothing and sets no mode over the new run',
    bad is 0 and seen > 0 and widths.size is 1 and widths.has(200),
    "bad=#{bad} of #{seen} frames, widths=#{[widths...].join()}"
  await click 'stop'
  await settle()

  # 11. Every line answered at a yield point leaves its poke queued in that
  # worker's inbox, and an old worker unwinding after a Run goes on to read
  # them. It used to claim whatever line was waiting -- by then the new
  # worker's -- and drop it on finding the memory no longer its own, leaving
  # the ask claimed for good: that line never answered, and every later one
  # said it was still waiting, until the next Run. Once for each way to run.
  stuck = []
  for how in ['eval', 'fresh']
    await setDoc """
screen 100, 80
loop
  t0 = performance.now()
  null while performance.now() - t0 < 100
  buffer.swap
"""
    await wait 400
    if how is 'eval' then await evalAll() else await click 'runFresh'
    deadline = Date.now() + 15000
    await wait 25 until (await status()) is 'running' or Date.now() > deadline
    await wait 300
    await ask '1 + 1'
    await ask '2 + 2'
    await setDoc """
screen 100, 80
loop
  buffer.swap
"""
    await wait 400
    await clearConsole()
    await t.js """
      document.getElementById('runFresh').click()
      setTimeout(() => Prompt.ask('6 * 7'), 30)
      return true
    """
    await wait 100
    deadline = Date.now() + 3000
    await wait 25 while (await t.js "return Prompt.pending()") and Date.now() < deadline
    await t.quiet()
    said = await consoleText()
    stuck.push "#{how}: #{JSON.stringify said.trim()}" unless said.includes '42'
    # A wedged ask outlives Stop; only a Run clears it for the next check.
    await click 'runFresh' if stuck.length
    await settle()
    await click 'stop'
    await settle()
  check 'a line asked just after Run is answered, not taken by the old worker',
    stuck.length is 0, stuck.join(' | ') or 'eval and fresh both answered'

  # 12. A worker in the middle of a long frame when Run is pressed still holds
  # the shared memory until it reaches a check. The drawing it does in that
  # time is overwritten by the new run, but a mode is not: its `screen` used
  # to land after the new sketch's and stay. The width is what the renderer
  # reads from the header; it must go to 200 once and stay there.
  await setDoc """
loop
  t0 = performance.now()
  null while performance.now() - t0 < 1500
  screen 100, 80
  buffer.on
  buffer.swap
"""
  await wait 400
  await evalAll()
  deadline = Date.now() + 15000
  await wait 25 until (await status()) is 'running' or Date.now() > deadline
  await wait 1600
  await setDoc """
screen 200, 120
loop
  buffer.swap
"""
  await wait 300
  await click 'runFresh'
  widths = []
  for i in [0...100]
    width = await t.js "return document.getElementById('screen').width"
    widths.push width unless widths[widths.length - 1] is width
    await wait 25
  check 'an old worker mid-frame at Run sets no mode over the new run',
    widths[widths.length - 1] is 200 and widths.indexOf(200) is widths.lastIndexOf(200),
    "widths=#{widths.join()}"
  await click 'stop'
  await settle()
