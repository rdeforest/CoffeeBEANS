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

ipcMain.handle 'settings:vim', -> settings.vim is true

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

# A sketch's name is its path under sketches/ without the extension, always
# with forward slashes, so `challenges/ocean` means the same thing on every
# platform and in every place a name is typed or shown.
sketchFile = (name) ->
  file = path.resolve SKETCHES, "#{name}.coffee"
  throw new Error "sketch outside sketches/: #{name}" unless file.startsWith SKETCHES + path.sep
  file

sketchName = (file) ->
  path.relative(SKETCHES, file).split(path.sep).join('/').replace /\.coffee$/, ''

ipcMain.handle 'sketch:read',  (event, name)       -> fsp.readFile sketchFile(name), 'utf8'
# Written beside the target and renamed into place. writeFile truncates
# first, so a watcher firing mid-write could read an empty file, hand it to
# the editor, and have the editor autosave the emptiness back. A rename is
# atomic: a reader sees the old file or the new one. The temp name must not
# end in .coffee or the watcher would pick it up as a sketch of its own.
ipcMain.handle 'sketch:write', (event, name, text) ->
  file    = sketchFile name
  await fsp.mkdir path.dirname(file), recursive: yes     # :e sub/new makes sub/
  staging = path.join path.dirname(file), ".#{path.basename file}.saving"
  await fsp.writeFile staging, text, 'utf8'
  await fsp.rename staging, file
  true
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
  (sketchName path.join(SKETCHES, entry) for entry in entries when entry.endsWith '.coffee').sort()

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
  root = await fsp.realpath SKETCHES
  file = await fsp.realpath filePaths[0]
  return {outside: filePaths[0]} unless file.startsWith root + path.sep
  {name: sketchName path.join SKETCHES, path.relative root, file}

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

  reload = (name) ->
    clearTimeout timers[name]
    timers[name] = setTimeout (->
      return if win.isDestroyed()
      try
        text = await fsp.readFile sketchFile(name), 'utf8'
        win.webContents.send 'sketch:changed', {name, text}
      catch error
        console.log "watch: #{name}: #{error.message}"
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
      return reload sketchName entry if filename.endsWith '.coffee'
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
  mapFirst = hidden and process.platform is 'linux'
  win.once 'ready-to-show', ->
    if mapFirst
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
        failures = await require('../../test/suite')(win, {root: ROOT, data: DATA, sketches: SKETCHES})
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
  protocol.handle 'app', serve
  installMenu()
  createWindow()
  app.on 'activate', -> createWindow() unless BrowserWindow.getAllWindows().length

app.on 'window-all-closed', -> app.quit()
