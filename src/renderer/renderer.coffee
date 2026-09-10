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

new ResizeObserver(resize).observe stage

# --- boot -------------------------------------------------------------------

do ->
  names = await fillPicker()
  await selectSketch (params.get('sketch') ? names[0])
  start()
  frame()
  say 'CoffeeBEANS 0.0.1  --  Ctrl-Enter runs the block under the cursor, :help for the rest', 'sys'
  if params.has 'help'
    topic = params.get 'help'
    showHelp (if topic and topic isnt '1' then topic else undefined)
  if params.has 'run'
    setTimeout (-> runSource Editor.all(), Editor.name()), 300
  if params.get 'stopAt'
    setTimeout stop, Number params.get 'stopAt'
