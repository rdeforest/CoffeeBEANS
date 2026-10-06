# Running, stopping, restarting and failing: the states the app can get
# into around a sketch, including the ones that used to wedge it.

fs                    = require 'fs'
fsp                   = require 'fs/promises'
path                  = require 'path'
{spawn}               = require 'child_process'
{BrowserWindow, Menu} = require 'electron'

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
  #
  # And the notice comes last. That drop is the final thing the sketch does,
  # so every line it did print was written before it. When the drain read the
  # drop count after the ring, a drop made mid-drain was announced ahead of
  # the thousands of lines still past the head it had read, and the cap then
  # trimmed it away -- about 1 run in 6 here, red on CI (found by Claude,
  # 2026-10-05). The old drain lost between 3 and 6 rounds of 12 when a
  # Claude fixer and reviewer ran it, the same night: at the worst of those
  # (1 in 4) ten rounds all pass by luck 6% of the time, at 2 in 5 under 1%.
  # Each round costs about a fifth of a second.
  await setDoc "print i for i in [1..200000]\nprint 'x'.repeat 1 << 20\n"
  await wait 500
  rounds = for round in [1..10]
    await clearConsole()
    await evalAll()
    await settled()
    await js """
      const lines = document.getElementById('console')
      return {count: lines.childElementCount, last: lines.lastElementChild?.textContent}
    """
  missed = rounds.filter ({count, last}) -> count > 2000 or not /^\*\*\* \d+ lines? dropped, console ring full \*\*\*$/.test last
  check 'a flood past the ring is counted and still capped',
    missed.length is 0, "#{missed.length} of #{rounds.length} rounds missed: #{JSON.stringify missed[..2]}"

  # A drop on its own is still printing in flight. The flood above cannot
  # tell: its ring is never empty when the drop lands, so pending() is true
  # for the bytes and the drop rides along. Here the ring stays empty and only
  # the drop count moves. The test spins the renderer's own thread from the
  # run onward, so no drain can take the count before pending() reads it; the
  # worker still runs, being another thread.
  await setDoc "print 'x'.repeat 1 << 20\n"
  await wait 500
  await clearConsole()
  await quiet()
  seen = await js """
    const before = Printing.pending()
    Editor.command('/eval')
    const deadline = performance.now() + 5000
    while (performance.now() < deadline && !Printing.pending()) {}
    return {before, during: Printing.pending()}
  """
  text = await settled()
  check 'a dropped line counts as printing still pending',
    not seen.before and seen.during and /\*\*\* 1 line dropped/.test(text), "#{JSON.stringify seen}, #{JSON.stringify text}"

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
  onDisk = t.asHeld await fsp.readFile path.join(t.paths.sketches, "#{overlap}.coffee"), 'utf8'
  last   = "print 11 #{'x'.repeat 4000 - 300 * 11}\n"
  failed = (r for r in results when r isnt 'ok')
  check 'overlapping saves of one sketch all land, the last one asked for on disk',
    failed.length is 0 and onDisk is last,
    "#{failed.length} failed #{JSON.stringify failed[0] ? ''} disk starts #{JSON.stringify onDisk[0...12]} length #{onDisk.length}"
  await fsp.rm path.join(t.paths.sketches, "#{overlap}.coffee"), force: yes

  # A save in flight must not let the watcher revert the editor. The editor
  # took any read of the old text as an outside edit, went back to it, and
  # flipped forward again on the new save's echo -- invisible afterwards, but
  # long enough in between for /eval to run the previous buffer, which is how
  # every Windows CI failure of the 2026-10-05 overnight session looked. This
  # net is what those checks did, many times over: it passed on Linux before
  # the fix too, and is here for the CI runners, where it did not.
  wrong = []
  for round in [1..20]
    marker = "SAVE_ROUND_#{round}"
    await clearConsole()
    await setDoc "print '#{marker}'\n"
    await wait 70 * (round % 5)                 # land on every side of the autosave
    await evalAll()
    printed = await settled()
    doc     = await js "return Editor.all()"
    wrong.push "#{round}: printed #{JSON.stringify printed.trim()} doc #{JSON.stringify doc}" unless printed.includes(marker) and doc.includes(marker)
  await wait 1000
  kept = await js "return Editor.all()"
  wrong.push "a second on: doc #{JSON.stringify kept}" unless kept.includes 'SAVE_ROUND_20'
  check 'twenty edit-and-run rounds each run their own text, and the editor keeps it',
    wrong.length is 0, wrong[0...3].join ' | '

  # The same race, made to happen: the suite holds a save before its rename
  # (main's `faults`) and puts the old text back on disk meanwhile, as a late
  # echo would. The editor must keep the new text throughout, and an outside
  # write once the save has landed must still arrive.
  {faults} = t.paths
  race     = 'save-race'
  raceFile = path.join t.paths.sketches, "#{race}.coffee"
  raceText = -> fsp.readFile raceFile, 'utf8'
  try
    await fsp.writeFile raceFile, "print 'OLD'\n", 'utf8'
    await js "await Editor.load('#{race}'); return true"
    faults.slow = 1500
    await setDoc "print 'NEW'\n"
    await js "Editor.save(); return true"
    await wait 100
    await fsp.writeFile raceFile, "print 'OLD'\n", 'utf8'
    await wait 500                              # past the watcher's 60ms, the read and the IPC
    during = await js "return Editor.all()"
    faults.slow = 0
    landed = await t.untilDoc "print 'NEW'\n"
    await until_ -> (await raceText()) is "print 'NEW'\n"
    disk   = await raceText()
    check 'a watcher read during a save in flight does not put the old text back',
      during is "print 'NEW'\n" and disk is "print 'NEW'\n",
      "during #{JSON.stringify during} landed #{JSON.stringify landed} disk #{JSON.stringify disk}"

    await fsp.writeFile raceFile, "print 'OUTSIDE'\n", 'utf8'
    outside = await t.untilDoc "print 'OUTSIDE'\n"
    check 'and an outside write after it still reaches the editor',
      outside is "print 'OUTSIDE'\n", JSON.stringify outside

    # Windows refusing the rename, as Defender or the indexer does: a few
    # refusals are waited out; one that outlasts the retries reaches the
    # editor, which says so and keeps the edit as unsaved.
    faults.windows = yes
    faults.refuse  = 3
    await quiet()                               # nothing queued from the checks above
    await clearConsole()
    await setDoc "print 'RETRIED'\n"
    await js "await Editor.save(); return true"
    disk  = await raceText()
    dirty = await js "return Editor.dirty()"
    left  = faults.refuse
    check 'a rename refused a few times is retried and the save lands',
      disk is "print 'RETRIED'\n" and not dirty and left is 0,
      "disk #{JSON.stringify disk} dirty #{dirty} refusals left #{left}"

    faults.refuse = 100
    await setDoc "print 'REFUSED'\n"
    await js "await Editor.save(); return true"
    faults.refuse = 0
    await quiet()
    said  = await consoleText()
    disk  = await raceText()
    dirty = await js "return Editor.dirty()"
    doc   = await js "return Editor.all()"
    check 'a rename refused past the retries says it could not save and leaves the edit unsaved',
      said.includes("could not save #{race}") and disk is "print 'RETRIED'\n" and dirty and doc is "print 'REFUSED'\n",
      "said #{JSON.stringify said.trim()} disk #{JSON.stringify disk} dirty #{dirty} doc #{JSON.stringify doc}"
  finally
    Object.assign faults, slow: 0, refuse: 0, windows: no
    await js "await Editor.load('scratch'); return true"
    await fsp.rm raceFile, force: yes

  # --- an edit made just before the page goes away ---------------------------

  # Each way a page leaves, with an edit the autosave has not taken. Not in
  # the test window: on Linux a page reloaded inside it (shown, then
  # minimised) gets no animation frames ever again (AGENTS.md, Platform
  # facts). A second window, opened on its own sketch, instead.
  openPage = (name) ->
    page = new BrowserWindow
      show: no
      webPreferences:
        contextIsolation: yes
        nodeIntegration:  no
        preload:          path.join t.paths.root, 'src', 'main', 'preload.js'
    page.webContents.setAudioMuted yes
    await page.loadURL "app://beans/src/renderer/index.html?sketch=#{name}"
    await onSketch page, name
    page

  onSketch = (page, name) ->
    until_ -> page.webContents.executeJavaScript "typeof Editor !== 'undefined' && Editor.name() === '#{name}'"

  # Hands back whether the edit is still waiting for its autosave, which is
  # the whole premise of each check below.
  edit = (page, text) -> page.webContents.executeJavaScript """
    (() => { const v = Editor.view()
             v.dispatch({ changes: { from: 0, to: v.state.doc.length, insert: #{JSON.stringify text} } })
             return Editor.dirty() })()
  """

  menuItem = (role) ->
    items = Menu.getApplicationMenu().items.flatMap (top) -> top.submenu?.items ? []
    items.find (item) -> item.role is role

  # The menu hands a role the focused window; the hidden page is never
  # focused, so it is handed over the way the menu would.
  reload = (page) ->
    reloaded = new Promise (resolve) -> page.webContents.once 'did-finish-load', resolve
    menuItem('reload').click null, page, page.webContents
    await reloaded

  close = (page) ->
    closed = new Promise (resolve) -> page.once 'closed', resolve
    page.close()
    await closed

  leaving  = 'unload-edit'
  leaveAt  = path.join t.paths.sketches, "#{leaving}.coffee"
  other    = 'unload-other'
  otherAt  = path.join t.paths.sketches, "#{other}.coffee"
  {faults} = t.paths
  try
    # View > Reload, the item Ctrl-r from the canvas or the pane reaches. The
    # save is held for 1.5s, as Windows' rename retry can hold one: the reload
    # has to wait for it, or the page it brings up reads the old text.
    await fsp.writeFile leaveAt, "print 'OLD'\n", 'utf8'
    page    = await openPage leaving
    pending = await edit page, "print 'RELOADED'\n"
    faults.slow = 1500
    await reload page
    faults.slow = 0
    await onSketch page, leaving
    doc  = await page.webContents.executeJavaScript 'Editor.all()'
    disk = await fsp.readFile leaveAt, 'utf8'
    page.destroy()
    check 'an edit made just before View > Reload is saved, and is what the reloaded page shows',
      pending and doc is "print 'RELOADED'\n" and disk is "print 'RELOADED'\n",
      "pending #{pending} doc #{JSON.stringify doc} disk #{JSON.stringify disk}"

    # And an autosave already on its way when the reload comes: nothing is
    # pending in the page, and the reload must still wait for it.
    await fsp.writeFile leaveAt, "print 'OLD'\n", 'utf8'
    page = await openPage leaving
    faults.slow = 1500
    await edit page, "print 'IN FLIGHT'\n"
    sent = await page.webContents.executeJavaScript 'Editor.save(), !Editor.dirty()'
    await reload page
    faults.slow = 0
    await onSketch page, leaving
    doc = await page.webContents.executeJavaScript 'Editor.all()'
    page.destroy()
    check 'an autosave still in flight at View > Reload is what the reloaded page shows',
      sent and doc is "print 'IN FLIGHT'\n", "sent #{sent} doc #{JSON.stringify doc}"

    # The same, and that autosave fails. The page that asked for it is going
    # and cannot try again, so it sends its text with the flush and main
    # writes it once more behind the failure. The failure is a refused
    # rename; on Windows the rename is retried and the first save lands, so
    # there this checks only the wait.
    await fsp.writeFile leaveAt, "print 'OLD'\n", 'utf8'
    page = await openPage leaving
    Object.assign faults, slow: 1500, refuse: 1
    await edit page, "print 'REFUSED'\n"
    sent = await page.webContents.executeJavaScript 'Editor.save(), !Editor.dirty()'
    await reload page
    Object.assign faults, slow: 0, refuse: 0
    await onSketch page, leaving
    doc  = await page.webContents.executeJavaScript 'Editor.all()'
    disk = await fsp.readFile leaveAt, 'utf8'
    page.destroy()
    check 'an autosave that fails while View > Reload waits for it is saved again',
      sent and doc is "print 'REFUSED'\n" and disk is "print 'REFUSED'\n",
      "sent #{sent} doc #{JSON.stringify doc} disk #{JSON.stringify disk}"

    # The same, but the page has moved on to another sketch by the time it
    # reloads: switching saves first, yet does not wait for a save already
    # going, so the flush has to cover a sketch that is no longer current.
    await fsp.writeFile leaveAt, "print 'OLD'\n", 'utf8'
    await fsp.writeFile otherAt, "print 'OTHER'\n", 'utf8'
    page = await openPage leaving
    Object.assign faults, slow: 1500, refuse: 1
    await edit page, "print 'SWITCHED'\n"
    sent = await page.webContents.executeJavaScript 'Editor.save(), !Editor.dirty()'
    away = await page.webContents.executeJavaScript "Editor.load('#{other}')"
    await reload page
    Object.assign faults, slow: 0, refuse: 0
    await onSketch page, leaving
    doc  = await page.webContents.executeJavaScript 'Editor.all()'
    disk = await fsp.readFile leaveAt, 'utf8'
    page.destroy()
    check 'an autosave that fails after the page switched sketches is saved again at View > Reload',
      sent and away is other and doc is "print 'SWITCHED'\n" and disk is "print 'SWITCHED'\n",
      "sent #{sent} away #{away} doc #{JSON.stringify doc} disk #{JSON.stringify disk}"

    # A save that hangs, as one on an NFS or FUSE data folder can: the reload
    # waits SAVE_LIMIT for it and then goes, rather than freezing the page.
    # The page it brings up shows the old text; the save still lands later.
    {saveLimit} = t.paths
    hold        = saveLimit + 2500
    await fsp.writeFile leaveAt, "print 'OLD'\n", 'utf8'
    page    = await openPage leaving
    pending = await edit page, "print 'HUNG'\n"
    faults.slow = hold
    began = Date.now()
    await reload page
    took = Date.now() - began
    faults.slow = 0
    page.destroy()
    disk = await until_ (-> fsp.readFile(leaveAt, 'utf8').then (text) -> text if text is "print 'HUNG'\n"), hold + 5000
    check 'View > Reload stops waiting for a save that hangs, and the save still lands',
      pending and saveLimit <= took < hold and disk?,
      "pending #{pending} took #{took}ms (limit #{saveLimit}, save held #{hold}) landed #{disk?}"

    # Closing the window. Chromium waits only about 500ms for a closing page
    # and then closes it anyway, and a rename Windows refuses can be retried
    # for longer, so the disk is read until the save lands rather than at
    # `closed`. Main saving it after the window has gone is enough: a quit
    # waits for it (will-quit, and the check below).
    await fsp.writeFile leaveAt, "print 'OLD'\n", 'utf8'
    page    = await openPage leaving
    pending = await edit page, "print 'CLOSED'\n"
    await close page
    disk = await until_ (-> fsp.readFile(leaveAt, 'utf8').then (text) -> text if text is "print 'CLOSED'\n"), 5000
    disk ?= await fsp.readFile leaveAt, 'utf8'
    check 'an edit made just before the window closes is saved',
      pending and disk is "print 'CLOSED'\n", "pending #{pending} disk #{JSON.stringify disk}"
  finally
    Object.assign faults, slow: 0, refuse: 0
    page?.destroy() unless page?.isDestroyed()
    await fsp.rm leaveAt, force: yes
    await fsp.rm otherAt, force: yes

  # Quitting, for real: File > Quit, the item Cmd-Q reaches. It cannot happen
  # in the app the suite runs in, so a second Electron runs the `quit` part
  # (test/parts/quit.coffee) on a data folder of its own, with its save held
  # for `hold`, and the disk is read once it has exited. Bounded: a child
  # still running after 30s is sent SIGTERM, which only asks it to quit -- a
  # quit that stalls outlives it (below) -- so SIGKILL follows 5s later, and
  # either fails the check rather than leaving the suite waiting for good.
  quitChild = (hold) ->
    home  = path.join t.paths.data, 'quit-child'
    saved = path.join home, 'sketches', 'quit-edit.coffee'
    await fsp.rm home, recursive: yes, force: yes
    env = {process.env..., BEANS_DATA_HOME: home, BEANS_TESTS: 'quit', BEANS_QUIT_HOLD: String hold}
    delete env[name] for name in ['ELECTRON_RUN_AS_NODE', 'BEANS_SHOW', 'BEANS_DEVTOOLS', 'BEANS_CAPTURE', 'BEANS_QUERY']
    began  = Date.now()
    child  = spawn process.execPath, [t.paths.root], {cwd: t.paths.root, env}
    output = ''
    child.stdout.on 'data', (chunk) -> output += chunk
    child.stderr.on 'data', (chunk) -> output += chunk
    killed = null
    kill   = (signal) -> killed = signal; child.kill signal
    killer = setTimeout (-> kill 'SIGTERM'; killer = setTimeout (-> kill 'SIGKILL'), 5000), 30000
    [code, signal] = await new Promise (resolve) -> child.on 'exit', (code, signal) -> resolve [code, signal]
    took = Date.now() - began
    clearTimeout killer
    disk = try fs.readFileSync(saved, 'utf8') catch error then error.code
    said = output.split('\n').filter (line) -> /PASS|FAIL|quit|crash|flush/.test line
    {code, disk, said, took, killed, report: "exit #{code} #{signal ? ''} after #{took}ms#{if killed then ", sent #{killed}" else ''} disk #{JSON.stringify disk} child said #{JSON.stringify said}"}

  {code, disk, killed, report} = await quitChild 1500
  check 'an edit made just before the app quits is on disk after it has exited',
    code is 0 and not killed and disk is "print 'QUIT'\n", report

  # A save held for a minute stands for one that hangs: the quit gives up on
  # it after SAVE_LIMIT and exits, saying which sketch it left unsaved. The
  # time is checked as well, because the SIGTERM does not bound this one: run
  # against the unbounded quit (Claude, 2026-10-06), the child outlived it and
  # exited 0 once the save landed. SIGTERM only starts a quit, and will-quit
  # holds it: a windowless Electron 44 app whose will-quit always holds logs
  # before-quit and will-quit on SIGTERM and stays up; a second signal kills
  # it (measured by a Claude reviewer, 2026-10-06). Hence the SIGKILL.
  {code, said, took, killed, report} = await quitChild 60000
  check 'the app quits with a save that hangs, after SAVE_LIMIT, and says so',
    code is 0 and not killed and took < 30000 and said.some((line) -> /will-quit: still saving .*quit-edit\.coffee/.test line), report

  # --- line endings ------------------------------------------------------------

  # Robert, 2026-10-05: line endings follow the platform. A sketch keeps the
  # endings it has, whoever wrote them, and one with none yet takes the
  # platform's (main's writeSketch). Each check below pretends to be the
  # platform whose endings the sketch does not have (`newline.forced`), so
  # keeping them is told apart from following the platform.
  {newline}  = t.paths
  NATIVE_EOL = if process.platform is 'win32' then '\r\n' else '\n'
  crlf       = (text) -> text.replace /\n/g, '\r\n'
  endsName   = 'line-endings'
  endsAt     = path.join t.paths.sketches, "#{endsName}.coffee"
  freshName  = 'line-endings-new'
  freshAt    = path.join t.paths.sketches, "#{freshName}.coffee"

  # Every sketch:changed the test page is sent, raw: the echo of a save is
  # otherwise invisible, being ignored, and an outside write has to have
  # come and gone before an edit, or its late read could revert the edit
  # (the stale-echo window AGENTS.md records as still open).
  await js "window.heardChanges = []; beans.onChanged((change) => window.heardChanges?.push(change)); return true"
  listen = -> js "window.heardChanges = []; return true"
  heard  = (name, bytes) -> until_ -> js """
    return heardChanges.some((change) => change.name === #{JSON.stringify name} && change.text === #{JSON.stringify bytes})
  """
  outside = (bytes) ->
    await listen()
    await fsp.writeFile endsAt, bytes, 'utf8'
    heard endsName, bytes
  openEnds = (bytes) ->
    await js "await Editor.load('scratch'); return true"
    await outside bytes
    await js "await Editor.load('#{endsName}'); return true"
  saveAs = (text) ->
    await setDoc text
    await js "await Editor.save(); return true"
    fsp.readFile endsAt, 'utf8'

  try
    # A CRLF sketch edited here stays CRLF, pretending to be Linux. Its echo
    # comes back CRLF and must not read as an outside edit: the editor holds
    # \n, so it compares the echo in that form.
    newline.forced = '\n'
    await openEnds crlf "print 'ONE'\nprint 'TWO'\n"
    await clearConsole()
    await listen()
    disk  = await saveAs "print 'ONE'\nprint 'TWO'\nprint 'THREE'\n"
    check 'an edited CRLF sketch is saved CRLF, on a platform whose own are LF',
      disk is crlf("print 'ONE'\nprint 'TWO'\nprint 'THREE'\n"), JSON.stringify disk
    echo  = await heard endsName, crlf "print 'ONE'\nprint 'TWO'\nprint 'THREE'\n"
    await quiet()
    after = await js "return {doc: Editor.all(), dirty: Editor.dirty(), said: document.getElementById('console').textContent}"
    check 'the echo of our own CRLF save is not taken for an outside edit',
      echo and after.doc is "print 'ONE'\nprint 'TWO'\nprint 'THREE'\n" and not after.dirty and not after.said.includes('reloaded'),
      JSON.stringify {echo, after}

    # And an LF sketch stays LF, pretending to be Windows. K4's always-LF
    # saves pass this too; the check above is the one they fail. This one
    # fails a save that keeps CRLF where it finds it and otherwise follows
    # the platform, which every other check here lets through.
    newline.forced = '\r\n'
    await openEnds "print 'ONE'\nprint 'TWO'\n"
    disk = await saveAs "print 'ONE'\nprint 'TWO'\nprint 'THREE'\n"
    check 'an edited LF sketch is saved LF, on a platform whose own are CRLF',
      disk is "print 'ONE'\nprint 'TWO'\nprint 'THREE'\n", JSON.stringify disk

    # The player's own editor rewrote it with other endings and nothing else.
    # The editor ignores that change -- its text is the same -- but the next
    # save keeps what the player's editor wrote.
    newline.forced = '\n'
    await openEnds "print 'ONE'\n"
    await outside crlf "print 'ONE'\n"
    disk = await saveAs "print 'ONE'\nprint 'TWO'\n"
    check 'a sketch whose endings were changed outside is saved with the new ones',
      disk is crlf("print 'ONE'\nprint 'TWO'\n"), JSON.stringify disk

    # Mixed: most lines win, over the platform's, and the console says so
    # once -- the save after is of a file that agrees with itself.
    newline.forced = '\n'
    await openEnds "print 'ONE'\r\nprint 'TWO'\r\nprint 'THREE'\n"
    await clearConsole()
    first  = await saveAs "print 'ONE'\nprint 'TWO'\nprint 'THREE'\nprint 'FOUR'\n"
    second = await saveAs "print 'ONE'\nprint 'TWO'\nprint 'THREE'\nprint 'FOUR'\nprint 'FIVE'\n"
    await quiet()
    said   = await consoleText()
    notes  = said.split('mixed line endings').length - 1
    check 'a sketch with mixed endings is saved with most lines\' ending, and the console says so once',
      first is crlf("print 'ONE'\nprint 'TWO'\nprint 'THREE'\nprint 'FOUR'\n") and
      second is crlf("print 'ONE'\nprint 'TWO'\nprint 'THREE'\nprint 'FOUR'\nprint 'FIVE'\n") and
      notes is 1 and said.includes("#{endsName}.coffee had mixed line endings (2 CRLF, 1 LF); saved with CRLF throughout"),
      JSON.stringify {first, second, said}

    # A sketch the app makes is empty, and has no endings until its first
    # save: that one takes the platform's. Pretending to be Windows, and then
    # as this machine is -- which on the Windows CI job is the real thing.
    makeFresh = (forced) ->
      newline.forced = forced
      await js "await Editor.load('scratch'); return true"
      await fsp.rm freshAt, force: yes
      await listen()
      created = await js "return (await beans.create('#{freshName}')).created"
      await heard freshName, ''
      await js "await Editor.load('#{freshName}'); return true"
      await setDoc "print 'A'\nprint 'B'\n"
      await js "await Editor.save(); return true"
      {created, disk: await fsp.readFile freshAt, 'utf8'}
    pretended = await makeFresh '\r\n'
    asIs      = await makeFresh null
    check 'a new sketch is saved CRLF where the platform is Windows, and with this platform\'s own endings here',
      pretended.created and pretended.disk is crlf("print 'A'\nprint 'B'\n") and
      asIs.created and asIs.disk is "print 'A'\nprint 'B'\n".replace(/\n/g, NATIVE_EOL),
      JSON.stringify {pretended, asIs, platform: process.platform}

    # U1's flush, as the page goes away, writes the same endings a save does:
    # main converts every write, not only sketch:write's.
    newline.forced = '\n'
    await js "await Editor.load('scratch'); return true"
    await fsp.writeFile endsAt, crlf("print 'OLD'\n"), 'utf8'
    page    = await openPage endsName
    pending = await edit page, "print 'FLUSHED'\nprint 'CRLF'\n"
    await reload page
    await onSketch page, endsName
    page.destroy()
    disk = await fsp.readFile endsAt, 'utf8'
    check 'an edit flushed at View > Reload keeps the sketch\'s CRLF endings',
      pending and disk is crlf("print 'FLUSHED'\nprint 'CRLF'\n"), "pending #{pending} disk #{JSON.stringify disk}"

    # A save asks the file for its endings, and a file that will not be read
    # must not fail the save: the rename needs only the folder. A holder on
    # Windows refuses the read for a moment, and that is waited out as the
    # rename's refusals are (main's `faults` stands in for the holder).
    newline.forced = '\n'
    await openEnds crlf "print 'ONE'\n"
    faults.windows    = yes
    faults.unreadable = 3
    disk  = await saveAs "print 'ONE'\nprint 'HELD'\n"
    left  = faults.unreadable
    faults.windows    = no
    faults.unreadable = 0
    dirty = await js "return Editor.dirty()"
    check 'a save whose read of the sketch is refused a few times waits it out, and keeps the CRLF',
      disk is crlf("print 'ONE'\nprint 'HELD'\n") and left is 0 and not dirty,
      "disk #{JSON.stringify disk} refusals left #{left} dirty #{dirty}"

    # A refusal that lasts leaves the endings unknown, and the save takes the
    # platform's. Mode 000 is one Linux and macOS make for real; Windows has
    # no unreadable mode that a rename would still replace, and root reads
    # through it.
    unless process.platform is 'win32' or process.getuid() is 0
      newline.forced = '\n'
      await openEnds crlf "print 'ONE'\n"
      await fsp.chmod endsAt, 0o000
      await clearConsole()
      await setDoc "print 'ONE'\nprint 'LOCKED'\n"
      await js "await Editor.save(); return true"
      await quiet()
      said  = await consoleText()
      dirty = await js "return Editor.dirty()"
      disk  = await fsp.readFile(endsAt, 'utf8').catch (error) -> error.code
      check 'a sketch that cannot be read is still saved, with the platform\'s endings',
        disk is "print 'ONE'\nprint 'LOCKED'\n" and not dirty and not said.includes('could not save'),
        JSON.stringify {disk, dirty, said}
      # Told only to the terminal until the integration review of
      # 2026-10-06: the player saw the watcher's "could not read" and took
      # it that nothing was saved.
      check 'and the console says the endings could not be read, and which it saved with',
        said.includes("could not read #{endsName}.coffee for its line endings (EACCES); saving it with LF"),
        JSON.stringify said
  finally
    newline.forced    = null
    faults.windows    = no
    faults.unreadable = 0
    page?.destroy() unless page?.isDestroyed()
    await js "window.heardChanges = null; await Editor.load('scratch'); return true"
    await fsp.rm endsAt,  force: yes
    await fsp.rm freshAt, force: yes
