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
    went is 'running' and held is 'paused' and first > 0 and same is first,
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

  # 7. `breakpoint` costs nothing when nobody is watching. A debugger statement
  # with no debugger attached is a no-op, which is the whole reason the command
  # can be spelled in the source rather than kept in a list of line numbers --
  # but if that were ever not true, every sketch carrying one would hang.
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
  text = await settled()
  check 'breakpoint is free when no debugger is attached',
    text.includes('kind=function') and text.includes('ranOn=true') and text.includes('inAFunction=42'),
    JSON.stringify text.trim()

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
