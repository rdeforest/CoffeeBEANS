# Stopping on uncaught errors. The only part that runs with error stops on:
# every other one is reset with them off (t.reset), so a check there that
# fails a sketch on purpose gets the plain report it was written against.
#
# A run's uncaught error stops where it was thrown, with the frame live, and
# is reported once, when it stops. Nothing else stops: an error the sketch
# catches, the prompt's own, a Stop, a syntax error, and -- decided by Robert,
# 2026-10-05 -- an error thrown once the run has ended. The prototype
# (research/pause-on-error, c5c788d) got those last ones wrong four ways,
# and each has a check here that fails against it.

module.exports = (t) ->
  {wait, check, setDoc, evalAll, consoleText, clearConsole, js, status, settled, ask, click} = t

  until_ = (probe, limit = 10000) ->
    deadline = Date.now() + limit
    loop
      value = await probe()
      return value if value
      return null if Date.now() > deadline
      await wait 25

  pauseNumber = -> js "return Stepping.linePaused()"
  pausedText  = -> js "return (document.querySelector('.cm-paused-line') || {}).textContent ?? null"
  errorText   = -> js "return (document.querySelector('.cm-error-line') || {}).textContent ?? null"
  paneText    = -> js "const v = document.getElementById('vars'); return v.hidden ? null : v.textContent"
  stackShown  = -> js "return !!document.querySelector('#vars .stack-head')"
  disabled    = (id) -> js "return document.getElementById(#{JSON.stringify id}).disabled"
  paneValue   = (name) -> js """
    for (const row of document.querySelectorAll('#vars .var')) {
      const n = row.querySelector('.var-name')
      if (n && n.textContent === #{JSON.stringify name}) return row.querySelector('.var-value').textContent
    }
    return null
  """
  nextPause = (since, limit) ->
    seq = await until_ (-> n = await pauseNumber(); n if n and n > since), limit
    await until_ paneText              # the pane fills after the status does
    seq
  statusBecomes = (wanted, limit) -> until_ (-> s = await status(); s if s is wanted), limit
  times = (text, part) -> text.split(part).length - 1

  runText = (source) ->
    await setDoc source
    await wait 500                     # past the autosave debounce, as every part does
    await clearConsole()
    await evalAll()

  await t.stopOnErrors yes

  # 1. The author's own mistake, inside a function. This is also the guard on
  # the prediction trap: a `catch` anywhere above the run -- even one that
  # could never see the error -- makes V8 call every error caught, and then
  # nothing stops and nothing says so (docs/research/pause-on-error.md).
  NULL_X = "Cannot read properties of null (reading 'x')"
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
  check 'an uncaught error stops on the line that threw, reported once and marked -- nothing above the run catches it',
    seq and (await status()) is 'error paused' and (await pausedText())?.trim() is 'ball.x + sum' and
      (await errorText())?.trim() is 'ball.x + sum' and times(said, "run (line 5): #{NULL_X}") is 1 and
      said.includes('at addAngle, line 5') and said.includes('stopped where it happened'),
    "seq=#{seq} status=#{await status()} line=#{JSON.stringify await pausedText()} console=#{JSON.stringify said.trim()}"

  check 'the pane holds the frame that threw',
    (await paneValue 'a') is '41' and (await paneValue 'b') is '1' and (await paneValue 'sum') is '42',
    JSON.stringify await paneText()

  answer = await ask 'sum * 2'
  check 'the prompt answers in the frame that threw', answer.includes('84'), JSON.stringify answer

  # Its own error there is an answer, not a second stop (an exception inside
  # evaluateOnCallFrame comes back as one; research note, item 7).
  answer = await ask 'ball.y'
  check 'an error typed at the prompt while stopped at an error is only an answer',
    answer.includes("(reading 'y')") and (await pauseNumber()) is seq and (await status()) is 'error paused',
    "#{JSON.stringify answer} seq #{seq} -> #{await pauseNumber()} status=#{await status()}"

  # 2. Step at an error pause is refused, by key and by function, and says
  # why: nothing catches the error, so no line of the author's runs next.
  await clearConsole()
  await js "Stepping.line(); Stepping.step(); return true"
  await t.quiet()
  said = await consoleText()
  holdTitle = await js "return document.getElementById('pauseFrame').title"
  check 'step at an error pause is refused and says why; the step buttons are greyed, the hold button ends the run',
    (await pauseNumber()) is seq and (await status()) is 'error paused' and
      times(said, 'stopped at an error') is 2 and (await disabled 'stepLine') and (await disabled 'stepFrame') and
      holdTitle.includes('end the run'),
    "seq #{seq} -> #{await pauseNumber()} status=#{await status()} console=#{JSON.stringify said.trim()}"

  # 3. Continue ends the run as the error it was, without saying it again,
  # and leaves what a failed run leaves: the stack, the red line, the image.
  await clearConsole()
  await js "Stepping.resume(); return true"
  ended = await statusBecomes 'error'
  await until_ stackShown
  await t.quiet()
  said = await consoleText()
  kept = await ask 'ball'
  check 'continue ends the run as the error, without reporting it again',
    seq and ended and not said.includes(NULL_X) and not said.includes('after') and (await stackShown()) and
      (await errorText())?.trim() is 'ball.x + sum' and (await pauseNumber()) is null and kept.includes('null'),
    "status=#{await status()} console=#{JSON.stringify said.trim()} ball=#{JSON.stringify kept.trim()}"

  # 4. Bad input to the runtime: the throw is in ignore-listed code, the stop
  # on the author's line that called it.
  before = (await pauseNumber()) ? 0
  await runText """
hue = 'mauvish'
c = COLORS.byName hue
print 'after'
"""
  got = await nextPause before
  check 'an error thrown inside the runtime stops on the author\'s line that called it',
    got and (await status()) is 'error paused' and (await pausedText())?.trim() is 'c = COLORS.byName hue' and
      (await paneValue 'hue') is '"mauvish"',
    "status=#{await status()} line=#{JSON.stringify await pausedText()} pane=#{JSON.stringify await paneText()}"

  # 5. Stop at an error pause lets the run end as the error it is, once, and
  # the image survives: the sketch is let go, not shot.
  await clearConsole()
  await click 'stop'
  ended = await statusBecomes 'error'
  await t.quiet()
  said = await consoleText()
  kept = await ask 'hue'
  check 'Stop at an error pause ends the run as that error, said once, with the image kept',
    got and ended and not said.includes('no colour named') and not said.includes('no yield point') and
      kept.includes('"mauvish"'),
    "status=#{await status()} console=#{JSON.stringify said.trim()} hue=#{JSON.stringify kept.trim()}"

  # 6. A thrown value that is not an Error says what it is. It carries no
  # stack, so where it was thrown is the pause's to say.
  before = (await pauseNumber()) ? 0
  await runText "n = 3\nthrow 'oops ' + n\n"
  got = await nextPause before
  await t.quiet()
  said = await consoleText()
  check 'a thrown string stops, and says itself and where',
    got and (await status()) is 'error paused' and said.includes('run (line 2): oops 3'),
    "status=#{await status()} console=#{JSON.stringify said.trim()}"

  # 7. Run at an error pause throws the stopped worker away. Terminated
  # mid-throw, it used to report the error to its Worker object on the way
  # out, which said `worker: ...` and set 'error' over the new run.
  await setDoc "print 'fresh'\n"
  await wait 500
  await clearConsole()
  await click 'runFresh'
  fresh = await statusBecomes 'ready'
  await t.quiet()
  said = await consoleText()
  check 'Run at an error pause starts afresh, and the old worker says nothing',
    got and fresh and said.includes('fresh') and not said.includes('oops') and not said.includes('worker:') and
      not said.includes('renderer:') and (await pauseNumber()) is null,
    "status=#{await status()} console=#{JSON.stringify said.trim()}"

  # 8. What must never stop. An error the sketch catches, its own or the
  # runtime's.
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

  # The prompt's own errors, idle and with a sketch running: serveAsk
  # catches them, so V8 calls them caught.
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
  await statusBecomes 'running'
  answer = await ask 'null.x'
  check 'an error typed at a running sketch is only an answer',
    answer.includes('Cannot read') and (await status()) is 'running' and not (await pauseNumber()),
    "#{JSON.stringify answer} status=#{await status()}"

  # Stop throws Interrupted through the sketch, uncaught by design.
  await clearConsole()
  await click 'stop'
  idle = await statusBecomes 'ready'
  await t.quiet()
  check 'Stop is not mistaken for an error', idle and not (await pauseNumber()) and
    (await consoleText()).includes('stopped'), JSON.stringify (await consoleText()).trim()

  # A syntax error is compiled before the run is dispatched, under a catch.
  await runText "a = (\nprint 'never'\n"
  text = await settled()
  check 'a syntax error is reported as one and never stops',
    (await status()) is 'error' and not (await pauseNumber()) and /run \(line \d+\)/.test(text) and
      not text.includes('stopped where'),
    "status=#{await status()} console=#{JSON.stringify text.trim()}"

  # 9. Errors after the run has ended are reported, once, and never stopped
  # on (Robert, 2026-10-05). Against the prototype: a promise callback's
  # throw paused silently (reason promiseRejection), an async function's
  # never got reported, a timer's paused after the run had ended and was
  # printed twice on Continue. Before E1 a timer's was printed twice too
  # (`worker:`, then `renderer:`) and a rejection's not at all. The run
  # itself ends well each time: `ran` is printed and `kept` is in the image.
  # Each from a fresh worker, so one case left wrong cannot fail the next.
  # Only the timer's is an `exception` pause the debugger has to tell from a
  # run's by inRun; the other three are rejections, let go by their reason
  # before inRun is asked. So the timer check alone guards inRun.
  later =
    'a timer callback':                   ["setTimeout (-> null.x), 50", "(reading 'x')"]
    'a promise callback':                 ["Promise.resolve().then -> null.y", "(reading 'y')"]
    'an async function after its await':  ["later = -> await null; null.z\nlater()", "(reading 'z')"]
    'an async function before its await': ["soon = -> null.w; await null\nsoon()", "(reading 'w')"]
  runLater = (code) ->
    await setDoc "kept = 'yes'\n#{code}\nprint 'ran'\n"
    await wait 500
    await clearConsole()
    await click 'runFresh'
  for name, [code, reading] of later
    await runLater code
    reported = await until_ -> (await consoleText()).includes reading
    # A line through the worker and back: anything else it had to say about
    # the error is said by the time the answer is.
    kept = await ask 'kept'
    await t.quiet()
    said = await consoleText()
    check "an error in #{name}, after the run, is reported once and never stops",
      reported and times(said, reading) is 1 and said.includes('after the run') and said.includes('ran') and
        (await status()) is 'error' and not (await pauseNumber()) and kept.includes('"yes"'),
      "status=#{await status()} pause=#{await pauseNumber()} console=#{JSON.stringify said.trim()}"

  # Nothing is left behind for Continue or Stop to trip on. The prototype's
  # silent pause made Continue say `running` with nothing running, and its
  # Stop then blamed a missing yield point and threw the image away.
  await runLater later['a promise callback'][0]
  await until_ -> (await consoleText()).includes "(reading 'y')"
  # Until the status says something that is not on its way somewhere else.
  # Here it never moves from `error`; there, it went on to `running`, and
  # after Stop to a worker restarted from nothing.
  restless = ['line paused', 'error paused', 'running', 'booting', 'arming']
  atRest = -> until_ (-> s = await status(); s unless s in restless), 5000
  await clearConsole()
  await js "Stepping.resume(); return true"
  went = await atRest()
  check 'continue after an error outside a run leaves nothing running',
    went is 'error' and not (await pauseNumber()), "status=#{await status()}"
  await click 'stop'
  await atRest()
  kept = await ask 'kept'
  await t.quiet()
  said = await consoleText()
  check 'stop after an error outside a run keeps the image',
    not said.includes('no yield point') and kept.includes('"yes"'),
    "status=#{await status()} console=#{JSON.stringify said.trim()}"

  # 10. Whatever the thrown value, the run ends or stops; it never just
  # hangs. Both checks below left the worker paused in V8 with nothing said,
  # status `running` for good and Stop blaming a missing yield point, before
  # the fixes in this check's commit.
  #
  # A value String() cannot convert made the report itself throw.
  before = (await pauseNumber()) ? 0
  await runText "throw Object.create null\n"
  got = await nextPause before, 5000
  await t.quiet()
  said = await consoleText()
  check 'a thrown object with no prototype stops and says what it can',
    got and (await status()) is 'error paused' and said.includes('run (line 1): [object Object]'),
    "status=#{await status()} console=#{JSON.stringify said.trim()}"
  await js "Stepping.resume(); return true"
  await statusBecomes 'error'

  # Any other failure to stop: the run is let go to end as it would with
  # error stops off, and the trouble said. The report the debugger asks for
  # is sabotaged here, which no sketch would do, because nothing a sketch
  # does by accident is known to make it fail once String() is safe.
  before = (await pauseNumber()) ? 0
  await runText "REPL.failure = -> throw new Error 'sabotaged'\nball = null\nball.x\n"
  ended = await statusBecomes 'error', 5000
  await t.quiet()
  said = await consoleText()
  check 'when an error cannot be stopped on, the run ends as the error and says why',
    ended and said.includes('could not stop at the error') and said.includes("run (line 3): #{NULL_X}") and
      ((await pauseNumber()) ? 0) is before,
    "status=#{await status()} console=#{JSON.stringify said.trim()}"
  await setDoc "print 'fresh'\n"                # a worker whose REPL is whole
  await wait 500
  await click 'runFresh'
  await statusBecomes 'ready'

  # A stack that is not a string made the report itself throw, and with it
  # the run, which then never ended, error stops on or off (a reviewer of E1,
  # 2026-10-06). Off, there is no pause to say the line.
  before = (await pauseNumber()) ? 0
  await runText "kept = 'yes'\nthrow {stack: 5}\n"
  got = await nextPause before, 5000
  stoppedAs = await status()
  await js "Stepping.resume(); return true"
  ended = await statusBecomes 'error', 5000
  await t.stopOnErrors no
  await runText "kept = 'yes'\nthrow {stack: 5}\n"
  endedOff = await t.settle()
  said = await consoleText()
  await t.stopOnErrors yes
  check 'a thrown value whose stack is not a string stops, and the run ends as an error, error stops on and off',
    got and stoppedAs is 'error paused' and ended and endedOff is 'error' and said.includes('run: [object Object]'),
    "stopped as #{stoppedAs}, then #{ended}; off, #{endedOff}; console=#{JSON.stringify said.trim()}"

  # Every read of this one throws, so no report of it can be made however
  # the report is written. The run still ends, as the error the report met.
  await runText "throw new Proxy {}, get: -> throw new Error 'unreadable'\n"
  ended = await t.settle()
  await t.quiet()
  said = await consoleText()
  check 'a thrown value that cannot be read at all still ends the run, as an error',
    ended is 'error' and said.includes('run (line 1): unreadable') and not said.includes('after the run'),
    "status=#{ended} console=#{JSON.stringify said.trim()}"

  # 11. A Stop reaching an async function the run left behind: it resumes
  # after the run has unwound, meets the flag still up at a yield point, and
  # its Interrupted is a rejection nobody handles. Not an error.
  await runText """
screen 320, 200
buffer.on
later = ->
  await null
  buffer.swap
later()
loop
  buffer.swap
"""
  await statusBecomes 'running'
  await clearConsole()
  await click 'stop'
  idle = await statusBecomes 'ready'
  await ask '1'                                 # a round trip, past anything still coming
  await t.quiet()
  said = await consoleText()
  check 'Stop reaching an async function left behind is a stop, not an error after the run',
    idle and (await status()) is 'ready' and said.includes('*** stopped ***') and not said.includes('after the run'),
    "status=#{await status()} console=#{JSON.stringify said.trim()}"

  # 12. An error after the run, reported while the next run is already busy,
  # is only news: that run keeps its status and the keyboard. The next run
  # is started the moment the status says the first is done, before the
  # worker's next message -- the timer's error -- is read.
  await setDoc "screen 320, 200\nsetTimeout (-> null.v), 0\nt0 = Date.now()\nloop\n  break if Date.now() - t0 > 100\n"
  await wait 500
  await clearConsole()
  await js """
    const next = #{JSON.stringify "screen 320, 200\nbuffer.on\nloop\n  buffer.swap\n"}
    let started = false                // past any 'arming' and back, which also reads 'ready'
    const watch = new MutationObserver(() => {
      const now = document.getElementById('status').textContent
      if (now === 'running') started = true
      if (!started || now !== 'ready') return
      watch.disconnect()
      const v = Editor.view()
      v.dispatch({ changes: { from: 0, to: v.state.doc.length, insert: next } })
      Editor.focus()
      Editor.command('/eval')
    })
    watch.observe(document.getElementById('status'), { childList: true, characterData: true, subtree: true })
    Editor.command('/eval')
    return true
  """
  heard = await until_ (-> (await consoleText()).includes "(reading 'v')"), 5000
  await wait 200
  busy  = await status()
  owner = await js "return document.activeElement === document.getElementById('promptLine')"
  check 'an error after an earlier run, reported while the next one runs, leaves that run alone',
    heard and busy is 'running' and (await consoleText()).includes('after the run') and not owner,
    "status=#{busy} prompt focused=#{owner} console=#{JSON.stringify (await consoleText()).trim()}"
  await click 'stop'
  await statusBecomes 'ready'

  # 13. Run landing just as an error stops: the old worker's pause is still
  # being worked out in main when Run replaces it. Applied late, it put the
  # old error in the new run's console, set its status, and swallowed the
  # new run's own first error. The sketch throws at a wall-clock moment the
  # page shares, and the page presses Run a few milliseconds after it -- a
  # few offsets, because which side of the race each lands on varies.
  for offset in [0, 1, 2, 3, 5]
    due = Date.now() + 600
    await setDoc "due = #{due}\nloop\n  break if Date.now() >= due\nnull.u\n"
    await wait 300
    await clearConsole()
    await evalAll()
    await js """
      const at = #{due + offset}
      await new Promise((resolve) => setTimeout(resolve, Math.max(0, at - Date.now() - 20)))
      while (Date.now() < at) {}
      const v = Editor.view()
      v.dispatch({ changes: { from: 0, to: v.state.doc.length, insert: 'a = (\\n' } })
      document.getElementById('runFresh').click()
      return true
    """
    text = await settled()
    await wait 200                              # time for a late pause to arrive
    late = await pauseNumber()
    text = await consoleText()
    check "Run #{offset}ms after an error stops reports only the new run's own error",
      (await status()) is 'error' and not late and /run \(line \d+\)/.test(text) and
        not text.includes("(reading 'u')") and not text.includes('stopped where') and not text.includes('debugger:'),
      "status=#{await status()} pause=#{late} console=#{JSON.stringify text.trim()}"

  # 14. A function defined long ago is still the author's. Main keeps every
  # named script's url and the worker every run's source, for the life of the
  # worker; only source maps are capped, at the newest 32, and fetched again
  # when needed. Before, both kept the last 32 sketches whole and forgot the
  # rest: after 40 region evals an error in `old` stopped on its caller, and
  # the report lost `at old` (a reviewer of E1, 2026-10-06). Each eval here
  # stops at a breakpoint, so each makes main fetch that script's map.
  # Not a comment on the first line: a sketch that starts with one keeps none
  # of its names in the image (declaredNames in worker-boot.js skips only
  # block comments; found 2026-10-06, and not this check's to fix).
  await setDoc "z = 0\nold = (v) -> v.x.y\n"
  await wait 500
  await click 'runFresh'
  await statusBecomes 'ready'
  [first] = await t.debugKept()
  await setDoc "z = 1\nbreakpoint\nz = 2\n"
  await wait 500
  stops = await js """
    const status = () => document.getElementById('status').textContent
    const until = async (ok) => {
      const deadline = Date.now() + 5000
      while (!ok()) {
        if (Date.now() > deadline) return false
        await new Promise((r) => setTimeout(r, 5))
      }
      return true
    }
    let stops = 0
    for (let i = 0; i < 40; i++) {
      Editor.command('/eval')
      if (await until(() => status() === 'line paused')) { stops++; Stepping.resume() }
      await until(() => status() === 'ready')
    }
    return stops
  """
  [mid] = await t.debugKept()
  await ask "z + #{n}" for n in [1..5]
  [last] = await t.debugKept()
  check 'the debugger keeps a url for every script, a source map for at most 32, and nothing for prompt lines',
    stops is 40 and last.scripts >= first.scripts + 40 and last.scripts is mid.scripts and 0 < last.maps <= 32,
    "stops=#{stops} first=#{JSON.stringify first} after 40 runs #{JSON.stringify mid} and 5 lines #{JSON.stringify last}"

  await setDoc "old null\n"
  await wait 500
  before = (await pauseNumber()) ? 0
  await clearConsole()
  await evalAll()
  got = await nextPause before
  await t.quiet()
  said = await consoleText()
  pane = await paneText()
  check 'an error in a function defined 40 runs ago stops in it, and the report names it',
    got and (await status()) is 'error paused' and pane?.includes('old \u00b7 line 2') and said.includes('at old, line 2'),
    "status=#{await status()} pane=#{JSON.stringify pane} console=#{JSON.stringify said.trim()}"
  await js "Stepping.resume(); return true"
  await statusBecomes 'error'

  # 15. A Stop while an error pause is still being set up: V8 halted at the
  # throw, main working out the report, the renderer not yet told. Main used
  # to resume only a pause it had finished setting up, so V8 stayed halted,
  # Stop's deadline passed, and the worker was shot for want of a yield
  # point, image and all (found by a reviewer of E1's fix, 2026-10-06). At
  # real latency the pause more likely landed after the Stop and stood, the
  # Stop lost. The hook holds main in that window while Stop is pressed and
  # its 250ms deadline goes by. Let go, the error goes on to end the run, and
  # the worker reports it -- once, since no pause ever did.
  hooks = t.debugHooks
  await setDoc "kept = 'yes'\nball = null\nball.x\n"
  await wait 500
  await clearConsole()
  before = (await pauseNumber()) ? 0
  held = no
  hooks.pausing = (stage) ->
    return unless stage is 'exception'
    hooks.pausing = null
    held = yes
    await click 'stop'
    await wait 400
  await evalAll()
  ended = await statusBecomes 'error', 5000
  hooks.pausing = null
  await t.quiet()
  said = await consoleText()
  kept = await ask 'kept'
  check 'a Stop while an error pause is being set up lets the run end as the error, said once, image kept',
    held and ended and times(said, NULL_X) is 1 and not said.includes('no yield point') and
      not said.includes('debugger:') and ((await pauseNumber()) ? 0) is before and kept.includes('"yes"'),
    "held=#{held} status=#{await status()} console=#{JSON.stringify said.trim()} kept=#{JSON.stringify kept.trim()}"

  # 16. A line from the prompt names the pause it was typed at. One naming
  # an earlier pause -- typed before the renderer heard that pause was over
  # -- that lands while main is still setting up the next one is refused:
  # it would have been evaluated in the new frame with main's own V8
  # commands for that pause still going, and nothing may reach V8 then.
  await setDoc "z = 1\nbreakpoint\nz = 2\nnull.x\n"
  await wait 500
  await clearConsole()
  before = (await pauseNumber()) ? 0
  await evalAll()
  stale = await nextPause before
  answered = 'never asked'
  hooks.pausing = (stage) ->
    return unless stage is 'report'
    hooks.pausing = null
    answered = await js "return await beans.debug.evaluate(#{stale}, 'z')"
  await js "Stepping.resume(); return true"
  got = await nextPause stale
  hooks.pausing = null
  answer = await ask 'z'
  check 'a line naming an earlier pause, landing while the next is set up, is refused; the new pause answers',
    stale and got and answered is null and (await status()) is 'error paused' and answer.includes('2'),
    "stale=#{stale} got=#{got} answered=#{JSON.stringify answered} status=#{await status()} z=#{JSON.stringify answer}"
  await js "Stepping.resume(); return true"
  await statusBecomes 'error'

  # 17. Which worker a pause belongs to is read from REPL.owner, and REPL is
  # the sketch's to clobber. Unread, the owner came back undefined and the
  # renderer dropped a live worker's pause as a replaced one's: the sketch
  # sat halted at `running` with nothing said until Stop. Now the pause is
  # let go and the trouble said. Nulled, reading the owner throws; replaced,
  # it reads undefined without a murmur, and is refused all the same (a
  # reviewer of 1389d44, 2026-10-06). A top-level `REPL = 5` is the sketch's
  # own local and never reaches the global: it pauses as usual (checked by
  # the fixer of 1389d44, 2026-10-06).
  for clobber in ['null', '{}']
    await setDoc "globalThis.REPL = #{clobber}\nbreakpoint\nprint 'after'\n"
    await wait 500
    await clearConsole()
    before = (await pauseNumber()) ? 0
    await evalAll()
    ended = await statusBecomes 'ready', 5000
    await t.quiet()
    said = await consoleText()
    check "a pause whose owner cannot be read (REPL = #{clobber}) is let go and said, not left halted",
      ended and said.includes('could not pause') and said.includes('after') and ((await pauseNumber()) ? 0) is before,
      "status=#{await status()} console=#{JSON.stringify said.trim()}"
    await setDoc "print 'fresh'\n"              # a worker whose REPL is whole
    await wait 500
    await click 'runFresh'
    await statusBecomes 'ready'

  # 18. A setup that never answers. Reading the report of a thrown object
  # runs its `location` getter in the paused worker, and this one loops: the
  # Stop waits on it, its deadline shoots the worker, and the command sent to
  # the dead worker is never answered. Main used to keep waiting on it for
  # good -- every later switch of error stops hung, and every later Stop set
  # nothing aside, so a sketch stopped from then on halted at a `breakpoint`
  # met on its way out (a reviewer of 1389d44, 2026-10-06). A turn now ends
  # with the worker it was taken in. The image is lost: nothing yields in
  # that getter, so the deadline is right to fire.
  await runText "bad = Object.defineProperty {}, 'location', get: -> (x = 0; x += 1 while true; x)\nthrow bad\n"
  await wait 500
  await click 'stop'
  replaced = await statusBecomes 'ready', 5000
  toggled = await Promise.race [t.stopOnErrors(yes).then((-> 'toggled')), wait(2000).then((-> 'hung'))]
  check 'after a setup that never answered, error stops can still be switched',
    replaced and toggled is 'toggled',
    "replaced=#{replaced} switch #{toggled} status=#{await status()}"

  before = (await pauseNumber()) ? 0
  await runText "try\n  loop\n    buffer.swap\nfinally\n  breakpoint\n"
  await wait 300
  await click 'stop'
  ended = await statusBecomes 'ready', 3000
  await t.quiet()
  said = await consoleText()
  check 'and a Stop still sets breakpoints aside: one met on the way out does not stop the sketch',
    ended and ((await pauseNumber()) ? 0) is before and not said.includes('no yield point'),
    "status=#{await status()} pause=#{await pauseNumber()} console=#{JSON.stringify said.trim()}"
  await setDoc "print 'fresh'\n"
  await wait 500
  await click 'runFresh'
  await statusBecomes 'ready'

  # 19. A step whose landing arrives while a Stop is setting breakpoints
  # aside. The Stop took V8's pause before that and never looked again, so
  # the landing stood, the renderer was shown it, and the deadline shot the
  # worker, image and all (a reviewer of 1389d44, 2026-10-06). On its own the
  # gap is a few milliseconds; the hook holds it open.
  await setDoc "kept = 'yes'\nz = 1\nbreakpoint\nz = 2\nloop\n  buffer.swap\n"
  await wait 500
  await clearConsole()
  before = (await pauseNumber()) ? 0
  await evalAll()
  got = await nextPause before
  hooks.stopping = ->
    hooks.stopping = null
    wait 300
  await js "beans.debug.step(); document.getElementById('stop').click(); return true"
  ended = await statusBecomes 'ready', 5000
  hooks.stopping = null
  await t.quiet()
  said = await consoleText()
  kept = await ask 'kept'
  check 'a step landing while Stop sets breakpoints aside is let go too, and the image kept',
    got and ended and not said.includes('no yield point') and kept.includes('"yes"'),
    "got=#{got} status=#{await status()} console=#{JSON.stringify said.trim()} kept=#{JSON.stringify kept.trim()}"

  # 20. The switch the preference and the suite share: off, an error ends
  # the run the way it always did.
  await t.stopOnErrors no
  await runText "ball = null\nball.x\nprint 'after'\n"
  text = await settled()
  check 'with error stops off, an error ends the run and is reported once, without stopping',
    (await status()) is 'error' and not (await pauseNumber()) and times(text, "run (line 2): #{NULL_X}") is 1,
    "status=#{await status()} console=#{JSON.stringify text.trim()}"
