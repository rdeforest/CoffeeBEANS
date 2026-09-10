H = LAYOUT.HEADER

sab = new SharedArrayBuffer LAYOUT.TOTAL_BYTES
i32 = new Int32Array  sab, 0, LAYOUT.HEADER_WORDS
u32 = new Uint32Array sab

params   = new URLSearchParams location.search
canvas   = document.getElementById 'screen'
stage    = document.getElementById 'stage'
output   = document.getElementById 'console'
statusEl = document.getElementById 'status'
picker   = document.getElementById 'sketch'
meter    = document.getElementById 'meter'
main     = document.getElementById 'main'
ctx      = canvas.getContext '2d'

surface = width: 0, height: 0, imageData: null, view32: null

setStatus = (text) -> statusEl.textContent = text

say = (text, kind = '') ->
  line = document.createElement 'div'
  line.className   = kind
  line.textContent = text
  output.appendChild line
  output.scrollTop = output.scrollHeight

# --- input ------------------------------------------------------------------

# Keys reach the sketch only while the screen has focus, so the editor keeps
# its own keystrokes. Click the screen to hand them over; click back to
# take them away.
setKey = (code, isDown) ->
  index = KEYTABLE.index[code]
  return false unless index?
  word = index >>> 5
  mask = 1 << (index & 31)
  if isDown
    Atomics.or  i32, H.KEYS     + word, mask
    Atomics.or  i32, H.KEYS_HIT + word, mask
  else
    Atomics.and i32, H.KEYS     + word, ~mask
  true

clearKeys = ->
  Atomics.store i32, H.KEYS + word, 0 for word in [0...LAYOUT.KEY_WORDS]
  undefined

toScreen = (event) ->
  rect = canvas.getBoundingClientRect()
  return null unless rect.width and rect.height and surface.width
  clamp = (value, limit) -> Math.min Math.max(Math.floor(value), 0), limit - 1
  x: clamp ((event.clientX - rect.left) / rect.width  * surface.width),  surface.width
  y: clamp ((event.clientY - rect.top)  / rect.height * surface.height), surface.height

listenForInput = ->
  stage.tabIndex = 0

  stage.addEventListener 'keydown', (event) ->
    tracked = setKey event.code, yes
    # Leave modified keys alone -- those are app and system shortcuts.
    event.preventDefault() if tracked and not (event.ctrlKey or event.metaKey or event.altKey)
  stage.addEventListener 'keyup', (event) -> setKey event.code, no
  # A key still held when focus leaves would otherwise stay down forever.
  stage.addEventListener 'blur', clearKeys

  stage.addEventListener 'pointermove', (event) ->
    position = toScreen event
    return unless position
    Atomics.store i32, H.MOUSE_X, position.x
    Atomics.store i32, H.MOUSE_Y, position.y

  buttons = (event) -> Atomics.store i32, H.MOUSE_BTN, event.buttons
  stage.addEventListener 'pointerdown', (event) -> stage.focus(); buttons event
  stage.addEventListener 'pointerup',   buttons
  stage.addEventListener 'pointerleave', -> Atomics.store i32, H.MOUSE_BTN, 0
  stage.addEventListener 'contextmenu', (event) -> event.preventDefault()
  stage.addEventListener 'wheel', ((event) ->
    Atomics.add i32, H.MOUSE_WHEEL, Math.round event.deltaY
    event.preventDefault()
  ), passive: no
  undefined

# --- panels -----------------------------------------------------------------

# Sizes are CSS variables so the grid stays declarative; dragging a splitter
# only ever writes a number. Detaching and scripting these is future work --
# see NOTES.md.
PANELS =
  editor:
    variable: '--editor-w'
    min:      220
    room:     -> window.innerWidth  - 240
    measure:  (event) -> window.innerWidth  - event.clientX
    current:  -> document.getElementById('editor').getBoundingClientRect().width
  console:
    variable: '--console-h'
    min:      32
    room:     -> window.innerHeight - 260
    measure:  (event) -> window.innerHeight - event.clientY
    current:  -> document.getElementById('console').getBoundingClientRect().height

applyPanel = (name, px) ->
  panel = PANELS[name]
  size  = Math.round Math.min Math.max(px, panel.min), Math.max panel.min, panel.room()
  document.documentElement.style.setProperty panel.variable, "#{size}px"
  resize()
  size

setPanel = (name, px) ->
  size = applyPanel name, px
  localStorage.setItem "panel.#{name}", size
  size

# A window that got smaller has to give the panel back some room, but that is
# not a preference the user expressed, so it must not overwrite the stored one.
reflowPanels = ->
  for name, panel of PANELS
    size = panel.current()
    applyPanel name, size if size > panel.room()
  undefined

dragPanel = (splitter, name) ->
  {measure} = PANELS[name]
  splitter.addEventListener 'pointerdown', (event) ->
    event.preventDefault()
    splitter.setPointerCapture event.pointerId
    splitter.classList.add 'dragging'
    onMove = (moved) -> setPanel name, measure moved
    onUp   = ->
      splitter.classList.remove 'dragging'
      splitter.removeEventListener 'pointermove', onMove
      splitter.removeEventListener 'pointerup',   onUp
    splitter.addEventListener 'pointermove', onMove
    splitter.addEventListener 'pointerup',   onUp

restorePanels = ->
  for name of PANELS
    stored = Number localStorage.getItem "panel.#{name}"
    setPanel name, stored if stored > 0
  undefined

globalThis.Panels =
  set:     setPanel
  size:    (name) -> PANELS[name].current()
  names:   -> Object.keys PANELS

showHelp = (topic) ->
  sections = HELP.match topic
  unless sections.length
    say "no help for \"#{topic}\" -- try :help with no topic", 'err'
    return
  entries = [].concat (section.lines for section in sections)...
  width   = Math.max (syntax.length for [syntax] in entries)...
  top     = output.scrollHeight
  for section in sections
    say section.title, 'help-head'
    for [syntax, description] in section.lines
      say "  #{syntax.padEnd width}   #{description}", 'help'
  output.scrollTop = top          # land on the first section, not the last
  undefined

# --- presentation -----------------------------------------------------------

resize = ->
  {width, height} = surface
  return unless width and height
  scale = Math.max 1, Math.floor Math.min stage.clientWidth / width, stage.clientHeight / height
  canvas.style.width  = "#{width  * scale}px"
  canvas.style.height = "#{height * scale}px"

reshape = (width, height) ->
  return if width is surface.width and height is surface.height
  canvas.width      = width
  canvas.height     = height
  surface.width     = width
  surface.height    = height
  surface.imageData = ctx.createImageData width, height
  surface.view32    = new Uint32Array surface.imageData.data.buffer
  resize()

present = (index) ->
  base = LAYOUT.bufferWords index
  surface.view32.set u32.subarray base, base + surface.width * surface.height
  ctx.putImageData surface.imageData, 0, 0

# You cannot tune what you cannot see. fps is how often a frame reaches the
# screen; the second number is what the sketch spent building one, which is
# the half a sketch can do something about.
meterState = presented: 0, shown: 0, since: performance.now()

updateMeter = ->
  meterState.presented += 1
  span = performance.now() - meterState.since
  return if span < 500
  fps    = (meterState.presented - meterState.shown) * 1000 / span
  cost   = Atomics.load(i32, H.SKETCH_US) / 1000
  sketch = if cost > 0 then "   sketch #{cost.toFixed 1}ms" else ''
  meter.textContent = "#{fps.toFixed 0}fps#{sketch}"
  meterState.shown = meterState.presented
  meterState.since = performance.now()
  undefined

frame = ->
  requestAnimationFrame frame
  reshape Atomics.load(i32, H.WIDTH), Atomics.load(i32, H.HEIGHT)
  return unless surface.width

  if Atomics.load(i32, H.SWAP) is 1
    # Only double buffering flips. Single buffered, a swap means no more than
    # "wait until this frame is on screen" -- flipping would hand the sketch
    # the other buffer and its drawing would vanish.
    if Atomics.load(i32, H.DOUBLE) is 1
      Atomics.store i32, H.FRONT, 1 - Atomics.load i32, H.FRONT
    present Atomics.load i32, H.FRONT
    Atomics.store  i32, H.SWAP, 0
    Atomics.notify i32, H.SWAP
  else
    present Atomics.load i32, H.FRONT

  Atomics.add i32, H.FRAME, 1
  updateMeter()

# --- worker lifecycle -------------------------------------------------------

worker  = null
pending = null

messages =
  ready: ->
    setStatus 'ready'
    return unless pending
    send pending
    pending = null
  print:   (data) -> say data.text
  done:    -> setStatus 'ready'
  stopped: -> say '*** stopped ***', 'sys'; setStatus 'ready'
  error:   (data) ->
    where = if data.line? then " (line #{data.line})" else ''
    say "#{data.stage}#{where}: #{data.message}", 'err'
    setStatus 'error'

send = ({source, name}) ->
  setStatus 'running'
  worker.postMessage {type: 'run', source, name}

start = (thenRun = null) ->
  worker?.terminate()
  Atomics.store i32, H.INTERRUPT, 0
  Atomics.store i32, H.SKETCH_US, 0
  Atomics.store i32, H.SWAP,      0
  Atomics.store i32, H.FRONT,     0
  pending = thenRun
  worker  = new Worker '/src/renderer/worker-boot.js'
  worker.onmessage = ({data}) -> messages[data.type]? data
  worker.postMessage type: 'boot', sab: sab
  setStatus 'booting'

stop = ->
  Atomics.store  i32, H.INTERRUPT, 1
  Atomics.store  i32, H.SWAP,      0
  Atomics.notify i32, H.SWAP
  deadline = performance.now() + 250
  check = ->
    return unless statusEl.textContent is 'running'
    if performance.now() > deadline
      say '*** no yield point, worker terminated (state lost) ***', 'sys'
      start()
    else
      requestAnimationFrame check
  requestAnimationFrame check

# --- editor wiring ----------------------------------------------------------

runSource = (source, name) ->
  return start {source, name} unless worker
  send {source, name}

Editor.mount document.getElementById('editor'),
  onRun:      (source, name) -> runSource source, "#{name} (region)"
  onRunAll:   (source, name) -> runSource source, name
  onRestart:  (source, name) -> say '*** restarting worker ***', 'sys'; start {source, name}
  onExternal: (name) -> say "reloaded #{name}.coffee from disk", 'sys'
  onHelp:     showHelp

selectSketch = (name) ->
  await Editor.load name
  picker.value = name
  Editor.focus()

fillPicker = ->
  names = await beans.list()
  picker.innerHTML = ''
  for name in names
    option = document.createElement 'option'
    option.value = option.textContent = name
    picker.appendChild option
  names

toggleEditor = ->
  main.classList.toggle 'solo'
  resize()

document.getElementById('run').onclick     = -> Editor.runRegion()
document.getElementById('runAll').onclick  = -> runSource Editor.all(), Editor.name()
document.getElementById('restart').onclick = -> start {source: Editor.all(), name: Editor.name()}
document.getElementById('stop').onclick    = stop
document.getElementById('toggle').onclick  = toggleEditor
picker.onchange = -> selectSketch picker.value

window.addEventListener 'keydown', (event) ->
  return unless event.ctrlKey
  handled =
    'e':      toggleEditor
    '.':      stop
  if handled[event.key]
    event.preventDefault()
    handled[event.key]()

listenForInput()

dragPanel document.getElementById('splitEditor'),  'editor'
dragPanel document.getElementById('splitConsole'), 'console'

new ResizeObserver(resize).observe stage
window.addEventListener 'resize', reflowPanels

# --- boot -------------------------------------------------------------------

do ->
  # The worker and the present loop come up first and unconditionally. If
  # loading a sketch goes wrong, you should still get a window that draws
  # and a console that tells you what happened.
  restorePanels()
  start()
  frame()
  say 'CoffeeBEANS 0.0.1  --  Ctrl-Enter runs the block under the cursor, :help for the rest', 'sys'

  try
    names  = await fillPicker()
    wanted = params.get 'sketch'
    if wanted and wanted not in names
      say "no sketch named \"#{wanted}\" -- opening #{names[0]}", 'err'
      wanted = null
    if names.length
      await selectSketch (wanted ? names[0])
    else
      say "no sketches in your data folder (File -> Open Data Folder)", 'err'
  catch error
    say "startup: #{error.message}", 'err'

  if params.has 'help'
    topic = params.get 'help'
    showHelp (if topic and topic isnt '1' then topic else undefined)
  stage.focus() if params.has 'focus'
  if params.has 'run'
    setTimeout (-> runSource Editor.all(), Editor.name()), 300
  if params.get 'stopAt'
    setTimeout stop, Number params.get 'stopAt'
