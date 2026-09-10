{app, BrowserWindow, protocol, net, ipcMain} = require 'electron'
fs   = require 'fs'
fsp  = require 'fs/promises'
path = require 'path'
url  = require 'url'

ROOT     = path.join __dirname, '..', '..'
SKETCHES = path.join ROOT, 'sketches'

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
      failures = await require('../../test/integration')(win, ROOT)
      process.exitCode = if failures then 1 else 0
      app.quit()
  win

app.whenReady().then ->
  protocol.handle 'app', serve
  createWindow()
  app.on 'activate', -> createWindow() unless BrowserWindow.getAllWindows().length

app.on 'window-all-closed', -> app.quit()
