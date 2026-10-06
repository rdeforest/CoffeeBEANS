{app, BrowserWindow, Menu, dialog, nativeImage, protocol, net, ipcMain, shell} = require 'electron'
crypto = require 'crypto'
fs   = require 'fs'
fsp  = require 'fs/promises'
os   = require 'os'
path = require 'path'
url  = require 'url'

ROOT     = path.join __dirname, '..', '..'
EXAMPLES = path.join ROOT, 'examples'

# The user's work lives outside the repo, so running the app never collides
# with working on it. BEANS_DATA_HOME is how the test suite gets its own.
data     = require './data'
debugSketches = require './debugger'
DATA     = data.home()
SKETCHES = path.join DATA, 'sketches'

# The renderer's localStorage (panel sizes, the last sketch opened) lives in
# userData. A run with its own data home gets its own, or a test run leaves
# the real app reopening a test fixture.
app.setPath 'userData', path.join DATA, 'electron' if process.env.BEANS_DATA_HOME

SETTINGS     = path.join DATA, 'settings.json'
Settings     = require './settings'
settings     = Settings.read SETTINGS
saveSettings = -> Settings.save SETTINGS, settings

ipcMain.handle 'settings:vim',      -> settings.vim is true
ipcMain.handle 'settings:warnCase', -> settings.warnCase isnt false

prepareDataHome = ->
  {added} = await data.prepare DATA, EXAMPLES
  console.log "added to #{SKETCHES}: #{added.join ', '}" if added.length
  undefined

MIME =
  '.html':   'text/html'
  '.js':     'text/javascript'
  '.coffee': 'text/plain'
  '.css':    'text/css'
  '.json':   'application/json'

# SharedArrayBuffer requires cross-origin isolation, which file:// cannot
# provide. A privileged custom scheme can.
protocol.registerSchemesAsPrivileged [
  scheme: 'app'
  privileges:
    standard:        yes
    secure:          yes
    supportFetchAPI: yes
    corsEnabled:     yes
]

serve = (request) ->
  {pathname} = new URL request.url
  file       = path.join ROOT, decodeURIComponent pathname
  return new Response 'forbidden', status: 403 unless file is ROOT or file.startsWith ROOT + path.sep

  try
    source = await net.fetch url.pathToFileURL(file).toString()
  catch error
    # Rejecting here gives the renderer an opaque network error. A 404 says
    # which path it was, which is the whole question when a module fails to
    # load and the worker never comes up.
    return new Response "not found: #{pathname}", status: 404
  headers = new Headers
  headers.set 'Content-Type', MIME[path.extname file] ? 'application/octet-stream'
  headers.set 'Cross-Origin-Opener-Policy',   'same-origin'
  headers.set 'Cross-Origin-Embedder-Policy', 'require-corp'
  headers.set 'Cross-Origin-Resource-Policy', 'same-origin'
  new Response source.body, {status: source.status, headers}

# Whether names that differ only in case are one sketch. Robert decided
# (2026-10-05) that where the disk folds case, so does the app. The disk is
# asked, not process.platform (decided by Claude, 2026-10-05): macOS can be
# formatted case-sensitive, Windows can mark a folder so, and Linux can mount
# a disk that folds. `probed` is set once sketches/ exists; `forced` is the
# suite's, which cannot make this Linux disk fold and so has main behave as
# if it did. Only the suite is handed this object (createWindow), as with
# `faults` below.
folding = {probed: no, forced: no}
folds   = -> folding.probed or folding.forced

# Where the disk folds, foo.COFFEE is foo's file too.
EXTENSION = {true: /\.coffee$/i, false: /\.coffee$/}
extension = -> EXTENSION[folds()]

# A sketch's name is its path under sketches/ without the extension, always
# with forward slashes, so `challenges/ocean` means the same thing on every
# platform and in every place a name is typed or shown.
sketchFile = (name) ->
  file = path.resolve SKETCHES, "#{name}.coffee"
  throw new Error "sketch outside sketches/: #{name}" unless file.startsWith SKETCHES + path.sep
  file

sketchName = (file) ->
  path.relative(SKETCHES, file).split(path.sep).join('/').replace extension(), ''

# A name with `.` and `..` walked and doubled slashes made single,
# so `./foo` is `foo` everywhere: as the editor's name, the watcher's, the
# save queue's. Throws for a name that leads out of sketches/.
canonical = (name) -> sketchName sketchFile name

flip      = (c)    -> if c is c.toLowerCase() then c.toUpperCase() else c.toLowerCase()
flipCase  = (text) -> (flip c for c in text).join ''
hasLetter = (text) -> flipCase(text) isnt text

# Whether `dir` finds its entry `name` again under `name` with its case
# swapped. lstat, so a sibling symlink spelled that way is not taken for
# the entry itself.
sameUnderFlip = (dir, name) ->
  twin = fs.lstatSync path.join(dir, flipCase name), bigint: yes, throwIfNoEntry: no
  self = fs.lstatSync path.join(dir, name), bigint: yes
  twin? and twin.ino is self.ino and twin.dev is self.dev

# Asked of an entry inside sketches/ (examples are seeded first, so there
# usually is one), which gets sketches/'s own answer where that differs from
# its parent's: a disk mounted at sketches/, ext4 casefold set on it, a
# Windows per-folder flag. With nothing in it whose name has a letter, the
# folder's own name is asked of its parent instead, and those cases get the
# parent's answer. Through realpath, so a sketches/ linked to another disk
# asks that disk. Subfolders are assumed to fold as sketches/ does; ext4 and
# Windows both hand a new folder its parent's setting, but one changed by
# hand afterwards is not noticed.
probeFolding = (dir) ->
  real  = fs.realpathSync dir
  child = fs.readdirSync(real).find hasLetter
  return sameUnderFlip real, child if child?
  return sameUnderFlip path.dirname(real), path.basename(real) if hasLetter path.basename real
  process.platform in ['darwin', 'win32']    # no letters to ask with

# A key two spellings of one sketch share. toLowerCase is near enough to what
# NTFS and APFS fold, though not exact for a handful of characters (the
# Kelvin sign, dotted I).
caseKey = (text) -> if folds() then text.toLowerCase() else text

entriesOf = (dir) ->
  try
    await fsp.readdir dir
  catch error
    throw error unless error.code in ['ENOENT', 'ENOTDIR']
    []

# A name as the disk spells it. Where the disk folds, `Foo` reads and writes
# foo.coffee anyway; carrying the disk's spelling on keeps one sketch one
# name -- in the title, the editor, the watcher -- and keeps a save from
# renaming onto the file under the spelling it was asked for, which may
# leave it spelled that way (not verified on macOS or Windows). Whatever part
# of the name is not on disk yet stays as asked. The extension is not part
# of the name, so foo.COFFEE is opened, and saved, as foo.coffee.
spelled = (name) ->
  name = canonical name
  return name unless folds()
  parts = "#{name}.coffee".split '/'
  dir   = SKETCHES
  for part, i in parts
    entries = await entriesOf dir
    exact   = entries.find (entry) -> entry is part
    match   = exact ? entries.find (entry) -> caseKey(entry) is caseKey part
    break unless match
    parts[i] = match
    dir      = path.join dir, match
  parts.join('/').replace extension(), ''

# The sketch a typed name means, and whether there is one yet. :e and
# ?sketch= ask this rather than looking for the name in sketch:list, which
# cannot know whether the disk folds: `:e Foo` with foo.coffee present
# missed it, "created" Foo, and on a disk that folds wrote '' over foo.coffee.
ipcMain.handle 'sketch:find', (event, asked) ->
  name = await spelled asked
  {name, exists: fs.statSync(sketchFile(name), throwIfNoEntry: no)?}

# A new, empty sketch -- unless one has appeared since sketch:find said
# there was none, which the disk decides ('wx'), not a look beforehand.
# Then that one is opened as it is.
ipcMain.handle 'sketch:create', (event, asked) ->
  file = sketchFile asked
  await fsp.mkdir path.dirname(file), recursive: yes     # :e sub/new makes sub/
  try
    await fsp.writeFile file, '', flag: 'wx'
    {name: canonical(asked), created: yes}
  catch error
    throw error unless error.code is 'EEXIST'
    {name: await spelled(asked), created: no}

ipcMain.handle 'sketch:read',  (event, name)       -> fsp.readFile sketchFile(await spelled name), 'utf8'
# Written beside the target and renamed into place. writeFile truncates
# first, so a watcher firing mid-write could read an empty file, hand it to
# the editor, and have the editor autosave the emptiness back. A rename is
# atomic: a reader sees the old file or the new one. The temp name must not
# end in .coffee or the watcher would pick it up as a sketch of its own.
writeSketch = (file, text) ->
  await fsp.mkdir path.dirname(file), recursive: yes     # :e sub/new makes sub/
  staging = path.join path.dirname(file), ".#{path.basename file}.saving"
  await fsp.writeFile staging, text, 'utf8'
  await renameOnto staging, file
  true

# Windows refuses a rename while something else has either file open: Defender
# or the indexer reading the staging file just written, or the target. EPERM
# on the CI's windows-latest runner, 2026-10-05. That lasts milliseconds, so
# the rename is tried again, backing off, for about 1.3s in all. Not longer:
# switching sketches waits on the outgoing save, and a save that still fails
# goes to the renderer as an error, and the next edit saves again anyway.
# graceful-fs waits up to a minute for the same thing, which suits npm, not
# an editor. Elsewhere these codes mean a real refusal, so no retry there.
RENAME_WAITS = [10, 20, 40, 80, 160, 320, 640]
TRANSIENT    = ['EPERM', 'EACCES', 'EBUSY']

# The suite's way to hold a save in flight, or to have a rename refused the
# way Windows refuses it, neither of which it can arrange from outside. Only
# the suite is handed this object (createWindow); nothing else touches it, so
# outside a test run every field stays at its zero and the hook does nothing.
faults = {slow: 0, refuse: 0, windows: no}

rename = (staging, file) ->
  if faults.slow
    await new Promise (resolve) -> setTimeout resolve, faults.slow
  if faults.refuse > 0
    faults.refuse -= 1
    throw Object.assign new Error("EPERM: refused by the suite, rename '#{staging}'"), code: 'EPERM'
  fsp.rename staging, file

renameOnto = (staging, file) ->
  for pause in RENAME_WAITS
    try
      return await rename staging, file
    catch error
      throw error unless (process.platform is 'win32' or faults.windows) and error.code in TRANSIENT
      console.log "sketch:write: #{error.code} renaming onto #{file}, again in #{pause}ms"
      await new Promise (resolve) -> setTimeout resolve, pause
  await rename staging, file

# Saves of one sketch run one at a time, in the order they were asked for.
# Overlapping, they shared the staging file: one save's rename carried off
# another's file (ENOENT, 11 of 12 overlapping saves when Claude reproduced
# it on Linux, 2026-10-05), and the disk kept whichever finished last rather
# than the last one asked for. Each waits for the one ahead however that one
# ended; its failure has already gone to its own caller.
#
# The watcher reads both maps: `saving` holds a file's chain while any save
# of it is in flight, `begun` counts the saves ever asked for (see reload in
# watchSketches). Both are keyed by caseKey, so two spellings of one sketch
# queue together rather than racing for the one staging file a folding disk
# gives them. The spelling is looked up inside the queue: looked up first, a
# later save could overtake an earlier one while each waited on its readdir.
saving = new Map
begun  = new Map

ipcMain.handle 'sketch:write', (event, name, text) ->
  key   = caseKey sketchFile name
  write = -> writeSketch sketchFile(await spelled name), text
  begun.set key, (begun.get(key) ? 0) + 1
  ahead = saving.get(key) ? Promise.resolve()
  done  = ahead.then write, write
  saving.set key, done
  forget = -> saving.delete key if saving.get(key) is done
  done.then forget, forget
  done
ASSETS = path.join DATA, 'assets'

# Cached on first fetch, and thereafter never touched again. A sketch shown
# on a stage with bad wifi, or six months after the URL rotted, still runs.
cachedBytes = (url) ->
  await fsp.mkdir ASSETS, recursive: yes
  key  = crypto.createHash('sha256').update(url).digest('hex')[0...32]
  file = path.join ASSETS, key
  try
    return await fsp.readFile file
  catch error
    throw error unless error.code is 'ENOENT'

  response = await net.fetch url
  throw new Error "#{response.status} #{response.statusText} for #{url}" unless response.ok
  bytes = Buffer.from await response.arrayBuffer()
  await fsp.writeFile file, bytes
  bytes

localBytes = (where) ->
  file = path.resolve DATA, where
  throw new Error "outside the data folder: #{where}" unless file.startsWith DATA + path.sep
  await fsp.readFile file

ipcMain.handle 'image:load', (event, url) ->
  bytes = if /^https?:/i.test url then await cachedBytes url else await localBytes url
  image = nativeImage.createFromBuffer bytes
  {width, height} = image.getSize()
  throw new Error "not an image we can decode: #{url}" unless width and height
  {width, height, data: image.toBitmap()}

ipcMain.handle 'beans:paths', -> {data: DATA, sketches: SKETCHES, assets: ASSETS}
ipcMain.handle 'sketch:list',  ->
  entries = await fsp.readdir SKETCHES, recursive: yes
  (sketchName path.join(SKETCHES, entry) for entry in entries when extension().test entry).sort()

# The native picker, so the header does not carry a list that stops being
# usable past a dozen sketches. It opens in sketches/ and answers a name; a
# file picked from anywhere else is refused rather than opened, because every
# other path a name travels -- read, write, the watcher -- is confined there.
ipcMain.handle 'sketch:pick', (event) ->
  win = BrowserWindow.fromWebContents event.sender
  {canceled, filePaths} = await dialog.showOpenDialog win,
    title:       'Open a sketch'
    defaultPath: SKETCHES
    properties:  ['openFile']
    filters:     [{name: 'CoffeeScript', extensions: ['coffee']}]
  return {canceled: yes} if canceled or not filePaths.length
  # Compared as real paths: the dialog may hand back /private/tmp for /tmp.
  # Spelled as the disk spells it, as :e's names are, in case a dialog hands
  # back the case it was typed in.
  root = await fsp.realpath SKETCHES
  file = await fsp.realpath filePaths[0]
  return {outside: filePaths[0]} unless file.startsWith root + path.sep
  {name: await spelled sketchName path.join SKETCHES, path.relative root, file}

# Watch directories, never files: a file replaced by renaming a new one into
# place leaves a file watch on the dead inode. Vim saves that way by default,
# and so does sketch:write above.
#
# So one plain watch per folder, walked by hand, and not fs.watch's
# `recursive` option. On Linux Node implements `recursive` itself by watching
# every file's inode -- exactly the watch this comment warns against -- so
# from the first time the app saved a sketch, no outside change to it was
# seen again. Reproduced on Node 24.20 and 26.8 by Claude, 2026-10-04; macOS
# never showed it because its recursive watch is native.
watchSketches = (win) ->
  timers   = {}
  watchers = new Map

  # Never read a sketch while a save of it is in flight. The editor sets
  # lastWritten to the new text before the write lands, and takes any text
  # that is neither that nor its own as an outside edit. A read that caught
  # the disk still holding the old text -- the echo of the save before, or
  # any event during the staging write and rename -- arrived as exactly that,
  # and the editor went back to the old text until the new save's own echo
  # put it right: long enough for /eval to run the previous buffer. That was
  # every Windows CI failure in the 2026-10-05 overnight session (traced by
  # a Claude CI investigator), where the rename retry stretches the window.
  # So a read waits for the file's saves to settle and then looks again, and
  # a read that a save began under is thrown away for a fresh one. An outside
  # edit still arrives, only after our own writes are on disk.
  #
  # That closes the window only for saves main already knows about. The
  # renderer sets lastWritten and then sends sketch:write, so a read that
  # completes and is sent while that write is still crossing IPC carries the
  # old text and still reverts the editor until the echo. Not taken: a write
  # sequence number the renderer sends and main echoes in sketch:changed, so
  # applyExternal could ignore a read older than its latest write.
  #
  # Sent under the disk's spelling, which is the one the editor opened it by,
  # whatever spelling the event carried.
  reload = (heard) ->
    timer = caseKey heard
    clearTimeout timers[timer]
    timers[timer] = setTimeout (->
      return if win.isDestroyed()
      key   = caseKey sketchFile heard
      again = -> reload heard
      return saving.get(key).then again, again if saving.has key
      before = begun.get key
      try
        name = await spelled heard
        text = await fsp.readFile sketchFile(name), 'utf8'
      catch error
        return console.log "watch: #{heard}: #{error.message}"
      return again() unless begun.get(key) is before
      win.webContents.send 'sketch:changed', {name, text} unless win.isDestroyed()
    ), 60

  forget = (dir) ->
    watchers.get(dir)?.close()
    watchers.delete dir

  watchTree = (dir) ->
    return if watchers.has dir
    try
      watcher  = fs.watch dir
      children = fs.readdirSync dir, withFileTypes: yes
    catch error
      watcher?.close()
      console.log "watch: #{dir}: #{error.message}"
      return
    watchers.set dir, watcher
    # Without this, deleting a watched folder while the app runs throws out
    # of the main process and takes the window with it.
    watcher.on 'error', (error) ->
      console.log "watch stopped: #{dir}: #{error.message}"
      forget dir
    watcher.on 'change', (event, filename) ->
      return unless filename?
      entry = path.join dir, filename
      return reload sketchName entry if extension().test filename
      # Anything else may be a folder arriving, which needs its own watch, or
      # one leaving, whose watch should go with it.
      fsp.stat(entry)
        .then (stats) -> watchTree entry if stats.isDirectory()
        .catch (error) ->
          if error.code is 'ENOENT' then forget entry
          else console.log "watch: #{entry}: #{error.message}"
    watchTree path.join dir, child.name for child in children when child.isDirectory()
    undefined

  watchTree SKETCHES
  # The watchers outlive the window otherwise, and sending to a destroyed
  # webContents throws out of a timer nobody is catching.
  win.on 'closed', ->
    clearTimeout timer for name, timer of timers
    watchers.forEach (watcher) -> watcher.close()
    watchers.clear()

SHOTS = path.join ROOT, 'tmp'

capture = (win) ->
  delays = (Number n for n in (process.env.BEANS_CAPTURE ? '').split(',') when n)
  return unless delays.length
  fs.mkdirSync SHOTS, recursive: yes      # gitignored, so a fresh clone has none
  for delay, i in delays
    do (delay, i) ->
      setTimeout (->
        # capturePage rejects with UnknownVizError when the window is not
        # being composited -- occluded, minimised, or simply not frontmost.
        # That is the developer's desktop, not the app, and it must not
        # leave the process running forever. Reported apart from the write,
        # which fails for entirely different reasons and used to be blamed
        # on the window being invisible.
        try
          image = await win.webContents.capturePage()
        catch error
          console.log "capture #{i} failed: #{error.message} (is the window visible?)"
        if image
          shot = path.join SHOTS, "capture-#{i}.png"
          try
            fs.writeFileSync shot, image.toPNG()
            console.log "captured #{i} at #{delay}ms to #{shot}"
          catch error
            console.log "could not write #{shot}: #{error.message}"
        app.quit() if i is delays.length - 1
      ), delay

createWindow = ->
  # A test run has no business taking the screen while you are working in
  # another window. Never shown is also the strongest form of background there
  # is, so a suite that passes this way is one that proves a sketch keeps
  # running when you alt-tab away from it. BEANS_CAPTURE needs a composited
  # window to photograph, and BEANS_SHOW is for watching a run go by.
  hidden = process.env.BEANS_TEST and not (process.env.BEANS_CAPTURE or process.env.BEANS_SHOW)

  win = new BrowserWindow
    show:            not hidden
    width:           1280
    height:          860
    backgroundColor: '#0b0b0d'
    webPreferences:
      contextIsolation: yes
      nodeIntegration:  no
      preload:          path.join __dirname, 'preload.js'
      # Chromium stops animation frames for a window it is not compositing --
      # behind another window, minimised, on another Space. The present loop
      # is the only thing that clears the swap flag, so without this a sketch
      # parked in buffer.swap never wakes up and the app looks wedged until
      # you Stop it. Alt-tabbing away from a running sketch must not do that.
      backgroundThrottling: no
      # Sound starts with the app, not with a click: a sketch that beeps on
      # its first line should be heard.
      autoplayPolicy: 'no-user-gesture-required'
  # Nor any business making noise. The audio thread still runs -- the sound
  # tests read what it reports, not what reaches the speakers -- but nothing
  # comes out unless you asked to watch the run, when hearing it helps.
  win.webContents.setAudioMuted yes if process.env.BEANS_TEST and not process.env.BEANS_SHOW
  query = process.env.BEANS_QUERY ? ''
  win.loadURL "app://beans/src/renderer/index.html#{query}"
  win.webContents.openDevTools mode: 'detach' if process.env.BEANS_DEVTOOLS
  win.webContents.on 'console-message', (event) ->
    console.log "[renderer] #{event.message}"
  # The sketch worker lives in the renderer's process, so a crash in either
  # takes the page with it and leaves a black window that says nothing. Come
  # back up and say what happened. A test run lets it lie: a suite that
  # reloaded past a crash could go on to pass.
  win.webContents.on 'render-process-gone', (event, {reason}) ->
    console.error "renderer gone: #{reason}"
    return if reason is 'clean-exit' or process.env.BEANS_TEST or win.isDestroyed()
    win.loadURL "app://beans/src/renderer/index.html?crashed=#{encodeURIComponent reason}"
  # BEANS_MINIMIZE is the way to exercise backgroundThrottling from a test run
  # on macOS: there a hidden window is not throttled and a minimised one is,
  # and with throttling on every buffer.swap in the suite hangs until its
  # deadline.
  #
  # Linux needs more. A never-shown window there that draws -- and this one
  # draws every tick -- gets about one animation frame a second whatever
  # backgroundThrottling says, which failed the frame-timing checks on every
  # hidden run. A window that has been mapped once keeps full rate even
  # minimised, so a hidden Linux run shows itself inactive (no focus taken)
  # and then minimises.
  #
  # The beat between is not decoration. `show` seems to fire when the map is
  # asked for, not when it has happened, and an iconify that overtakes the
  # map leaves a window that was never mapped. Minimised straight from
  # `show`, the timing parts passed two runs in three; 300ms later, eight in
  # eight (Claude, 2026-10-04). The race is the likeliest reading of that,
  # not a proven one -- if the timing parts start failing hidden again, this
  # is the first place to look. See AGENTS.md, Platform facts.
  #
  # Windows needs more still. On the GitHub Actions runner the frame-timing
  # checks failed never shown (the meter read 1fps) and failed shown then
  # minimised, and passed with the window shown and left alone (Claude,
  # 2026-10-05). So a hidden Windows run shows itself inactive and stays.
  mapFirst  = hidden and process.platform in ['linux', 'win32']
  iconAfter = process.platform is 'linux'
  win.once 'ready-to-show', ->
    if mapFirst
      if iconAfter
        win.once 'show', -> setTimeout (-> win.minimize() unless win.isDestroyed()), 300
      win.showInactive()
    else if process.env.BEANS_MINIMIZE
      win.minimize()
  capture win
  watchSketches win
  debugSketches win
  if process.env.BEANS_TEST
    win.webContents.once 'did-finish-load', ->
      try
        failures = await require('../../test/suite')(win, {root: ROOT, data: DATA, sketches: SKETCHES, faults, folding})
      catch error
        # A suite that throws must still bring the app down, or the run hangs.
        console.error "suite crashed: #{error.stack ? error}"
        failures = 1
      # app.exit, not process.exitCode then app.quit: Electron's quit path
      # ignores exitCode, so a red suite reported success to the shell
      # (checked by Claude, 2026-10-04). Nothing here hooks before-quit or
      # will-quit, which are what app.exit skips.
      app.exit if failures then 1 else 0
  win

installMenu = ->
  Menu.setApplicationMenu Menu.buildFromTemplate [
    label: 'File'
    submenu: [
      {
        # Handed to the renderer, which owns the console that says why a
        # pick was refused.
        label:       'Open Sketch…'
        accelerator: 'CmdOrCtrl+O'
        click: (item, win) -> win?.webContents.send 'sketch:open'
      }
      {
        label:       'Open Data Folder'
        accelerator: 'CmdOrCtrl+Shift+D'
        click: ->
          problem = await shell.openPath DATA
          console.log "openPath: #{problem}" if problem
      }
      {type: 'separator'}
      {role: 'quit'}
    ]
  ,
    label: 'Edit'
    # Deliberately no undo/redo: those roles drive the native edit stack,
    # and CodeMirror keeps its own history, behind its own undo keys (or
    # vim's u and Ctrl-r).
    submenu: [
      {role: 'cut'}, {role: 'copy'}, {role: 'paste'}, {role: 'selectAll'}
      {type: 'separator'}
      {
        # Electron flips `checked` before calling this. Every window is told,
        # not just the focused one: there may be none focused.
        id:      'vim'
        label:   'Vim Keys'
        type:    'checkbox'
        checked: settings.vim is true
        click: (item) ->
          settings.vim = item.checked
          saveSettings()
          win.webContents.send 'settings:vim', item.checked for win in BrowserWindow.getAllWindows()
      }
      {
        # On unless unticked: a sketch opened under another spelling says so
        # in the console. The renderer asks each time, so nobody is told.
        id:      'warnCase'
        label:   'Warn About Name Case'
        type:    'checkbox'
        checked: settings.warnCase isnt false
        click: (item) ->
          settings.warnCase = item.checked
          saveSettings()
      }
    ]
  ,
    label: 'View'
    submenu: [
      {role: 'reload'}, {role: 'toggleDevTools'}
      {type: 'separator'}
      {role: 'resetZoom'}, {role: 'zoomIn'}, {role: 'zoomOut'}
      {type: 'separator'}
      {role: 'togglefullscreen'}
    ]
  ]

app.whenReady().then ->
  await prepareDataHome()
  folding.probed = probeFolding SKETCHES
  protocol.handle 'app', serve
  installMenu()
  createWindow()
  app.on 'activate', -> createWindow() unless BrowserWindow.getAllWindows().length

app.on 'window-all-closed', -> app.quit()
