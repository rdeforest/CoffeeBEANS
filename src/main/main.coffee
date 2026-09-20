{app, BrowserWindow, Menu, nativeImage, protocol, net, ipcMain, shell} = require 'electron'
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
DATA     = data.home()
SKETCHES = path.join DATA, 'sketches'

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

sketchFile = (name) ->
  file = path.join SKETCHES, "#{path.basename name}.coffee"
  throw new Error "sketch outside sketches/: #{name}" unless file.startsWith SKETCHES + path.sep
  file

ipcMain.handle 'sketch:read',  (event, name)       -> fsp.readFile sketchFile(name), 'utf8'
# Written beside the target and renamed into place. writeFile truncates
# first, so a watcher firing mid-write could read an empty file, hand it to
# the editor, and have the editor autosave the emptiness back. A rename is
# atomic: a reader sees the old file or the new one. The temp name must not
# end in .coffee or the watcher would pick it up as a sketch of its own.
ipcMain.handle 'sketch:write', (event, name, text) ->
  file    = sketchFile name
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
  entries = await fsp.readdir SKETCHES
  (entry.replace /\.coffee$/, '' for entry in entries when entry.endsWith '.coffee').sort()

# Watch the directory rather than the file: vim writes via a temp file and a
# rename, which leaves a file watch pointing at a dead inode.
watchSketches = (win) ->
  timers  = {}
  watcher = fs.watch SKETCHES
  # Without this, deleting the sketches directory while the app runs throws
  # out of the main process and takes the window with it.
  watcher.on 'error', (error) ->
    console.log "watch stopped: #{error.message}"
    watcher.close()
  # The watcher outlives the window otherwise, and sending to a destroyed
  # webContents throws out of a timer nobody is catching.
  win.on 'closed', ->
    clearTimeout timer for name, timer of timers
    watcher.close()
  watcher.on 'change', (event, filename) ->
    return unless filename?.endsWith '.coffee'
    name = filename.replace /\.coffee$/, ''
    clearTimeout timers[name]
    timers[name] = setTimeout (->
      return if win.isDestroyed()
      try
        text = await fsp.readFile sketchFile(name), 'utf8'
        win.webContents.send 'sketch:changed', {name, text}
      catch error
        console.log "watch: #{name}: #{error.message}"
    ), 60

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
  query = process.env.BEANS_QUERY ? ''
  win.loadURL "app://beans/src/renderer/index.html#{query}"
  win.webContents.openDevTools mode: 'detach' if process.env.BEANS_DEVTOOLS
  win.webContents.on 'console-message', (event) ->
    console.log "[renderer] #{event.message}"
  # The only way to exercise backgroundThrottling from a test run: a hidden
  # window is not throttled, a minimised one is. With throttling on, this
  # makes every buffer.swap in the suite hang until its deadline.
  win.once 'ready-to-show', -> win.minimize() if process.env.BEANS_MINIMIZE
  capture win
  watchSketches win
  if process.env.BEANS_TEST
    win.webContents.once 'did-finish-load', ->
      try
        failures = await require('../../test/suite')(win, {root: ROOT, data: DATA, sketches: SKETCHES})
      catch error
        # A suite that throws must still bring the app down, or the run hangs.
        console.error "suite crashed: #{error.stack ? error}"
        failures = 1
      process.exitCode = if failures then 1 else 0
      app.quit()
  win

installMenu = ->
  Menu.setApplicationMenu Menu.buildFromTemplate [
    label: 'File'
    submenu: [
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
    # and CodeMirror keeps its own history. Use vim's u and Ctrl-r.
    submenu: [
      {role: 'cut'}, {role: 'copy'}, {role: 'paste'}, {role: 'selectAll'}
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
