# Running, stopping, restarting and failing: the states the app can get
# into around a sketch, including the ones that used to wedge it.

module.exports = (t) ->
  {js, wait, check, setDoc, evalAll, consoleText, clearConsole, click, status,
   settled, evalRegion} = t
  # 23. a sketch that is not there must not take the boot sequence with it
  missingName = 'definitely-not-a-sketch'
  await js "return (async () => { try { await beans.read('#{missingName}') } catch (e) { return 'threw' } })()"
  await clearConsole()
  await js "await Editor.load('scratch'); return true"
  await evalAll()
  alive = true
  await wait 600
  check 'a failed read does not stop the app', alive is true and (await js "return typeof Panels.size('editor')") is 'number'

  # 33. a stop must not poison the live worker: the next region that swaps runs

  await setDoc "screen 320, 200\nbuffer.on\nloop\n  buffer.swap\n"
  await wait 500
  await evalAll()
  await wait 300
  await click 'stop'
  await wait 300
  await clearConsole()
  await setDoc "buffer.swap\nprint 'ALIVE'\n"
  await wait 500
  await evalAll()
  text = await settled()
  check 'stop does not poison the next run', text.includes('ALIVE') and not text.includes('stopped'), JSON.stringify text.trim()

  # 34. a run while a sketch is running is refused, not queued: the buttons
  # grey out, and the keyboard path says so
  await setDoc "screen 320, 200\nbuffer.on\nloop\n  buffer.swap\n"
  await wait 500
  await clearConsole()
  await evalAll()
  await wait 300
  greyed = await js "return document.getElementById('evalRegion').disabled"
  await evalRegion()
  text = await settled()
  await click 'stop'
  await wait 300
  idle    = await status()
  enabled = await js "return !document.getElementById('evalRegion').disabled"
  check 'run while running is refused', greyed and text.includes('already running') and idle is 'ready' and enabled, "#{JSON.stringify text.trim()} status=#{idle} greyed=#{greyed} enabled=#{enabled}"

  # 35. a run right after a stop must not be killed by the stop's deadline
  await setDoc "loop\n  0\n"
  await wait 500
  await clearConsole()
  await evalAll()
  await wait 200
  await click 'stop'
  await wait 50
  await setDoc "screen 320, 200\nbuffer.on\nprint 'FRESH'\nloop\n  buffer.swap\n"
  await click 'runFresh'
  await wait 800
  text = await consoleText()
  live = await status()
  check 'a run during a stop deadline survives', text.includes('FRESH') and not text.includes('no yield point') and live is 'running', "#{JSON.stringify text.trim()} status=#{live}"
  await click 'stop'
  await wait 300

  # 36. a flood of prints is capped, and the last line still arrives
  await setDoc "print i for i in [1..200000]\nprint 'LAST'\n"
  await wait 500
  await clearConsole()
  await evalAll()
  await wait 2500
  count = await js "return document.getElementById('console').childElementCount"
  text  = await consoleText()
  check 'console caps a flood and keeps the tail', count <= 2000 and text.includes('LAST'), "#{count} lines"

  # 39. a runtime error reports the CoffeeScript line it happened on
  await setDoc "a = 1\n\nboom = ->\n  throw new Error 'kaboom'\n\nboom()\n"
  await wait 500
  await clearConsole()
  await evalAll()
  text = await settled()
  check 'a runtime error shows a full traceback',
    text.includes('kaboom') and
    text.includes('at boom, line 4') and text.includes('at top level, line 6') and
    text.includes("throw new Error 'kaboom'"), JSON.stringify text.trim()

  # and a compile error still reports its own
  await setDoc "x = 1\n  y = 2\n"
  await wait 500
  await clearConsole()
  await evalAll()
  text = await settled()
  check 'a compile error names its line', /line \d/.test(text), JSON.stringify text.trim()

  # 39a. reporting an error must not cost us the present loop. It did: the
  # traceback borrowed `frame` at file scope, which is the loop itself, so the
  # next tick handed an object to requestAnimationFrame and the loop stopped
  # dead. Nothing presented after that and every swap blocked forever, and
  # only reloading the window put it right. Runs after the error tests above,
  # because the poisoning is what it is checking for.
  await clearConsole()
  await setDoc "screen 320, 200\nbuffer.on\nbuffer.swap\nprint 'SWAPPED'\n"
  await wait 500
  await evalAll()
  text  = await settled()
  alive = await status()
  check 'an error does not stop the present loop',
    text.includes('SWAPPED') and alive is 'ready', "#{JSON.stringify text.trim()} status=#{alive}"

  # 40. screen refuses dimensions the renderer cannot make an image from
  await setDoc "try\n  screen 0, 200\n  print 'accepted'\ncatch error\n  print 'refused=' + error.message\nscreen 320, 200\ncls()\nprint 'stillAlive=true'\n"
  await wait 500
  await clearConsole()
  await evalAll()
  text = await settled()
  check 'screen refuses bad dimensions without wedging the renderer',
    text.includes('refused=') and text.includes('width must be') and text.includes('stillAlive=true'),
    JSON.stringify text.trim()

  # 46. a print is visible while the sketch is still busy. postMessage could
  # never do this: a worker in a tight loop delivers nothing until it yields.
  await setDoc "print 'EARLY'\nstart = elapsed\nspun = 0\nwhile elapsed - start < 1.5\n  spun += 1\nprint 'LATE'\n"
  await wait 500
  await clearConsole()
  await evalAll()
  # One of the few places a fixed wait is the point: this reads the console
  # while the sketch is deliberately still busy, so it must not wait for the
  # run to finish the way every other check does.
  await wait 700
  midRun  = await consoleText()
  running = await status()
  await wait 1600
  after = await consoleText()
  check 'a print arrives while the sketch is still running',
    midRun.includes('EARLY') and not midRun.includes('LATE') and running is 'running' and after.includes('LATE'),
    "mid=#{JSON.stringify midRun.trim()} status=#{running}"
