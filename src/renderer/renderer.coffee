H = LAYOUT.HEADER

sab = new SharedArrayBuffer LAYOUT.TOTAL_BYTES
i32 = new Int32Array  sab, 0, LAYOUT.HEADER_WORDS
u32 = new Uint32Array sab

params   = new URLSearchParams location.search
canvas   = document.getElementById 'screen'
stage    = document.getElementById 'stage'
output   = document.getElementById 'console'
statusEl = document.getElementById 'status'
promptLine = document.getElementById 'promptLine'
meter    = document.getElementById 'meter'
linesEl  = document.getElementById 'lines'
main     = document.getElementById 'main'
ctx      = canvas.getContext '2d'

surface = width: 0, height: 0, imageData: null, view32: null

status = ''
# A paused sketch is a busy one: it is parked mid-frame, or mid-line, with the
# whole image in mid-flight. Anything that refuses to run while a sketch is
# running has to refuse while one is paused too.
#
# Two kinds of pause, named apart: `frame paused` holds at a buffer.swap and
# still answers the prompt through the worker; `line paused` is stopped in V8
# on a line the author wrote, and everything goes through the debugger.
PAUSED = ['frame paused', 'line paused']
BUSY   = ['running', PAUSED...]

setStatus = (text) ->
  status = text
  statusEl.textContent = text
  # Eval means "evaluate into the live worker", which a busy worker cannot
  # do, so the button says so. Run replaces the worker and always works.
  document.getElementById('evalRegion').disabled = text in BUSY
  document.getElementById('stepFrame').disabled  = text not in PAUSED
  document.getElementById('stepLine').disabled   = text not in BUSY
  holding = text in PAUSED
  # The audio clock stands still with the frame clock, so stepping does not
  # leave the music running on ahead of the picture.
  Atomics.store i32, H.SOUND_HOLD, if holding then 1 else 0
  hold    = document.getElementById 'pauseFrame'
  hold.textContent = if holding then '\u23E9' else '\u275A\u275A'
  hold.title       = if holding then 'Let the sketch run on (F8)' else 'Hold the sketch at its next frame'
  undefined

# --- console ----------------------------------------------------------------

# Lines are queued and appended in batches, as one fragment with one scroll.
# Appending per line forces a layout per line, which is quadratic in the
# size of the console and is what froze the window when a sketch printed
# every iteration of a loop. The cap keeps a runaway loop from eating memory.
# A timer rather than requestAnimationFrame, because an occluded window gets
# no animation frames and its console should still fill in.
CONSOLE_CAP   = 2000
CONSOLE_EVERY = 16
queued        = []
flushQueued   = null

flushConsole = ->
  clearTimeout flushQueued if flushQueued?
  flushQueued = null
  return unless queued.length
  # Whether lines were actually dropped, rather than whether the count happens
  # to equal the cap: a batch of exactly CONSOLE_CAP lines is not an overflow,
  # and replacing the scrollback on one throws away history nobody lost.
  overflowed = queued.length > CONSOLE_CAP
  queued = queued.slice -CONSOLE_CAP if overflowed
  fragment = document.createDocumentFragment()
  for {text, kind} in queued
    line = document.createElement 'div'
    line.className   = kind
    line.textContent = text
    fragment.appendChild line
  if overflowed
    output.replaceChildren fragment
  else
    output.appendChild fragment
    output.firstElementChild.remove() while output.childElementCount > CONSOLE_CAP
  queued = []
  output.scrollTop = output.scrollHeight

# Drained on a timer rather than an animation frame: an occluded window gets
# no animation frames, and its console should still fill in.
decoder   = new TextDecoder()
printRing = new Uint8Array sab, LAYOUT.printOffset, LAYOUT.PRINT_BYTES

# One buffer, grown as needed and handed back as a view of itself. A flood of
# console lines would otherwise allocate two arrays per line, on the thread
# that has to keep drawing the window.
taken = new Uint8Array 256

readRing = (position, length) ->
  taken = new Uint8Array length if taken.length < length
  first = Math.min length, LAYOUT.PRINT_BYTES - position
  taken.set printRing.subarray(position, position + first), 0
  taken.set printRing.subarray(0, length - first), first if first < length
  taken.subarray 0, length

drainPrints = ->
  head = Atomics.load i32, H.PRINT_HEAD
  tail = Atomics.load i32, H.PRINT_TAIL
  while tail isnt head
    size   = readRing tail, 4
    # Unsigned: a length with the top bit set would otherwise read as negative
    # and slip straight past the sanity check below.
    length = (size[0] | (size[1] << 8) | (size[2] << 16) | (size[3] << 24)) >>> 0
    # A length that cannot fit means the ring is not saying what we think it
    # is. Resynchronise rather than loop on garbage forever.
    if length > LAYOUT.PRINT_BYTES - 4
      say '*** console ring lost sync ***', 'err'
      tail = head
      break
    tail = (tail + 4) % LAYOUT.PRINT_BYTES
    say decoder.decode readRing tail, length
    tail = (tail + length) % LAYOUT.PRINT_BYTES
  Atomics.store i32, H.PRINT_TAIL, tail
  lost = Atomics.exchange i32, H.PRINT_LOST, 0
  say "*** #{lost} line#{if lost is 1 then '' else 's'} dropped, console ring full ***", 'sys' if lost > 0
  undefined

say = (text, kind = '') ->
  queued.push {text, kind}
  # Trim in chunks so a flood costs amortised constant time per line.
  queued.splice 0, queued.length - CONSOLE_CAP if queued.length > 2 * CONSOLE_CAP
  flushQueued ?= setTimeout flushConsole, CONSOLE_EVERY

# --- the prompt -------------------------------------------------------------

# A line typed here goes to the same worker the sketch runs in, so it sees
# what the sketch defined and the sketch sees what it defines. It goes through
# shared memory rather than postMessage, because the whole point is to ask a
# question of a sketch that is still running -- and a busy worker receives no
# messages. It answers at the sketch's next yield point.
#
# Not `history`: at this scope that is window.history, which is the first
# entry in the NOTES.md list of names that looked free.
askBytes  = new Uint8Array sab, LAYOUT.askOffset, LAYOUT.ASK_BYTES
entered   = []
enteredAt = 0

askLine = (source) ->
  return unless source.trim()
  say "> #{source}", 'echo'
  entered.push source
  enteredAt = entered.length
  return say '*** no worker -- press Run ***', 'err' unless worker
  # A sketch stopped in V8 cannot serve the shared-memory question -- nothing
  # runs to look at it -- so the line goes to the paused frame instead. That
  # is also the better answer: this call's `angle`, not the image's.
  return askPaused source if linePaused
  if Atomics.load(i32, H.ASK_STATE) isnt 0
    return say '*** still waiting on the last line ***', 'sys'
  bytes = new TextEncoder().encode source
  return say '*** line too long ***', 'err' if bytes.length > LAYOUT.ASK_BYTES
  askBytes.set bytes
  Atomics.store i32, H.ASK_LEN,   bytes.length
  Atomics.store i32, H.ASK_STATE, 1
  # An idle worker is parked in its event loop and will never look at shared
  # memory unaided. A busy one cannot receive this, and has already been told
  # where to look; the message then arrives to find nothing left to do.
  worker.postMessage type: 'ask'
  undefined

debugAsking = 0

askPaused = (source) ->
  debugAsking += 1
  try
    reply = await beans.debug.evaluate source
    return say '*** it moved on before it could answer ***', 'sys' unless reply
    showVars reply.pane if reply.pane and reply.pane.seq is linePaused
    say reply.text, reply.kind
  catch error
    say String(error.message ? error), 'err'
  finally
    debugAsking -= 1
  undefined

drainAsk = ->
  state = Atomics.load i32, H.ASK_STATE
  return unless state is 2 or state is 3
  # Copied out first: TextDecoder refuses a view onto shared memory, and the
  # state is cleared before we decode so a bad answer cannot wedge the prompt
  # by throwing here every 16ms forever.
  answer = new Uint8Array askBytes.subarray 0, Atomics.load i32, H.ASK_LEN
  Atomics.store i32, H.ASK_STATE, 0
  say decoder.decode(answer), (if state is 3 then 'err' else 'value')
  undefined

recall = (step) ->
  return unless entered.length
  enteredAt = Math.min entered.length, Math.max 0, enteredAt + step
  promptLine.value = entered[enteredAt] ? ''
  promptLine.setSelectionRange promptLine.value.length, promptLine.value.length

listenForPrompt = ->
  promptLine.addEventListener 'keydown', (event) ->
    return if event.ctrlKey or event.metaKey or event.altKey
    switch event.key
      when 'Enter'
        askLine promptLine.value
        promptLine.value = ''
        enteredAt = entered.length
      when 'ArrowUp'   then recall -1
      when 'ArrowDown' then recall  1
      else return
    event.preventDefault()

  # Clicking the log to read it should not cost you the prompt, but clicking
  # to select text should not steal it back either.
  document.getElementById('consolePane').addEventListener 'click', (event) ->
    return if event.target.closest '#vars'    # opening a value is not typing
    promptLine.focus() unless String(window.getSelection())
  undefined

# Is anything printed still on its way to the screen -- bytes the ring has not
# handed over, or lines queued but not yet in the DOM. Both are read in one
# go on the one thread that moves either, so a false here means everything a
# sketch printed is on screen. The suite waits on this instead of guessing an
# interval; a loaded machine makes every guess wrong eventually.
globalThis.Printing =
  pending: ->
    Atomics.load(i32, H.PRINT_HEAD) isnt Atomics.load(i32, H.PRINT_TAIL) or queued.length > 0

globalThis.Prompt =
  ask:     askLine
  pending: -> Atomics.load(i32, H.ASK_STATE) isnt 0 or debugAsking > 0
  entered: -> entered.slice()

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

# Blur only releases what is held -- a tap that happened is still a tap, and
# the sketch should see it. A restart is different: a new sketch must not
# inherit a key that was down, a hit nobody claimed, or wheel movement nobody
# read, all of which outlive the worker in shared memory.
clearInput = ->
  for word in [0...LAYOUT.KEY_WORDS]
    Atomics.store i32, H.KEYS     + word, 0
    Atomics.store i32, H.KEYS_HIT + word, 0
  Atomics.store i32, H.MOUSE_BTN,   0
  Atomics.store i32, H.MOUSE_WHEEL, 0
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
    current:  -> document.getElementById('consolePane').getBoundingClientRect().height

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
  flushConsole()
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

# You cannot tune what you cannot see. fps is how often a new frame reaches
# the screen -- counted where one is served, not on every animation frame,
# which would only measure the display's refresh rate. The second number is
# what the sketch spent building one, the half a sketch can do something
# about.
meterState = presented: 0, shown: 0, since: performance.now()

updateMeter = ->
  span = performance.now() - meterState.since
  return if span < 500
  fps    = (meterState.presented - meterState.shown) * 1000 / span
  cost   = Atomics.load(i32, H.SKETCH_US) / 1000
  sketch = if cost > 0 then "   sketch #{cost.toFixed 1}ms" else ''
  meter.textContent = "#{fps.toFixed 0}fps#{sketch}"
  meterState.shown = meterState.presented
  meterState.since = performance.now()
  undefined

# Pausing is not a new mechanism: it is declining to clear the swap. The
# worker asks for a frame, parks in doSwap's Atomics.wait, and stays there
# until we say the frame was presented. Which means a paused sketch is still
# awake every 100ms to check the interrupt flag and answer the prompt -- you
# can ask a stopped-mid-flight sketch what it is holding.
#
# It also means the same limitation Stop has: a sketch that never asks for a
# frame can never be paused. `loop` with no buffer.swap is not pausable, by
# construction.
paused   = no
stepOnce = no
resumeTo = 'ready'

pauseFrames = ->
  return if paused
  paused   = yes
  resumeTo = if status is 'line paused' then 'running' else status
  setStatus 'frame paused' unless linePaused

goFrames = ->
  return unless paused
  paused   = no
  stepOnce = no
  setStatus resumeTo unless linePaused

# From a line pause, a frame step runs on to the next frame boundary and holds
# there: the swap it reaches is simply not served.
stepFrame = ->
  if linePaused
    pauseFrames()
    return beans.debug.resume()
  pauseFrames() unless paused
  stepOnce = yes

# --- line stepping ----------------------------------------------------------

# The pause we are in, as the debugger numbered it, or null. The number is
# what makes an object id in the variables pane mean anything.
linePaused = null

# Suspend now, on whatever line is running. From a frame pause the swap has to
# be let go, or the sketch never reaches a line to stop on.
linePause = ->
  return unless status in ['running', 'frame paused']
  unless await beans.debug.pause()
    return say '*** could not pause -- is DevTools open? ***', 'sys'
  goFrames()

stepLine = ->
  if linePaused then beans.debug.step() else linePause()

continueAll = ->
  goFrames()
  beans.debug.resume() if linePaused

togglePause = ->
  if linePaused then continueAll() else linePause()

# The buffer arms the debugger: attached while it says `breakpoint` anywhere,
# let go when it does not. Nothing to remember to turn on, and nothing left
# on by mistake. Keystrokes are debounced; a run checks for itself, so it can
# never set off ahead of the attach it needs.
BREAKPOINT = /\bbreakpoint\b/
armedFor   = null
armTimer   = null
skipping   = no          # a Stop set breakpoints aside; the next run wants them

wantsDebug = (extra = '') -> BREAKPOINT.test(Editor.all()) or BREAKPOINT.test extra

syncDebug = (extra = '') ->
  clearTimeout armTimer
  want = wantsDebug extra
  armedFor = want
  skipping = no
  try
    await beans.debug.arm want
  catch error
    say "debugger: #{error.message ? error}", 'err'

watchBuffer = ->
  clearTimeout armTimer
  armTimer = setTimeout (->
    syncDebug() unless BREAKPOINT.test(Editor.all()) is armedFor
  ), 300

lineOnScreen = (where) ->
  return null unless where?.line? and where.name
  if where.name.replace(/ \(region\)$/, '') is Editor.name() then where.line else null

beans.debug.onEvent (event) ->
  switch event.type
    when 'paused'
      linePaused = event.seq
      setStatus 'line paused'
      Editor.showLine lineOnScreen event.where
      showVars event
    when 'resumed'
      linePaused = null
      Editor.showLine null
      hideVars()
      setStatus (if paused then 'frame paused' else 'running') if status is 'line paused'
    when 'problem'
      say event.text, 'err'
  undefined

globalThis.Stepping =
  pause:  pauseFrames
  step:   stepFrame
  go:     goFrames
  paused: -> paused
  line:   stepLine
  suspend: linePause
  resume: continueAll
  linePaused: -> linePaused
  armed:  -> armedFor

# --- the variables pane -----------------------------------------------------

# The paused frame's names, beside the console rather than printed into it,
# so a value can be watched changing as you step. Nothing here runs code: the
# debugger hands over previews, and a getter is shown as a getter.
varsEl = document.getElementById 'vars'

# What was open, by path, so a step does not fold everything back up; and
# what each row said last time, so a value that changed can say so.
expandedPaths = new Set
shownBefore   = new Map

varRow = (entry, path, depth) ->
  row = document.createElement 'div'
  row.className = 'var'
  row.style.paddingLeft = "#{depth * 1.1 + .4}rem"
  name = document.createElement 'span'
  name.className   = 'var-name'
  name.textContent = entry.name
  value = document.createElement 'span'
  value.className   = if entry.getter then 'var-value getter' else 'var-value'
  value.textContent = entry.text
  seen = shownBefore.get path
  value.classList.add 'changed' if seen? and seen isnt entry.text
  shownBefore.set path, entry.text
  row.append name, value
  holder = document.createElement 'div'
  holder.append row
  if entry.id
    row.classList.add 'openable'
    open = (expand) ->
      row.classList.toggle 'open', expand
      if expand
        expandedPaths.add path
        members = await beans.debug.members linePaused, entry.id
        return unless members and row.classList.contains 'open'
        children = document.createElement 'div'
        children.className = 'var-children'
        children.append (varRow member, "#{path}.#{member.name}", depth + 1 for member in members)...
        holder.append children
      else
        expandedPaths.delete path
        holder.querySelector('.var-children')?.remove()
    row.addEventListener 'click', -> open not row.classList.contains 'open'
    open yes if expandedPaths.has path
  holder

showVars = ({where, scopes}) ->
  head = document.createElement 'div'
  head.className = 'vars-head'
  place = if where?.line? then "line #{where.line}" else 'somewhere of ours'
  head.textContent = "#{where?.fn ? 'top level'} \u00b7 #{place}"
  sections = for scope in scopes
    section = document.createElement 'div'
    title = document.createElement 'div'
    title.className   = 'vars-title'
    title.textContent = scope.title
    section.append title
    if scope.vars.length
      section.append (varRow entry, "#{scope.title}/#{entry.name}", 0 for entry in scope.vars)...
    else
      none = document.createElement 'div'
      none.className   = 'var none'
      none.textContent = 'nothing here'
      section.append none
    section
  varsEl.replaceChildren head, sections...
  varsEl.hidden = no
  undefined

hideVars = ->
  varsEl.hidden = yes
  varsEl.replaceChildren()

# buffer.fps paces swaps, so the gate belongs on the branch that serves one.
# The worker stays parked until its frame is due, which is the whole point:
# a sketch asking for 30fps should spend the rest of the time asleep.
pacing = due: 0

framePending = ->
  fps = Atomics.load i32, H.FPS
  unless fps > 0
    pacing.due = 0
    return true
  now = performance.now()
  # A fresh cap, or one resumed after a long stall, starts counting from now.
  pacing.due = now if pacing.due is 0 or now - pacing.due > 1000
  return false if now < pacing.due
  pacing.due += 1000 / fps
  true

# Re-armed through `tick`, which is private to this closure rather than a
# name at file scope. Losing this loop is the worst failure the window has:
# nothing presents, and every buffer.swap after it blocks forever, with no
# error anywhere the user can see. It must not be one stray assignment away.
frame = do ->
  tick = ->
    requestAnimationFrame tick
    reshape Atomics.load(i32, H.WIDTH), Atomics.load(i32, H.HEIGHT)
    return unless surface.width

    # Paused, a frame is served only when a step asks for one, and a step does
    # not wait on the fps cap -- a frame you asked for by hand should arrive.
    # Note neither branch flips while paused: flipping without clearing the
    # swap would show the buffer the sketch is drawing into, and flicker.
    request = Atomics.load i32, H.SWAP
    serve   = request isnt 0 and (if paused then stepOnce else framePending())
    if serve
      stepOnce = no
      # Only a double-buffered swap flips. Single buffered, a swap means no
      # more than "wait until this frame is on screen" -- flipping would hand
      # the sketch the other buffer and its drawing would vanish. A wait
      # (request 2) never flips, whatever the mode.
      double = Atomics.load(i32, H.DOUBLE) is 1
      if double and request is 1
        Atomics.store i32, H.FRONT, 1 - Atomics.load i32, H.FRONT
      present Atomics.load i32, H.FRONT
      # Single buffered, what is on screen is what the sketch drew, so every
      # frame served is new; double buffered, only a flip brings one.
      meterState.presented += 1 if request is 1 or not double
      Atomics.store  i32, H.SWAP, 0
      Atomics.notify i32, H.SWAP
    else
      present Atomics.load i32, H.FRONT

    Atomics.add i32, H.FRAME, 1
    updateMeter()
  tick

# --- sound ------------------------------------------------------------------

# The audio thread gets the same shared memory as everyone else and reads its
# notes straight out of it; see sound-worklet.coffee. Compiled here and handed
# over as a blob, with the layout ahead of it, because a worklet loads one
# module and CoffeeScript is only on this side.
startSound = ->
  try
    audio   = new AudioContext latencyHint: 'interactive'
    sources = for part in ['/src/runtime/layout.coffee', '/src/renderer/sound-worklet.coffee']
      CoffeeScript.compile (await (await fetch part).text()), bare: no, filename: part
    url = URL.createObjectURL new Blob [sources.join '\n'], type: 'text/javascript'
    await audio.audioWorklet.addModule url
    voices = new AudioWorkletNode audio, 'beans-sound', numberOfInputs: 0, outputChannelCount: [2]
    voices.port.postMessage sab
    voices.connect audio.destination
    await audio.resume()
  catch error
    say "sound: #{error.message ? error}", 'err'
  undefined

# What the audio thread says it is doing. The suite reads this; nothing else
# needs to.
globalThis.Sound =
  started: -> Atomics.load i32, H.SOUND_STARTED
  peak:    -> Atomics.load(i32, H.SOUND_PEAK) / 1e6
  busy:    -> Atomics.load i32, H.SOUND_BUSY
  rate:    -> Atomics.load i32, H.SOUND_RATE

# --- worker lifecycle -------------------------------------------------------

worker  = null
pending = null

# Once the worker says it is idle there is nothing left for a Stop to unwind.
# Left raised, the flag makes every yield point reached from the prompt --
# buffer.swap, sound -- throw 'stopped' until the next run.
standDown = -> Atomics.store i32, H.INTERRUPT, 0

messages =
  ready: ->
    setStatus 'ready'
    return unless pending
    send pending
    pending = null
  load:    (data) -> answerLoad data.url
  done:    -> standDown(); setStatus 'ready'
  stopped: -> standDown(); say '*** stopped ***', 'sys'; setStatus 'ready'
  error:   (data) ->
    standDown()
    where = if data.line? then " (line #{data.line})" else ''
    say "#{data.stage}#{where}: #{data.message}", 'err'
    # The frames span more than one sketch only when a region defined a helper
    # another region calls; then say which sketch each frame belongs to.
    frames = data.frames ? []
    multi  = (new Set(step.name for step in frames)).size > 1
    # Not `for frame in frames`: at this scope that is the present loop, and
    # a comprehension variable would quietly reassign it. See NOTES.md.
    for step in frames
      site = step.fn ? 'top level'
      site = "#{site} in #{step.name}" if multi and step.name
      code = if step.text then ":  #{step.text}" else ''
      say "    at #{site}, line #{step.line ? '?'}#{code}", 'err'
    setStatus 'error'

# nativeImage hands back BGRA; the framebuffer wants RGBA. One swizzle here
# beats one per pixel at draw time.
answerLoad = (url) ->
  try
    image = await beans.image url
    pixels = image.width * image.height
    throw new Error "image too large: #{image.width}x#{image.height}" if pixels > LAYOUT.TRANSFER_PIXELS
    bytes  = new Uint8Array image.data
    # A word at a time rather than a byte at a time: a 2048-square image is 16
    # million byte writes on the thread that has to keep the window alive.
    # Little-endian BGRA read as a word is ARGB, and swapping the R and B
    # bytes of that is the whole conversion. A copy first if the transferred
    # bytes do not start on a word boundary, which Uint32Array requires.
    source = if bytes.byteOffset % 4
      new Uint32Array new Uint8Array(bytes).buffer, 0, pixels
    else
      new Uint32Array bytes.buffer, bytes.byteOffset, pixels
    base = LAYOUT.transferWords
    for at in [0...pixels] by 1
      word = source[at]
      u32[base + at] = (word & 0xFF00FF00) | ((word & 0xFF) << 16) | ((word >>> 16) & 0xFF)
    Atomics.store i32, H.LOAD_W, image.width
    Atomics.store i32, H.LOAD_H, image.height
    Atomics.store i32, H.LOAD_STATE, 2
  catch error
    message = new TextEncoder().encode String error.message ? error
    new Uint8Array(sab, LAYOUT.transferWords * 4, message.length).set message
    Atomics.store i32, H.LOAD_W, message.length
    Atomics.store i32, H.LOAD_STATE, 3
  Atomics.notify i32, H.LOAD_STATE
  undefined

# The worker runs one thing at a time and its inbox is not a queue we want:
# a run posted while a sketch is busy would sit there and fire the moment the
# sketch ended, which looks exactly like the sketch running itself twice.
send = ({source, name}) ->
  if status in BUSY
    say '*** already running -- stop it first (Ctrl-.) ***', 'sys'
    return
  Atomics.store i32, H.INTERRUPT, 0   # a stop leaves the flag raised
  setStatus 'running'
  worker.postMessage {type: 'run', source, name}

start = (thenRun = null) ->
  worker?.terminate()
  drainPrints()                       # anything the old worker already wrote
  Atomics.store i32, H.PRINT_HEAD, 0
  Atomics.store i32, H.PRINT_TAIL, 0
  Atomics.store i32, H.PRINT_LOST, 0
  Atomics.store i32, H.INTERRUPT, 0
  Atomics.store i32, H.SKETCH_US, 0
  Atomics.store i32, H.SWAP,      0
  Atomics.store i32, H.FRONT,     0
  Atomics.store i32, H.ASK_STATE, 0   # the old worker will never answer now
  Atomics.add   i32, H.SOUND_EPOCH, 1 # nor should anything it queued play
  clearInput()
  paused   = no                       # a new sketch does not inherit a pause
  stepOnce = no
  linePaused = null                   # nor a line pause: the old worker is gone
  Editor.showLine null
  hideVars()
  pending = thenRun
  worker  = new Worker '/src/renderer/worker-boot.js'
  worker.onmessage = ({data}) -> messages[data.type]? data
  # A worker that dies on the way up posts nothing, and without this the
  # status sits on 'booting' forever while every run is silently queued.
  worker.onerror = (event) ->
    say "worker: #{event.message ? 'failed to start'}", 'err'
    setStatus 'error'
  worker.postMessage type: 'boot', sab: sab
  setStatus 'booting'

stop = ->
  pending = null
  # Stop clears the swap itself and notifies, so it releases a paused worker
  # without any help. Going through goFrames rather than just dropping the flag
  # is what puts the status line back: left saying "paused", nothing that reads
  # it -- the buttons, a test, the next run -- can tell the pause is over.
  goFrames()
  Atomics.store  i32, H.INTERRUPT, 1
  Atomics.store  i32, H.SWAP,      0
  Atomics.notify i32, H.SWAP
  Atomics.add    i32, H.SOUND_EPOCH, 1   # silence now, not at the next yield point
  # A sketch stopped in V8 cannot reach a yield point to notice the interrupt,
  # so it is let go first, told to ignore any breakpoint on its way out, and
  # the deadline only starts once it is actually running. Timed from the
  # press instead, it would always miss, destroy the live image, and blame
  # "no yield point", which would be a lie.
  if linePaused
    linePaused = null
    skipping = yes
    await beans.debug.resume yes
    Editor.showLine null
    hideVars()
    setStatus 'running' if status is 'line paused'
  else if armedFor
    skipping = yes
    beans.debug.resume yes
  # The deadline belongs to this worker. A restart before it passes replaces
  # the worker, and this check must not shoot the new one.
  stopping = worker
  deadline = performance.now() + 250
  check = ->
    return unless worker is stopping and status is 'running'
    if performance.now() > deadline
      say '*** no yield point, worker terminated (state lost) ***', 'sys'
      start()
    else
      requestAnimationFrame check
  requestAnimationFrame check

# --- editor wiring ----------------------------------------------------------

# A run that arrives while the runtime is still loading waits for it; sent
# straight through it would evaluate before `screen` exists. The latest
# request wins, which is also what a held-down Ctrl-Enter means.
# Arming has to finish before the run it is for, or the first breakpoint is
# missed. It is the only wait in front of a run, so it is skipped when nothing
# changes, and said on the status line when it happens -- which is also what
# stops anything watching the status from mistaking the gap for a run that
# has already finished.
armFirst = (source, run) ->
  return run() if wantsDebug(source) is armedFor and not skipping
  before = status
  setStatus 'arming'
  await syncDebug source
  setStatus before if status is 'arming'
  run()

runSource = (source, name) -> armFirst source, ->
  return start {source, name} unless worker
  return pending = {source, name} if status is 'booting'
  send {source, name}

runFresh = (source, name) -> armFirst source, -> start {source, name}

# Non-comment source lines, the count he used to fish out of the REPL. With a
# :target set it reads count/limit and turns red once the limit is passed.
setLines = ({count, limit}) ->
  linesEl.textContent = if limit? then "#{count}/#{limit} lines" else "#{count} lines"
  linesEl.classList.toggle 'over', limit? and count > limit
  undefined

Editor.mount document.getElementById('editor'),
  onPause:    pauseFrames
  onStep:     stepFrame
  onGo:       continueAll
  onLine:     stepLine
  onEval:     (source, name) -> runSource source, "#{name} (region)"
  onEvalAll:  (source, name) -> runSource source, name
  onRun:      (source, name) -> say '*** run -- fresh worker ***', 'sys'; runFresh source, name
  onExternal: (name) -> say "reloaded #{name}.coffee from disk", 'sys'
  onHelp:     showHelp
  onLines:    (lines) -> setLines lines; watchBuffer()
  onMessage:  (text) -> say text, 'sys'
  onProblem:  (text) -> say text, 'err'
  onEdit:     (name) -> openSketch name

# The open sketch's name lives in the window title, which costs the header
# nothing, and is remembered so the next launch reopens it instead of
# whichever sketch sorts first.
selectSketch = (name) ->
  await Editor.load name
  document.title = "#{name} \u2014 CoffeeBEANS"
  localStorage.setItem 'lastSketch', name
  Editor.focus()

# :e newfile -- create it if it does not exist yet (an empty sketch, the way a
# touch would leave it), then open it.
openSketch = (name) ->
  unless name in await beans.list()
    await beans.write name, ''
    say "created #{name}.coffee", 'sys'
  await selectSketch name

pickSketch = ->
  choice = await beans.pick()
  if choice.outside
    say "#{choice.outside} is outside your sketches folder -- copy it in first", 'err'
  else if choice.name
    await selectSketch choice.name
  else
    Editor.focus()

toggleEditor = ->
  main.classList.toggle 'solo'
  resize()

document.getElementById('evalRegion').onclick = -> Editor.evalRegion()
document.getElementById('runFresh').onclick   = -> runFresh Editor.all(), Editor.name()
document.getElementById('pauseFrame').onclick = -> if status in PAUSED then continueAll() else pauseFrames()
document.getElementById('stepFrame').onclick  = stepFrame
document.getElementById('stepLine').onclick   = stepLine
document.getElementById('stop').onclick       = stop
document.getElementById('toggle').onclick     = toggleEditor
document.getElementById('open').onclick = pickSketch
beans.onOpen pickSketch

# The line-stepping keys are DevTools' own, and are caught before the editor
# or the prompt can see them: Ctrl-\ is a prefix in vim, and a key that
# pauses only when the right thing has focus is no use in a hurry.
window.addEventListener 'keydown', ((event) ->
  modified = event.ctrlKey or event.metaKey
  verb = if event.key is 'F8' or (modified and event.key is '\\')
    togglePause
  else if event.key is 'F10'
    stepLine
  return unless verb
  event.preventDefault()
  event.stopPropagation()
  verb()
), true

window.addEventListener 'keydown', (event) ->
  return unless event.ctrlKey
  handled =
    'e':      toggleEditor
    '.':      stop
  if handled[event.key]
    event.preventDefault()
    handled[event.key]()

listenForInput()
listenForPrompt()

dragPanel document.getElementById('splitEditor'),  'editor'
dragPanel document.getElementById('splitConsole'), 'console'

setInterval (-> drainPrints(); drainAsk()), CONSOLE_EVERY

new ResizeObserver(resize).observe stage
window.addEventListener 'resize', reflowPanels

# The console pane is the only one he is looking at. Without these, an
# uncaught renderer error goes to the terminal -- or nowhere -- and the window
# just quietly stops doing things.
window.addEventListener 'error', (event) ->
  say "renderer: #{event.message}", 'err'
window.addEventListener 'unhandledrejection', (event) ->
  say "renderer: #{event.reason?.message ? event.reason}", 'err'

# --- boot -------------------------------------------------------------------

do ->
  # The worker and the present loop come up first and unconditionally. If
  # loading a sketch goes wrong, you should still get a window that draws
  # and a console that tells you what happened.
  restorePanels()
  start()
  frame()
  startSound()
  say 'CoffeeBEANS 0.0.1  --  Ctrl-Enter evals the block under the cursor, > for a line, :help for the rest', 'sys'

  try
    names  = await beans.list()
    wanted = params.get 'sketch'
    if wanted and wanted not in names
      say "no sketch named \"#{wanted}\" -- opening #{names[0]}", 'err'
      wanted = null
    last = localStorage.getItem 'lastSketch'
    # The URL is how the suite drives the app, so it must not inherit
    # whatever the last hand-run session had open.
    wanted ?= if last in names and not params.has 'sketch' then last else names[0]
    if names.length
      await selectSketch wanted
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
