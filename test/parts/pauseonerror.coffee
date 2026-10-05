# PROTOTYPE (research/pause-on-error, Claude, 2026-10-05). Not for main.
#
# With BEANS_PAUSE_ON_ERROR=1 the checks say whether an uncaught sketch error
# stops on the author's line with the frame live, and whether everything
# that must not stop (an error the sketch catches, Stop, the prompt's own
# errors) still does not. Without it, only the measurements run, so the two
# runs can be compared:
#
#   BEANS_TESTS=pauseonerror [BEANS_PAUSE_ON_ERROR=1] npm test
#
# Measurements print as `MEASURE <name> <number>`.

module.exports = (t) ->
  {wait, check, setDoc, evalAll, consoleText, clearConsole, js, status, settle, settled, ask, click} = t
  on_ = Boolean process.env.BEANS_PAUSE_ON_ERROR

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
  nextPause = (since, limit) ->
    seq = await until_ (-> n = await pauseNumber(); n if n and n > since), limit
    await until_ paneText
    seq

  measure = (name, value) -> console.log "MEASURE #{name} #{value}"

  runText = (source) ->
    await setDoc source
    await wait 500
    await clearConsole()
    await evalAll()

  only = process.env.PROBE_ONLY      # 'frames': just the frame-rate measurements

  if on_ and not only
    # 1. the author's own mistake, inside a function
    await runText """
screen 320, 200
ball = null
addAngle = (a, b) ->
  sum = a + b
  ball.x + sum
total = addAngle 41, 1
print 'after'
"""
    seq = await nextPause 0
    await t.quiet()
    said = await consoleText()
    check 'an uncaught error stops on the line that threw, and says it is an error',
      seq and (await status()) is 'line paused' and (await pausedText())?.trim() is 'ball.x + sum' and
        said.includes('error (line 5)') and said.includes('Cannot read properties of null'),
      "status=#{await status()} line=#{JSON.stringify await pausedText()} console=#{JSON.stringify said.trim()}"
    check 'the pane holds the frame that threw',
      (await paneValue 'a') is '41' and (await paneValue 'b') is '1' and (await paneValue 'sum') is '42',
      JSON.stringify await paneText()
    answer = await ask 'sum * 2'
    check 'the prompt answers in that frame', answer.includes('84'), JSON.stringify answer
    await js "Stepping.resume(); return true"
    ended = await until_ -> s = await status(); s if s is 'error'
    await t.quiet()
    said = await consoleText()
    check 'continue ends the run as the error it was, with its traceback',
      ended and said.includes('run (line 5)') and said.includes('at addAngle, line 5') and not said.includes('after'),
      "status=#{await status()} console=#{JSON.stringify said.trim()}"

    # 2. bad input to the runtime: the throw is in ignore-listed code, the stop
    # is on the author's line that called it
    before = (await pauseNumber()) ? 0
    await runText """
hue = 'mauvish'
c = COLORS.byName hue
print 'after'
"""
    got = await nextPause before
    check 'an error thrown inside the runtime stops on the author\'s line that called it',
      got and (await pausedText())?.trim() is 'c = COLORS.byName hue' and (await paneValue 'hue') is '"mauvish"',
      "line=#{JSON.stringify await pausedText()} pane=#{JSON.stringify await paneText()}"
    await js "Stepping.resume(); return true"
    await until_ -> (await status()) is 'error'

    # 3. an error the sketch catches is not stopped at
    await runText """
got = 'none'
try
  null.x
catch e
  got = 'caught'
try
  COLORS.byName 'mauvish'
catch e
  got += ' twice'
print got
"""
    text = await settled()
    check 'an error the sketch catches does not stop it',
      (await status()) is 'ready' and text.includes('caught twice') and not (await pauseNumber()),
      "status=#{await status()} console=#{JSON.stringify text.trim()}"

    # 4. the prompt's own errors do not stop anything, idle or running
    answer = await ask 'null.x'
    check 'an error typed at the idle prompt is only an answer',
      answer.includes('Cannot read') and (await status()) is 'ready' and not (await pauseNumber()),
      JSON.stringify answer
    await runText """
screen 320, 200
buffer.on
n = 0
loop
  n += 1
  buffer.swap
"""
    await until_ -> (await status()) is 'running'
    answer = await ask 'null.x'
    check 'an error typed at a running sketch is only an answer',
      answer.includes('Cannot read') and (await status()) is 'running' and not (await pauseNumber()),
      "#{JSON.stringify answer} status=#{await status()}"

    # 5. Stop throws Interrupted through the sketch; that is not an error
    await clearConsole()
    await click 'stop'
    idle = await until_ -> s = await status(); s if s is 'ready'
    await t.quiet()
    check 'Stop is not mistaken for an error', idle and not (await pauseNumber()) and
      (await consoleText()).includes('stopped'), JSON.stringify (await consoleText()).trim()

    # 6. Stop while stopped at an error ends the run
    await runText "x = null\nx.y\n"
    seen = await nextPause 0
    await click 'stop'
    gone = await until_ -> s = await status(); s if s in ['error', 'ready']
    check 'Stop at an error pause lets the run end', seen and gone, "status=#{await status()}"

    # 7. a syntax error is reported as one, with no pause: the compiler now
    # runs with no catch above it too
    await runText "a = (\nprint 'never'\n"
    text = await settled()
    check 'a syntax error is still just reported',
      (await status()) is 'error' and not (await pauseNumber()) and /run \(line \d+\)/.test(text) and
        not text.includes('stopped where'),
      "status=#{await status()} console=#{JSON.stringify text.trim()}"

  # --- measurements, both ways -------------------------------------------------

  # Iterations a second of a loop that throws and catches, three kinds.
  throwing =
    plain:     'Math.sqrt n'
    throwOwn:  "try\n      throw new Error 'x'\n    catch e\n      null"
    throwNull: "try\n      null.x\n    catch e\n      null"
    throwLib:  "try\n      COLORS.byName 'mauvish'\n    catch e\n      null"
  for name, body of throwing when not only
    for round in [1..3]
      await runText """
n = 0
t0 = performance.now()
while performance.now() - t0 < 1000
  for k in [0...1000]
    #{body}
    n += 1
print "count=\#{n}"
"""
      text = await settled 20000
      measure "#{name}.perSecond", /count=(\d+)/.exec(text)?[1] ? "?(#{text.trim()})"

  # A sketch that draws, flat out at whatever the frame clock allows, and one
  # that does enough work a frame to be CPU-bound.
  frames =
    light: 'circle 160, 100, 50'
    heavy: '(circleFill 160, 100, 90 for r in [1..150])'
    # bound by JS rather than by the frame clock
    math:  's = 0\n  s += Math.sin i for i in [0...1000000]'
  for name, body of frames
    for round in [1..3]
      await runText """
screen 320, 200
buffer.on
f = 0
t0 = performance.now()
while performance.now() - t0 < 2000
  cls()
  #{body}
  buffer.swap
  f += 1
print "fps=\#{(f / 2).toFixed 1}"
"""
      text = await settled 20000
      measure "#{name}.fps", /fps=([\d.]+)/.exec(text)?[1] ? "?(#{text.trim()})"

  return if only

  # Boot: Run to ready, which is where Debugger.enable lands for every run.
  await setDoc "print 'hi'\n"
  await wait 500
  for round in [1..5]
    started = Date.now()
    await click 'runFresh'
    await until_ (-> s = await status(); s if s in ['ready', 'error']), 15000
    measure 'runFresh.ms', Date.now() - started
