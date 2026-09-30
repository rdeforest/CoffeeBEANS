# Line stepping. The debugger lives in the main process and drives the worker
# over the inspector protocol, so these checks go through the real thing: a
# `breakpoint` in the buffer arms it, and every pause is a V8 pause.
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

  # 14. the buffer arms and disarms the debugger by itself
  await setDoc "print 'plain'\n"
  await until_ (-> (await js "return Stepping.armed()") is false), 3000
  disarmed = (await js "return Stepping.armed()") is false
  await setDoc "breakpoint\n"
  armed = await until_ (-> js "return Stepping.armed()"), 3000
  check 'the buffer arms the debugger when it says breakpoint, and not otherwise',
    disarmed and armed, "disarmed=#{disarmed} armed=#{armed}"

  # 15. a region's line numbers are the buffer's: errors say where in the file
  await setDoc "a = 1\n\nboom = ->\n  throw new Error 'kaboom'\n\nboom()\n"
  await wait 500
  await clearConsole()
  await t.cursorOnLine 6
  await t.evalRegion()
  text = await settled()
  check 'a region reports buffer line numbers', text.includes('(line 6)'), JSON.stringify text.trim()
