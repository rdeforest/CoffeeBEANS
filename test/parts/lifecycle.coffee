# Running, stopping, restarting and failing: the states the app can get
# into around a sketch, including the ones that used to wedge it.

fsp  = require 'fs/promises'
path = require 'path'

module.exports = (t) ->
  {js, wait, check, setDoc, evalAll, consoleText, clearConsole, click, status,
   settle, settled, quiet, evalRegion} = t

  # The same poll as debugging's and sound's: until the app says so, however
  # long that takes, with a ceiling so a broken app fails rather than hangs.
  until_ = (probe, limit = 15000) ->
    deadline = Date.now() + limit
    loop
      value = await probe()
      return value if value
      return null if Date.now() > deadline
      await wait 25

  # 23. a sketch that is not there must not take the boot sequence with it
  missingName = 'definitely-not-a-sketch'
  await js "return (async () => { try { await beans.read('#{missingName}') } catch (e) { return 'threw' } })()"
  await clearConsole()
  await js "await Editor.load('scratch'); return true"
  await evalAll()
  alive = true
  await settle()
  check 'a failed read does not stop the app', alive is true and (await js "return typeof Panels.size('editor')") is 'number'

  # 33. a stop must not poison the live worker: the next region that swaps runs

  await setDoc "screen 320, 200\nbuffer.on\nloop\n  buffer.swap\n"
  await wait 500
  await evalAll()
  await wait 300
  await click 'stop'
  await settled()                    # its own "*** stopped ***" is not the check's
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
  # Not settled(): this sketch never finishes, so that waited out its whole
  # 30s ceiling on every run before reading the console.
  await until_ -> /already running/.test await consoleText()
  text = await consoleText()
  await click 'stop'
  await settle()
  idle    = await status()
  enabled = await js "return !document.getElementById('evalRegion').disabled"
  check 'run while running is refused', greyed and text.includes('already running') and idle is 'ready' and enabled, "#{JSON.stringify text.trim()} status=#{idle} greyed=#{greyed} enabled=#{enabled}"

  # 35. a run right after a stop must not be killed by the stop's deadline.
  # Stop and Run go in one call, 50ms apart in the page, so the Run lands
  # inside the 250ms deadline however slow the round trips are; two separate
  # calls on a 2-core CI runner could miss it, get "no yield point" for the
  # old worker, and fail for the wrong reason.
  await setDoc "loop\n  0\n"
  await wait 500
  await clearConsole()
  await evalAll()
  await wait 200
  await setDoc "screen 320, 200\nbuffer.on\nprint 'FRESH'\nloop\n  buffer.swap\n"
  await js """
    document.getElementById('stop').click()
    await new Promise((resolve) => setTimeout(resolve, 50))
    document.getElementById('runFresh').click()
    return true
  """
  ranAt = Date.now()                 # the stop was 50ms before this
  # Until the new sketch has printed, or the deadline has shot it: however
  # long a boot takes. A fixed 800ms read an empty console on CI, both while
  # still booting and once running.
  await until_ -> /FRESH|no yield point/.test await consoleText()
  # Then past the deadline for certain, so a shot that is still coming has
  # landed: the point here is that it does not happen.
  await wait Math.max 0, ranAt + 1000 - Date.now()
  await quiet()
  text = await consoleText()
  live = await status()
  check 'a run during a stop deadline survives', text.includes('FRESH') and not text.includes('no yield point') and live is 'running', "#{JSON.stringify text.trim()} status=#{live}"
  await click 'stop'
  await settle()

  # 36. a flood the console cannot hold is capped to its tail. 20,000 lines
  # of 1..5 digits are 88,894 bytes of text plus a 4-byte length each, about
  # 169 KB against the 1 MiB print ring (PRINT_BYTES): it fits six times over
  # even if the renderer drained nothing, so every line reaches the console
  # and the cap alone decides what is kept -- 18002..20000 and LAST.
  await setDoc "print i for i in [1..20000]\nprint 'LAST'\n"
  await wait 500
  await clearConsole()
  await evalAll()
  await settled()
  ends = await js """
    const lines = document.getElementById('console')
    return {count: lines.childElementCount, first: lines.firstElementChild?.textContent,
            last: lines.lastElementChild?.textContent}
  """
  check 'console caps a flood and keeps the tail',
    ends.count is 2000 and ends.first is '18002' and ends.last is 'LAST', JSON.stringify ends

  # 61. a flood the ring cannot hold drops lines and says so. A full ring
  # drops new lines rather than block the sketch (NOTES.md, The console goes
  # through shared memory), so which lines survive is a race with the drain
  # and LAST is not promised. The closing line is longer than the whole ring,
  # so at least that one is dropped however fast the renderer keeps up.
  await setDoc "print i for i in [1..200000]\nprint 'x'.repeat 1 << 20\n"
  await wait 500
  await clearConsole()
  await evalAll()
  text  = await settled()
  count = await js "return document.getElementById('console').childElementCount"
  check 'a flood past the ring is counted and still capped',
    count <= 2000 and /\d+ lines? dropped, console ring full/.test(text), "#{count} lines, ends #{JSON.stringify text[-120..]}"

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

  # Saves that overlap must all land, in the order asked. They shared one
  # staging file until 2026-10-05, so one write's rename moved another's file
  # out from under it (ENOENT on Windows CI, and here), and the text left on
  # disk was whichever write happened to finish last.
  overlap = 'save-overlap'
  results = await js """
    const writes = [];
    for (let i = 0; i < 12; i++) writes.push(beans.write('#{overlap}', 'print ' + i + ' ' + 'x'.repeat(4000 - 300 * i) + '\\n'));
    return (await Promise.allSettled(writes)).map(r => r.status === 'fulfilled' ? 'ok' : r.reason.message);
  """
  onDisk = await fsp.readFile path.join(t.paths.sketches, "#{overlap}.coffee"), 'utf8'
  last   = "print 11 #{'x'.repeat 4000 - 300 * 11}\n"
  failed = (r for r in results when r isnt 'ok')
  check 'overlapping saves of one sketch all land, the last one asked for on disk',
    failed.length is 0 and onDisk is last,
    "#{failed.length} failed #{JSON.stringify failed[0] ? ''} disk starts #{JSON.stringify onDisk[0...12]} length #{onDisk.length}"
  await fsp.rm path.join(t.paths.sketches, "#{overlap}.coffee"), force: yes
