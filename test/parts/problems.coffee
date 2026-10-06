# Failures nobody asked about -- a rejection in main nobody caught, a
# settings file that will not read or save, a file of the app's own that
# will not load, a page's last save, a folder the watcher cannot watch -- said
# in the console, where a player looks, and not only on a terminal a player
# never sees. The audit behind these is docs/research/unhandled-exceptions.md
# (Claude, 2026-10-06).

fsp             = require 'fs/promises'
path            = require 'path'
{BrowserWindow} = require 'electron'
Settings        = require '../../src/main/settings'

# Main has dealt with every rejection made before this resolves: Node reports
# unhandled ones once the microtasks run out, ahead of the next turn.
nextTurn = -> new Promise (resolve) -> setImmediate resolve

# How many times `text` appears in `shown`.
countIn = (shown, text) -> shown.split(text).length - 1

module.exports = (t) ->
  {check, js, waitFor, freshPage, consoleText, vimKeys, wait, paths} = t
  {unserved, listening, loadPage, sayProblem, held, faults, refuseNavigation} = paths

  # What a promise gave, or `timed out`: a check here that hangs would hold
  # the suite lock every other run is queued on.
  within = (ms, promise) -> Promise.race [promise, wait(ms).then -> 'timed out']

  # A rejection in main that nothing catches. Before, the terminal had a
  # warning and the window nothing at all.
  Promise.reject new Error 'problems: nobody caught this'
  said = await waitFor "return document.getElementById('console').textContent.includes('nobody caught this')"
  shown = await consoleText()
  check 'an unhandled rejection in main is said in the window console, once',
    said and countIn(shown, 'main: problems: nobody caught this') is 1, JSON.stringify shown

  # A settings file that will not save -- here its staging file is a folder --
  # costs the choice at the next launch, and says so now.
  staging = path.join paths.data, '.settings.json.saving'
  await fsp.mkdir staging
  try
    await vimKeys yes
    unsaved = await waitFor "return document.getElementById('console').textContent.includes('could not save')"
    shown   = await consoleText()
  finally
    await fsp.rm staging, recursive: yes, force: yes
    await vimKeys no
  check 'a settings file that will not save is said in the console',
    unsaved and shown.includes(path.join paths.data, 'settings.json') and shown.includes('lasts until CoffeeBEANS quits'),
    JSON.stringify shown

  # One that will not read is handed to whoever asked; a launch hands it to
  # the console through the same path as the two above.
  broken = path.join paths.data, 'settings-unreadable.json'
  await fsp.writeFile broken, '{"vim": tr', 'utf8'
  heard = []
  read  = Settings.read broken, (text) -> heard.push text
  await fsp.rm broken
  check 'a settings file that will not read says why to whoever asked, and reads as every default',
    JSON.stringify(read) is '{}' and heard.length is 1 and heard[0].startsWith('settings: ') and heard[0].endsWith('using the defaults'),
    JSON.stringify heard

  # A file of the app's own that will not load. Before, the page compiled the
  # 404's body as CoffeeScript, threw before any listener was up, and sat
  # dark with an empty console.
  unserved.add '/src/renderer/help.coffee'
  try
    page = await freshPage """
      const shown = document.getElementById('console').textContent
      return shown.includes('could not start') && {shown, editor: typeof Editor}
    """, 5000
  finally
    unserved.delete '/src/renderer/help.coffee'
  check 'a file of the app that will not load is said in the console, and nothing after it runs',
    page and page.shown.includes('/src/renderer/help.coffee') and page.shown.includes('not found') and page.editor is 'undefined',
    JSON.stringify page

  # A load another overtakes -- View > Reload while the window comes up --
  # fails with ERR_ABORTED, which is no failure and must say nothing; with
  # rejections made visible, it said `main: ERR_ABORTED ...`. Any other
  # failure is said. Handed windows whose loads fail as Electron 44's do
  # (the shape measured by Claude, 2026-10-06): a real overtaken load is
  # not reported to did-fail-load, so the check could not tell it happened.
  failing = (code) ->
    loadURL: -> Promise.reject Object.assign new Error("#{code} (-3) loading 'app://beans/'"), {code}
  await loadPage failing('ERR_ABORTED'), ''
  await loadPage failing('ERR_FAILED'), ''
  await nextTurn()
  await waitFor "return document.getElementById('console').textContent.includes('could not load')"
  shown = await consoleText()
  check 'a window load overtaken by another says nothing; any other failed load is said',
    not shown.includes('ERR_ABORTED') and shown.includes('the window could not load: ERR_FAILED'),
    JSON.stringify shown[-200..]

  # The next checks take the test window off the list, as a reload or a
  # closed window would, so that the page each opens is the only one
  # listening, if any is.
  aside = (body) ->
    away = [listening...]
    listening.clear()
    try
      await body()
    finally
      # Not a page destroyed since: one the last check destroyed can still be
      # on the list when this one starts, and its 'destroyed' has come and
      # gone by now. Put back, it made every later problem throw out of
      # sayProblem, and Electron's box hang the run (Claude, 2026-10-06).
      listening.add contents for contents in away when not contents.isDestroyed()

  openPage = (query = '') ->
    page = new BrowserWindow
      show: no
      webPreferences:
        contextIsolation: yes
        nodeIntegration:  no
        preload:          path.join paths.root, 'src', 'main', 'preload.js'
    page.webContents.setAudioMuted yes
    # Destroyed here if it will not load: the caller's `finally` only has a
    # page to destroy once this returns one.
    try
      await page.loadURL "app://beans/src/renderer/index.html#{query}"
    catch error
      page.destroy()
      throw error
    page

  reload = (page) ->
    reloaded = new Promise (resolve) -> page.webContents.once 'did-finish-load', resolve
    page.webContents.reload()
    await reloaded

  # The console of a page that is up, once it shows `text` or `limit` is out.
  pageSays = (page, text, limit = 5000) ->
    deadline = Date.now() + limit
    loop
      shown = await page.webContents.executeJavaScript "document.getElementById('console').textContent"
      return shown if shown.includes(text) or Date.now() > deadline
      await wait 25

  waitIn = (page, probe, limit = 5000) ->
    deadline = Date.now() + limit
    loop
      seen = await page.webContents.executeJavaScript probe
      return seen if seen or Date.now() > deadline
      await wait 25

  listens = (page, limit = 5000) ->
    deadline = Date.now() + limit
    await wait 25 until listening.has(page.webContents) or Date.now() > deadline
    listening.has page.webContents

  # A page that has started loading another is not sent problems: they are
  # held, and the page that comes up says them, once. Without that the
  # problem went to the page on its way out, and was lost with it.
  await aside ->
    page = await openPage()
    try
      heard = await listens page
      leaving = new Promise (resolve) -> page.webContents.once 'did-start-loading', resolve
      landed  = new Promise (resolve) -> page.webContents.once 'did-finish-load', resolve
      page.webContents.reload()
      await leaving
      Promise.reject new Error 'problems: while the page reloaded'
      await nextTurn()
      await landed
      shown = await pageSays page, 'while the page reloaded'
      check 'a problem from while a page reloads is held, and said once by the page that comes up',
        heard and countIn(shown, 'main: problems: while the page reloaded') is 1, JSON.stringify shown[-200..]

    finally
      page.destroy()

  # And one whose renderer has died. Nothing reloads this page, as the test
  # window lets a crash lie (createWindow). It is a page of its own session,
  # so it cannot share the test window's renderer process -- the app's own
  # windows did, measured by Claude, 2026-10-06 -- and the crash cannot take
  # the suite down with it; it asks for problems as the preload lets any page.
  await aside ->
    page = new BrowserWindow
      show: no
      webPreferences:
        contextIsolation: yes
        nodeIntegration:  no
        partition:        'problems-crash'
        preload:          path.join paths.root, 'src', 'main', 'preload.js'
    try
      await page.loadURL 'data:text/html,<p>to be crashed</p>'
      asked  = await page.webContents.executeJavaScript "typeof beans === 'object' && (beans.onProblem(() => {}), true)"
      heard  = asked and await listens page
      tested = BrowserWindow.getAllWindows().find (other) -> other isnt page
      shared = page.webContents.getOSProcessId() is tested.webContents.getOSProcessId()
      unless shared
        gone = new Promise (resolve) -> page.webContents.once 'render-process-gone', resolve
        page.webContents.forcefullyCrashRenderer()
        await gone
        Promise.reject new Error 'problems: after the page crashed'
        await nextTurn()
        later = await freshPage """
          const shown = document.getElementById('console').textContent
          return shown.includes('after the page crashed') && shown
        """
      check 'a problem from after a page crashed is held for the next page, not sent to the dead one',
        heard and not shared and countIn("#{later}", 'main: problems: after the page crashed') is 1,
        JSON.stringify {heard, shared, later: "#{later}"[-200..]}
    finally
      page.destroy()

  # Held, they stop at `held`: a page whose loader failed never asks for
  # them. The rest are counted, and the count said with the first.
  await aside ->
    sayProblem "problems: held #{n}" for n in [1..held + 2]
    shown = await freshPage """
      const shown = document.getElementById('console').textContent
      return shown.includes('more problems') && shown
    """
  check "problems held while no page listens stop at #{held}, and the rest are counted",
    shown and countIn(shown, 'problems: held ') is held and shown.includes("problems: held #{held}") and
      not shown.includes("problems: held #{held + 1}") and shown.includes('main: 2 more problems, on the terminal only'),
    JSON.stringify "#{shown}"[-200..]

  # A page's last save (U1's sketch:flush) that fails as the page reloads.
  # Before, only the terminal heard; now the page that comes up says it. A
  # hundred refusals, so Windows' rename retry gives up too.
  sketch = 'problems-flush'
  file   = path.join paths.sketches, "#{sketch}.coffee"
  await fsp.writeFile file, "print 'OLD'\n", 'utf8'
  await aside ->
    page = await openPage "?sketch=#{sketch}"
    try
      opened  = await waitIn page, "typeof Editor !== 'undefined' && Editor.name() === '#{sketch}'"
      pending = await page.webContents.executeJavaScript """
        (() => { const v = Editor.view()
                 v.dispatch({ changes: { from: 0, to: v.state.doc.length, insert: "print 'NEW'\\n" } })
                 return Editor.dirty() })()
      """
      faults.refuse = 100
      await reload page
      faults.refuse = 0
      shown = await pageSays page, "could not save #{sketch}"
    finally
      faults.refuse = 0
      page.destroy()
      # And the staging file the refused rename left: writeSketch does not
      # clear it after a failure (see the audit).
      await fsp.rm path.join(paths.sketches, ".#{sketch}.coffee.saving"), force: yes
      await fsp.rm file, force: yes
    check 'a page\'s last save that fails as it reloads is said by the page that comes up, once',
      opened and pending and countIn(shown, "could not save #{sketch}") is 1, JSON.stringify shown[-200..]

  # A navigation the page itself starts -- a file dropped on the window
  # outside the editor, a link -- replaced the app with the file. Refused in
  # a page of its own, not the test window, so that a regression costs this
  # check and not the rest of the run. A refused navigation still starts
  # loading and stops, and the page must go on hearing main's problems.
  await aside ->
    page = await openPage()
    refuseNavigation page.webContents
    try
      heard   = await listens page
      refused = new Promise (resolve) -> page.webContents.once 'will-navigate', (event) -> resolve event.defaultPrevented
      stopped = new Promise (resolve) -> page.webContents.once 'did-stop-loading', resolve
      await page.webContents.executeJavaScript "location.href = '/src/renderer/help.coffee'; true"
      refused = await within 3000, refused
      await within 3000, stopped
      Promise.reject new Error 'problems: after a refused navigation'
      await nextTurn()
      # Caught, so that a page navigated away -- no console, no Editor -- fails
      # this check and says why, rather than ending the part.
      gave  = (error) -> "threw: #{error.message}"
      shown = await within 8000, pageSays(page, 'after a refused navigation').catch gave
      still = await within 3000, page.webContents.executeJavaScript('typeof Editor').catch gave
      check 'a navigation the page starts is refused, and the page stays the app and goes on hearing problems',
        heard and refused is true and still is 'object' and countIn("#{shown}", 'after a refused navigation') is 1,
        JSON.stringify {heard, refused, still, shown: "#{shown}"[-200..]}
    finally
      page.destroy()

  # A folder in sketches/ that cannot be watched: edits made to it outside
  # the app will not be seen, which was said only on the terminal. Made
  # unreadable with its mode, which Windows ignores, and root reads anyway.
  unless process.platform is 'win32' or process.getuid?() is 0
    locked = path.join paths.sketches, 'problems-locked'
    await fsp.mkdir locked, mode: 0
    try
      unseen = await waitFor "return document.getElementById('console').textContent.includes('problems-locked will not be seen')"
      shown  = await consoleText()
    finally
      await fsp.chmod locked, 0o755
      await fsp.rmdir locked
    check 'a folder in sketches/ that cannot be watched is said in the console',
      unseen and shown.includes('changes made outside CoffeeBEANS to'), JSON.stringify shown[-200..]

  # A sketch that will not read. That may pass -- Windows' EBUSY while
  # something else holds the file -- and every event reads it again, so it
  # is said once, and again only after a read of it has succeeded; before,
  # every event said its changes "will not be seen". Unreadable by its mode,
  # as above. A repeat goes to stdout only, so that is where the check looks
  # for the second failed read.
  unless process.platform is 'win32' or process.getuid?() is 0
    sketch  = 'problems-unreadable'
    file    = path.join paths.sketches, "#{sketch}.coffee"
    saying  = "could not read #{sketch}: "
    sayings = (count) -> waitFor "return document.getElementById('console').textContent.split(#{JSON.stringify saying}).length - 1 === #{count}"
    logged  = []
    log     = console.log
    console.log = (args...) ->
      logged.push args.join ' '
      log args...
    repeated = ->
      deadline = Date.now() + 3000
      await wait 25 until logged.some((line) -> line.startsWith "watch: #{sketch}: ") or Date.now() > deadline
      logged.some (line) -> line.startsWith "watch: #{sketch}: "
    await js "window.problemsRead = []; beans.onChanged((change) => window.problemsRead?.push(change.name)); return true"
    try
      await fsp.writeFile file, "print 'LOCKED'\n", mode: 0
      first  = await sayings 1
      await fsp.utimes file, new Date, new Date
      again  = await repeated()
      once   = await sayings 1
      await fsp.chmod file, 0o644
      read   = await waitFor "return problemsRead.includes('#{sketch}')"
      await fsp.chmod file, 0
      second = await sayings 2
      shown  = await consoleText()
    finally
      console.log = log
      await fsp.rm file, force: yes
    check 'a sketch that will not read is said once, not at every event, and again after a read has succeeded',
      first and again and once and read and second, JSON.stringify {first, again, once, read, second, shown: shown?[-300..]}

