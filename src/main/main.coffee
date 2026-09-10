{app, BrowserWindow, Menu, protocol, net, ipcMain, shell} = require 'electron'
fs   = require 'fs'
fsp  = require 'fs/promises'
os   = require 'os'
path = require 'path'
url  = require 'url'

ROOT     = path.join __dirname, '..', '..'
EXAMPLES = path.join ROOT, 'examples'

# The user's work lives outside the repo, so running the app never collides
# with working on it. BEANS_DATA_HOME is how the test suite gets its own.
dataHome = ->
  return path.resolve process.env.BEANS_DATA_HOME if process.env.BEANS_DATA_HOME
  share = process.env.XDG_DATA_HOME or path.join os.homedir(), '.local', 'share'
  path.join share, 'coffeebeans'

DATA     = dataHome()
SKETCHES = path.join DATA, 'sketches'

# Seeded only when there is no data directory at all -- an existing one with
# an empty sketches/ belongs to the user, who may have deleted them on purpose.
prepareDataHome = ->
  fresh = not fs.existsSync DATA
  await fsp.mkdir SKETCHES, recursive: yes
  return unless fresh
  for entry in await fsp.readdir EXAMPLES when entry.endsWith '.coffee'
    await fsp.copyFile path.join(EXAMPLES, entry), path.join SKETCHES, entry
  console.log "seeded #{SKETCHES} from examples/"
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
  return new Response 'forbidden', status: 403 unless file.startsWith ROOT

  source  = await net.fetch url.pathToFileURL(file).toString()
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
ipcMain.handle 'sketch:write', (event, name, text) -> await fsp.writeFile sketchFile(name), text, 'utf8'; true
ipcMain.handle 'beans:paths', -> {data: DATA, sketches: SKETCHES}
ipcMain.handle 'sketch:list',  ->
  entries = await fsp.readdir SKETCHES
  (entry.replace /\.coffee$/, '' for entry in entries when entry.endsWith '.coffee').sort()

# Watch the directory rather than the file: vim writes via a temp file and a
# rename, which leaves a file watch pointing at a dead inode.
watchSketches = (win) ->
  timers = {}
  fs.watch SKETCHES, (event, filename) ->
    return unless filename?.endsWith '.coffee'
    name = filename.replace /\.coffee$/, ''
    clearTimeout timers[name]
    timers[name] = setTimeout (->
      try
        text = await fsp.readFile sketchFile(name), 'utf8'
        win.webContents.send 'sketch:changed', {name, text}
      catch error
        console.log "watch: #{name}: #{error.message}"
    ), 60

capture = (win) ->
  fs    = require 'fs'
  delays = (Number n for n in (process.env.BEANS_CAPTURE ? '').split(',') when n)
  return unless delays.length
  for delay, i in delays
    do (delay, i) ->
      setTimeout (->
        image = await win.webContents.capturePage()
        fs.writeFileSync "tmp/capture-#{i}.png", image.toPNG()
        console.log "captured #{i} at #{delay}ms"
        app.quit() if i is delays.length - 1
      ), delay

createWindow = ->
  win = new BrowserWindow
    width:           1280
    height:          860
    backgroundColor: '#0b0b0d'
    webPreferences:
      contextIsolation: yes
      nodeIntegration:  no
      preload:          path.join __dirname, 'preload.js'
  query = process.env.BEANS_QUERY ? ''
  win.loadURL "app://beans/src/renderer/index.html#{query}"
  win.webContents.openDevTools mode: 'detach' if process.env.BEANS_DEVTOOLS
  win.webContents.on 'console-message', (event) ->
    console.log "[renderer] #{event.message}"
  capture win
  watchSketches win
  if process.env.BEANS_TEST
    win.webContents.once 'did-finish-load', ->
      failures = await require('../../test/integration')(win, {root: ROOT, data: DATA, sketches: SKETCHES})
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
