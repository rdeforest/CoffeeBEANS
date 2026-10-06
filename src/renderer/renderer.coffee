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
  # The drop count is taken before the head, never after. The worker counts a
  # drop only after storing the head of every line it wrote first, so the head
  # read below covers them all and the notice follows them: late at worst,
  # never early. Taken after, a drop made mid-drain was announced ahead of the
  # lines still in the ring past the old head, and a big enough backlog pushed
  # it out past the console cap (found by Claude in CI, 2026-10-05).
  lost = Atomics.exchange i32, H.PRINT_LOST, 0
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

# Tab's question while it is out -- the line and caret it was asked about, so
# an answer that arrives after either has moved can be dropped -- and the
# last ambiguous answer, which a second Tab on the same line lists. One slot
# for both ways of asking, the worker and the paused frame: an answer is
# taken only by the question it belongs to, so a later Tab replaces the
# earlier one rather than receiving its answer.
completing = null
tabbed     = null

askLine = (source) ->
  return unless source.trim()
  say "> #{source}", 'echo'
  entered.push source
  enteredAt = entered.length
  return Editor.command source if Editor.isCommand source
  return say '*** no worker -- press Run ***', 'err' unless worker
  # A sketch stopped in V8 cannot serve the shared-memory question -- nothing
  # runs to look at it -- so the line goes to the paused frame instead. That
  # is also the better answer: this call's `angle`, not the image's.
  if linePaused
    return stillAsking() if debugAsking
    return askPaused source
  return say '*** still answering Tab ***', 'sys' unless withdrawTab()
  if Atomics.load(i32, H.ASK_STATE) isnt 0
    return say '*** still waiting on the last line ***', 'sys'
  askWorker source, LAYOUT.ASK_FOR.value

# A Tab still out gives way to a line: taken back if the worker has not
# claimed it yet, its answer dropped if one is already in -- not offered,
# which would rewrite the very line being sent. One the worker is answering
# has to finish first, and only that refuses the line, so this says no. Without
# this, a Tab at a sketch with no yield point would block every later line
# until Stop.
#
# Whose question is out is read from ASK_KIND, which only this side writes,
# not from `completing`: a Tab asked of a paused frame sets that too, while a
# line may still be waiting in shared memory, and taking that line back left
# it unanswered with nothing said (found by the holistic review, 2026-10-05).
withdrawTab = ->
  return yes unless Atomics.load(i32, H.ASK_KIND) is LAYOUT.ASK_FOR.completion
  return no if Atomics.compareExchange(i32, H.ASK_STATE, 1, 0) is 4
  completing = null
  drainAsk()
  yes

# The one way a question reaches a worker that is not line paused, a line or
# Tab's alike; ASK_KIND says which, so drainAsk knows whose the answer is.
askWorker = (text, kind) ->
  bytes = new TextEncoder().encode text
  return say '*** line too long ***', 'err' if bytes.length > LAYOUT.ASK_BYTES
  askBytes.set bytes
  Atomics.store i32, H.ASK_KIND,  kind
  Atomics.store i32, H.ASK_LEN,   bytes.length
  Atomics.store i32, H.ASK_STATE, 1
  # An idle worker is parked in its event loop and will never look at shared
  # memory unaided. A busy one cannot receive this, and has already been told
  # where to look; the message then arrives to find nothing left to do.
  worker.postMessage type: 'ask'
  undefined

debugAsking = 0

# The pane's member listings while they are out. Runtime.getProperties during
# a step or an evaluation has never been measured, so a listing takes the
# turn as well -- but it is waited for, not refused: the pane re-opens what
# was open on every pause, and a step pressed just then must not bounce.
# Listings do not wait for each other, or a redraw would refuse itself.
listing = new Set
listed  = -> Promise.all listing

# Whether step and continue may go: once the listings are in, and only if no
# evaluation is out -- one may have been asked for while they were.
frameFree = ->
  await listed()
  not debugAsking

movedOn = -> say '*** it moved on before it could answer ***', 'sys'

# And the one way to evaluate in a line-paused frame -- a line, Tab, a getter
# clicked in the pane. Counted while out, so step, continue, the pane and each
# other all wait their turn: nothing may reach V8 until it is back. Counted
# from the call, not from when it is sent, so a second one asked in the same
# tick is refused; it is sent only once the pane's member listings are in.
evaluatePaused = (ask) ->
  debugAsking += 1
  try
    await listed()
    await ask()
  finally
    debugAsking -= 1

# The pane is redrawn only once the evaluation is counted back in, so the
# objects it re-opens are not asked for while one is still out.
askPaused = (source) ->
  try
    reply = await evaluatePaused -> beans.debug.evaluate source
  catch error
    return say String(error.message ? error), 'err'
  return movedOn() unless reply
  showVars reply.pane if reply.pane and reply.pane.seq is linePaused
  say reply.text, reply.kind
  undefined

drainAsk = ->
  state = Atomics.load i32, H.ASK_STATE
  return unless state is 2 or state is 3
  # Copied out first: TextDecoder refuses a view onto shared memory, and the
  # state is cleared before we decode so a bad answer cannot wedge the prompt
  # by throwing here every 16ms forever.
  answer = new Uint8Array askBytes.subarray 0, Atomics.load i32, H.ASK_LEN
  kind   = Atomics.load i32, H.ASK_KIND
  Atomics.store i32, H.ASK_STATE, 0
  text = decoder.decode answer
  return completed completing, text, state is 3 if kind is LAYOUT.ASK_FOR.completion
  say text, (if state is 3 then 'err' else 'value')
  undefined

recall = (step) ->
  tabbed = null
  return unless entered.length
  enteredAt = Math.min entered.length, Math.max 0, enteredAt + step
  promptLine.value = entered[enteredAt] ? ''
  promptLine.setSelectionRange promptLine.value.length, promptLine.value.length

# --- the prompt's keys --------------------------------------------------------

# Readline's keys, as the node and coffee REPLs have them (Robert's call,
# 2026-10-04): Node 24's "TTY keybindings" table and the REPL's
# reverse-i-search, ported from lib/internal/readline/interface.js and
# lib/internal/repl/utils.js by Claude on 2026-10-05. While the prompt has
# focus they beat the app's shortcuts -- Ctrl-E is end of line here and
# toggles the editor everywhere else. The keys that must work from anywhere
# are safe: Ctrl-\, F8 and F10 are caught before the prompt sees them, and
# Ctrl-. is not bound here.
#
# Rows of that table left unbound on purpose:
#   Ctrl-Left/Right, Ctrl-Backspace/Delete  Chromium's own, with its own word
#                                           boundaries -- left to it
#   Ctrl-_ undo, Ctrl-6 redo                the input's native undo and redo
#                                           instead; Ctrl-- is zoom out
#   Ctrl-Z suspend                          no process to suspend; stays undo
# and one bound over a native key: Ctrl-Y is yank, which takes it from
# Windows' redo. Ctrl-Shift-Z still redoes.
#
# Ctrl, never Cmd: on a Mac Cmd-A still selects all, and these Ctrl keys are
# what Cocoa's own text fields already mean by them. Alt is readline's Meta
# except on a Mac, where Option types characters. AltGr arrives as Ctrl+Alt
# on Windows, so Ctrl+Alt with a key that types a character is typing; with
# one that types nothing -- Enter, an arrow -- it is a chord of its own, so
# Ctrl-Alt-Enter on Linux is not Enter. Not getModifierState('AltGraph'):
# what Chromium reports for it on Windows is unmeasured.
ON_MAC        = /Mac/.test navigator.platform
MODIFIER_KEYS = ['Shift', 'Control', 'Alt', 'AltGraph', 'Meta', 'CapsLock']
UNFINISHED    = ['Dead', 'Process']  # half a character: a dead key, or the IME's
KILL_RING     = 32                   # readline's kMaxLengthOfKillRing
PASS          = Symbol 'pass'        # a binding that hands the key back

promptMark = document.getElementById 'promptMark'
killRing   = []
killAt     = 0
yanking    = no
searching  = null

oneCharacter = (text) -> Array.from(text).length is 1

chordOf = (event) ->
  return null if event.metaKey
  typed = oneCharacter event.key
  altGr = event.ctrlKey and event.altKey and typed
  ctrl  = event.ctrlKey and not altGr
  alt   = event.altKey  and not altGr and not ON_MAC
  shift = event.shiftKey and (ctrl or alt)
  key   = if (ctrl or alt) and typed then event.key.toLowerCase() else event.key
  "#{if ctrl then 'C-' else ''}#{if alt then 'M-' else ''}#{if shift then 'S-' else ''}#{key}"

caret   = -> if promptLine.selectionDirection is 'backward' then promptLine.selectionStart else promptLine.selectionEnd
leftOf  = -> promptLine.value[...caret()]
rightOf = -> promptLine.value[caret()..]
moveTo  = (at) -> promptLine.setSelectionRange at, at

# By code point, so an emoji is one step, not two. Not /[\s\S]$/u: V8 finds
# no match for that at all when the last character is outside the BMP
# (checked by Claude in Node 26.10, 2026-10-05).
charLeft  = -> Array.from(leftOf()).pop()?.length ? 0
charRight = -> Array.from(rightOf())[0]?.length   ? 0

# Readline's own word boundaries; the left ones read the text reversed.
backwards      = (text) -> Array.from(text).reverse().join ''
wordLeft       = -> caret() - /^\s*(?:[^\w\s]+|\w+)?/.exec(backwards leftOf())[0].length
wordRight      = -> caret() + /^(?:\s+|[^\w\s]+|\w+)\s*/.exec(rightOf())[0].length
eraseWordRight = -> caret() + /^(?:\s+|\W+|\w+)\s*/.exec(rightOf())[0].length

# Through execCommand rather than by assigning the value, which would wipe
# the input's own undo: Ctrl-Z is the ordinary key for "I didn't mean that",
# and Ctrl-U is an easy way to need it.
rewrite = (from, to, text = '') ->
  promptLine.setSelectionRange from, to
  document.execCommand 'insertText', false, text unless from is to and not text
  undefined

kill = (from, to) ->
  text = promptLine.value[from...to]
  rewrite from, to
  return if not text or text is killRing[0]
  killRing.unshift text
  killAt = 0
  killRing.length = KILL_RING if killRing.length > KILL_RING
  undefined

yank = ->
  return unless killRing.length
  yanking = yes
  rewrite caret(), caret(), killRing[killAt]

yankPop = ->
  return unless yanking and killRing.length > 1
  last   = killRing[killAt]
  killAt = (killAt + 1) % killRing.length
  rewrite caret() - last.length, caret(), killRing[killAt]

# --- Tab ----------------------------------------------------------------------

# Bash's Tab, as designed in AGENTS.md ("Tab completion"): as far as every
# candidate agrees, a beep when that is ambiguous, and the candidates listed
# on a second Tab. Only the worker knows the names worth offering, so it is
# asked, by the same path a line takes -- through the paused frame while line
# paused, so `ang` finds this call's `angle`. Whatever cannot be asked right
# now -- a line still out, an evaluation in a paused frame -- beeps rather
# than queues. A sketch with no yield point never answers, and Tab does
# nothing, as the prompt does nothing.
#
# The word is a dotted name ending at the caret. Anything else -- `a[0].`,
# `f().`, `@x` -- would mean evaluating something to find out what it is,
# and Tab never evaluates; it beeps.
DOTTED  = /(?:^|[^\w$.@])((?:[A-Za-z_$][\w$]*\.)*)([A-Za-z_$][\w$]*)?$/
COMMAND = /^\s*[\/:](\w*)$/   # a command's name, as Editor.isCommand finds one
ARGUED  = /^\s*[\/:]/          # a command with more after its name

commonPrefix = (a, b) ->
  at = 0
  at += 1 while at < a.length and a[at] is b[at]
  a[...at]

# The answer to a question asked at `line`, with the caret at `at`. Dropped
# if the line has moved on since: completing what is no longer there would
# write into the middle of something else. Dropped too if the focus has left
# the prompt, where the line and caret stand still: rewrite types into
# whatever has focus, and in the editor that is the sketch, autosaved.
offer = ({line, at, word}, names) ->
  return unless document.activeElement is promptLine and promptLine.value is line and caret() is at
  fits = (name for name in names when name.startsWith word)
  return beep() unless fits.length
  common = fits.reduce commonPrefix
  rewrite at, at, common[word.length..] if common.length > word.length
  return if fits.length is 1
  tabbed = {line: promptLine.value, at: caret(), names: fits}
  beep()

completed = (asked, text, threw) ->
  return unless asked and asked is completing
  completing = null
  return say "completion: #{text}", 'err' if threw
  offer asked, JSON.parse text

complete = ->
  line = promptLine.value
  at   = caret()
  return beep() unless promptLine.selectionStart is promptLine.selectionEnd
  if tabbed?.line is line and tabbed.at is at
    return say tabbed.names.join('   '), 'sys'
  before  = line[...at]
  command = COMMAND.exec before
  return offer {line, at, word: command[1]}, Editor.commands() if command
  # A command's arguments are not CoffeeScript, so the worker's names mean
  # nothing there.
  return beep() if ARGUED.test before
  found = DOTTED.exec before
  path  = found?[1].split('.')[...-1] ? []
  word  = found?[2] ? ''
  return beep() unless path.length or word
  asked = {line, at, word}
  return completePaused asked, path if linePaused
  return beep() unless worker and Atomics.load(i32, H.ASK_STATE) is 0
  completing = asked
  askWorker JSON.stringify({path, word}), LAYOUT.ASK_FOR.completion

# The frame's own names come from the pane's last report. The first name is
# read in the frame only when it is one of them -- a variable, which cannot
# be a getter; anything else is left to the worker's descriptor walk.
#
# A Tab still out to the worker is taken back first: it was asked about the
# line before this one, and would otherwise answer into this one's slot.
completePaused = (asked, path) ->
  return beep() if debugAsking or not withdrawTab()
  local    = path[0] in pausedNames
  question = JSON.stringify {path, word: asked.word, local}
  source   = "REPL.complete #{question}, #{JSON.stringify pausedNames}, #{if local then path[0] else 'undefined'}"
  completing = asked
  try
    reply = await evaluatePaused -> beans.debug.evaluate source
  catch error
    completing = null if completing is asked
    return say String(error.message ? error), 'err'
  unless reply
    completing = null if completing is asked
    return
  completed asked, (if reply.kind is 'value' then JSON.parse reply.text else reply.text), reply.kind isnt 'value'

submit = ->
  tabbed = null
  askLine promptLine.value
  promptLine.value = ''
  enteredAt = entered.length

# Ctrl-C copies a selection -- the ordinary key wins there, since readline has
# no selection to mean anything else by it -- and otherwise drops the line,
# the REPL's .break.
clearLine = ->
  return PASS if promptLine.selectionStart isnt promptLine.selectionEnd
  rewrite 0, promptLine.value.length
  enteredAt = entered.length

PROMPT_KEYS =
  'Enter':         submit
  # Shift-Tab still takes the keyboard back out of the prompt.
  'Tab':           (chord, event) -> if event.shiftKey then PASS else complete()
  'ArrowUp':       -> recall -1
  'ArrowDown':     -> recall  1
  'C-p':           -> recall -1
  'C-n':           -> recall  1
  'C-a':           -> moveTo 0
  'C-e':           -> moveTo promptLine.value.length
  'C-b':           -> moveTo caret() - charLeft()
  'C-f':           -> moveTo caret() + charRight()
  'M-b':           -> moveTo wordLeft()
  'M-f':           -> moveTo wordRight()
  'C-h':           -> rewrite caret() - charLeft(), caret()
  'C-d':           -> rewrite caret(), caret() + charRight()
  'C-w':           -> rewrite wordLeft(), caret()
  'M-Backspace':   -> rewrite wordLeft(), caret()
  'M-d':           -> rewrite caret(), eraseWordRight()
  'M-Delete':      -> rewrite caret(), eraseWordRight()
  'C-u':           -> kill 0, caret()
  'C-S-Backspace': -> kill 0, caret()
  'C-k':           -> kill caret(), promptLine.value.length
  'C-S-Delete':    -> kill caret(), promptLine.value.length
  'C-y':           yank
  'M-y':           yankPop
  'C-l':           -> output.replaceChildren()
  'C-c':           clearLine
  'C-r':           -> startSearch 'bck'
  'C-s':           -> startSearch 'fwd'

# Reverse-i-search, as the node REPL does it: the line shows the match, the
# mark says what is being looked for, each entry is shown once per query, and
# any key that is not part of the search takes the match and then does what
# it does -- so Enter runs it. Esc or Ctrl-C puts back the line from before.
showSearch = ->
  {dir, query, match} = searching
  promptMark.textContent = "#{if query and not match? then 'failed-' else ''}#{dir}-i-search: #{query}_"

startSearch = (dir) ->
  searching = {dir, query: '', from: enteredAt, at: enteredAt, match: null, seen: new Set,
               original: promptLine.value, caret: caret()}
  showSearch()

# From the entry the history was on, that one included, as node starts from
# its historyIndex. An entry is shown once per query, which is also what
# carries a second Ctrl-R past the match on show.
searchOn = ->
  {dir, query, seen} = searching
  step  = if dir is 'bck' then -1 else 1
  index = if dir is 'bck' then Math.min searching.at, entered.length - 1 else searching.at
  while 0 <= index < entered.length
    entry = entered[index]
    if query and entry.includes(query) and not seen.has entry
      seen.add entry
      searching.at = searching.match = index
      promptLine.value = entry
      moveTo if dir is 'bck' then entry.lastIndexOf query else entry.indexOf query
      return showSearch()
    index += step
  searching.match = null
  promptLine.value = searching.original
  moveTo searching.caret
  showSearch()

# Turning round forgets what was shown, so it can be found again on the way
# back -- all but the match on show, which would otherwise be found first.
searchToward = (dir) ->
  unless dir is searching.dir
    searching.seen.clear()
    searching.seen.add entered[searching.match] if searching.match?
  searching.dir = dir
  searchOn()

requery = (query) ->
  Object.assign searching, {query, at: searching.from, match: null}
  searching.seen.clear()
  searchOn()

endSearch = ->
  enteredAt = searching.match if searching.match?
  searching = null
  promptMark.textContent = '>'

cancelSearch = ->
  Object.assign searching, match: null
  promptLine.value = searching.original
  moveTo searching.caret
  endSearch()

dropLast = -> requery searching.query[...-1]

SEARCH_KEYS =
  'C-r':       -> searchToward 'bck'
  'C-s':       -> searchToward 'fwd'
  'Backspace': dropLast
  'C-h':       dropLast
  'C-w':       dropLast
  'Escape':    cancelSearch
  'C-c':       cancelSearch

claim = (event, verb, chord) ->
  return if verb(chord, event) is PASS
  event.preventDefault()
  # Not just the default: the window's own Ctrl-E is listening further up.
  event.stopPropagation()

onPromptKey = (event) ->
  return if event.key in MODIFIER_KEYS or event.isComposing
  chord = chordOf event
  # A second Tab lists only if nothing came between, not just the same line.
  tabbed = null unless chord is 'Tab'
  if searching
    return if event.key in UNFINISHED
    verb = SEARCH_KEYS[chord] ? (((typed) -> requery searching.query + typed) if chord? and oneCharacter chord)
    return claim event, verb, chord if verb
    # Any other key takes the match and does what it does. Tab too, on
    # purpose: it completes the word at the caret, where the search left it.
    endSearch()
  return unless chord?
  yanking = no unless chord is 'M-y'
  verb = PROMPT_KEYS[chord]
  claim event, verb, chord if verb

# A click moves the caret out from under a yank, so Alt-Y after it would
# replace text that is not the yank.
interruptPrompt = ->
  yanking = no
  endSearch() if searching

listenForPrompt = ->
  promptLine.addEventListener 'keydown',     onPromptKey
  promptLine.addEventListener 'pointerdown', interruptPrompt
  promptLine.addEventListener 'blur',        interruptPrompt

  # Clicking the log to read it should not cost you the prompt, but clicking
  # to select text should not steal it back either.
  document.getElementById('consolePane').addEventListener 'click', (event) ->
    return if event.target.closest '#vars'    # opening a value is not typing
    promptLine.focus() unless String(window.getSelection())
  undefined

# Is anything printed still on its way to the screen -- bytes the ring has not
# handed over, a drop not yet announced, or lines queued but not yet in the
# DOM. All are read in one go on the one thread that drains them, so a false
# here means everything a sketch printed, or failed to, is on screen. The
# suite waits on this instead of guessing an interval; a loaded machine makes
# every guess wrong eventually.
globalThis.Printing =
  pending: ->
    Atomics.load(i32, H.PRINT_HEAD) isnt Atomics.load(i32, H.PRINT_TAIL) or queued.length > 0 or
      Atomics.load(i32, H.PRINT_LOST) isnt 0

globalThis.Prompt =
  ask:     askLine
  pending: -> Atomics.load(i32, H.ASK_STATE) isnt 0 or debugAsking > 0 or listing.size > 0
  entered: -> entered.slice()
  beeps:   -> beeps

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
    Atomics.or  i32, H.KEYS_UP  + word, mask
  true

# A key let go by losing focus is still a key let go. Without the up, a note
# held while a key is down would ring on after you clicked away.
clearKeys = ->
  for word in [0...LAYOUT.KEY_WORDS]
    Atomics.or    i32, H.KEYS_UP + word, Atomics.exchange i32, H.KEYS + word, 0
  undefined

# Blur only releases what is held -- a tap that happened is still a tap, and
# the sketch should see it. A restart is different: a new sketch must not
# inherit a key that was down, a hit nobody claimed, or wheel movement nobody
# read, all of which outlive the worker in shared memory.
clearInput = ->
  for word in [0...LAYOUT.KEY_WORDS]
    Atomics.store i32, H.KEYS     + word, 0
    Atomics.store i32, H.KEYS_HIT + word, 0
    Atomics.store i32, H.KEYS_UP  + word, 0
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
    say "no help for \"#{topic}\" -- try /help with no topic", 'err'
    return
  entries = [].concat (section.lines for section in sections)...
  width   = Math.max (syntax.length for [syntax] in entries)...
  top     = output.scrollHeight
  for section in sections
    say section.title, 'help-head'
    for [syntax, description] in section.lines
      say "  #{syntax.padEnd width}   #{description}", 'help'
    if section.example
      say 'Example', 'help-head'
      say "    #{line}", 'help-code' for line in section.example
  flushConsole()
  output.scrollTop = top          # land on the first section, not the last
  undefined

# --- about ------------------------------------------------------------------

# In the page rather than Electron's native about panel, which cannot carry a
# Copy button on every platform (Robert, 2026-10-05). Copy takes the text as
# shown, so what lands in a bug report is what the player saw.
aboutBox  = document.getElementById 'about'
aboutText = document.getElementById 'aboutText'
aboutCopy = document.getElementById 'aboutCopy'

showAbout = ->
  {text} = await beans.about()
  aboutText.textContent = text
  aboutCopy.textContent = 'Copy'
  aboutBox.showModal()

aboutCopy.onclick = ->
  await beans.copy aboutText.textContent
  aboutCopy.textContent = 'Copied'

beans.onAbout showAbout

# --- the report -------------------------------------------------------------

# The 📣🐞 button: the player says what happened, main adds About and the
# console's tail and redacts it, and the player sees -- and may edit --
# exactly what is saved. They attach the file to an issue; nothing is sent.
REPORT_LINES = 100

reportButton  = document.getElementById 'feedback'
reportBox     = document.getElementById 'report'
reportWords   = document.getElementById 'reportWords'
reportSketch  = document.getElementById 'reportSketch'
reportText    = document.getElementById 'reportText'
reportSave    = document.getElementById 'reportSave'
reportRefused = document.getElementById 'reportRefused'
reportSaved   = document.getElementById 'reportSaved'

# Where the player was before a click on the button took focus. A dialog
# closing hands focus back to whatever had it when it opened -- after a
# click, the button itself, so Space would open the report again and typing
# would go nowhere. pointerdown comes before the click moves focus. Reached
# by Tab instead, the button is where the player was, and stays null.
reportReturn = null

reportStep = (id) ->
  step.hidden = step.id isnt id for step in reportBox.querySelectorAll '.step'
  undefined

# Said in the dialog, which is where the player is looking; the console is
# behind it.
reportFailed = (what, error) ->
  reportSaved.textContent = "Could not #{what}: #{error.message}"
  reportStep 'reportDone'

openReport = ->
  reportReturn = document.activeElement unless document.activeElement is reportButton
  reportWords.value     = ''
  reportSketch.checked  = no
  reportRefused.hidden  = yes
  reportStep 'reportAsk'
  reportBox.showModal()
  reportWords.focus()

draftReport = ->
  flushConsole()
  lines  = (line.textContent for line in output.children)[-REPORT_LINES..]
  sketch = if reportSketch.checked then {name: Editor.name(), text: Editor.all()} else null
  try
    reportText.value = await beans.report.draft {words: reportWords.value, lines, sketch}
  catch error
    return reportFailed 'draft the report', error
  reportStep 'reportCheck'
  reportText.focus()

# One save at a time. A save that fails leaves the player where they were,
# their edits intact, to try again.
saveReport = ->
  reportSave.disabled  = yes
  reportRefused.hidden = yes
  try
    {file, issues} = await beans.report.save reportText.value
  catch error
    reportRefused.textContent = "Could not save the report: #{error.message}"
    reportRefused.hidden      = no
    return
  finally
    reportSave.disabled = no
  told = "Saved #{file} -- its folder is open. To send it, open an issue at #{issues} and attach the file."
  reportSaved.textContent = told
  say told, 'sys'
  reportStep 'reportDone'

reportButton.addEventListener 'pointerdown', -> reportReturn = document.activeElement
reportBox.addEventListener 'close', ->
  reportReturn?.focus()
  reportReturn = null
reportButton.onclick                            = openReport
document.getElementById('reportDraft').onclick  = draftReport
reportSave.onclick                              = saveReport
document.getElementById('reportIssues').onclick = -> beans.report.issues()

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
    seq = linePaused
    return stillAsking() unless await frameFree()
    return unless linePaused is seq
    pauseFrames()
    return beans.debug.resume()
  pauseFrames() unless paused
  stepOnce = yes

# --- line stepping ----------------------------------------------------------

# The pause we are in, as the debugger numbered it, or null. The number is
# what makes an object id in the variables pane mean anything.
linePaused  = null
pausedNames = []          # every name the paused frame's scopes hold, for Tab

# Suspend now, on whatever line is running. From a frame pause the swap has to
# be let go, or the sketch never reaches a line to stop on.
linePause = ->
  return unless status in ['running', 'frame paused']
  unless await beans.debug.pause()
    return say '*** could not pause -- is DevTools open? ***', 'sys'
  goFrames()

# Something -- a line, Tab, a getter -- is still being worked out inside the
# paused frame, and V8 must not be moved on under it (main refuses too; this
# is the saying so).
stillAsking = -> say '*** still evaluating in the paused frame ***', 'sys'

# Each waits for the frame to be free, and the pause may be gone by then --
# Stop, or a Run -- with nothing left to step or continue.
stepLine = ->
  return linePause() unless linePaused
  seq = linePaused
  return stillAsking() unless await frameFree()
  return unless linePaused is seq
  beans.debug.step()

continueAll = ->
  return goFrames() unless linePaused
  seq = linePaused
  return stillAsking() unless await frameFree()
  return unless linePaused is seq
  goFrames()
  beans.debug.resume()

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
      linePaused  = event.seq
      pausedNames = (entry.name for entry in scope.vars for scope in event.scopes).flat()
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
# so a value can be watched changing as you step. Nothing here runs code
# unasked: the debugger hands over previews, and a getter is shown as a
# getter until it is clicked.
varsEl = document.getElementById 'vars'

# What was open, by path, so a step does not fold everything back up; and
# what each row said last time, so a value that changed can say so.
expandedPaths = new Set
shownBefore   = new Map

# What a click on a getter got, by path -- only the latest click's. Anything
# else that redraws the pane -- a step, the prompt, another getter -- may have
# changed what a getter would say, so it goes back to not run rather than
# show an answer that is no longer true.
ranGetters = new Map

# The click is an evaluation in the paused frame, so it waits its turn with
# the prompt's: refused while one is out, and holding step and continue off
# while it runs (main refuses both as well; this is the saying so). The pause
# is the one it was clicked in, not whichever is current once it is sent.
runGetter = (entry, path) ->
  return stillAsking() if debugAsking
  seq = linePaused
  try
    reply = await evaluatePaused -> beans.debug.getter seq, entry.owner, entry.name
  catch error
    return say String(error.message ? error), 'err'
  return stillAsking() if reply is 'evaluating'
  return movedOn() unless reply
  return unless reply.pane.seq is linePaused
  ranGetters.clear()
  ranGetters.set path, reply
  showVars reply.pane, yes

varRow = (entry, path, depth) ->
  row = document.createElement 'div'
  row.className = 'var'
  row.style.paddingLeft = "#{depth * 1.1 + .4}rem"
  name = document.createElement 'span'
  name.className   = 'var-name'
  name.textContent = entry.name
  value = document.createElement 'span'
  ran   = ranGetters.get path
  value.className   = if ran then 'var-value ran' else if entry.getter then 'var-value getter' else 'var-value'
  value.textContent = ran?.text ? entry.text
  value.classList.add 'thrown' if ran?.kind is 'err'
  seen = shownBefore.get path
  value.classList.add 'changed' if seen? and seen isnt entry.text
  shownBefore.set path, entry.text
  row.append name, value
  holder = document.createElement 'div'
  holder.append row
  if entry.id
    row.classList.add 'openable'
    # Listing members is a request to V8, so it waits its turn behind an
    # evaluation like everything else. A redraw's re-open just stays closed
    # and remembered, for the next redraw to try.
    open = (expand, redrawn = no) ->
      if expand and debugAsking
        return if redrawn
        return stillAsking()
      row.classList.toggle 'open', expand
      if expand
        expandedPaths.add path
        fetching = beans.debug.members linePaused, entry.id
        # Held only as something to wait on; the error, if any, is this
        # row's, and the await below still meets it.
        held = fetching.catch(->)
        listing.add held
        try
          members = await fetching
        catch error
          row.classList.remove 'open'
          expandedPaths.delete path
          return say String(error.message ? error), 'err'
        finally
          listing.delete held
        if members is 'evaluating'
          row.classList.remove 'open'
          expandedPaths.delete path
          return stillAsking()
        return unless members and row.classList.contains 'open'
        children = document.createElement 'div'
        children.className = 'var-children'
        children.append (varRow member, "#{path}.#{member.name}", depth + 1 for member in members)...
        holder.append children
      else
        expandedPaths.delete path
        holder.querySelector('.var-children')?.remove()
    row.addEventListener 'click', -> open not row.classList.contains 'open'
    open yes, yes if expandedPaths.has path
  if entry.getter and entry.owner
    row.classList.add 'runnable'
    row.addEventListener 'click', -> runGetter entry, path
  holder

showVars = ({where, scopes}, forGetter = no) ->
  ranGetters.clear() unless forGetter
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

# --- after a failed run -------------------------------------------------------

# Region runs carry this on their name, so a traceback can say a frame came
# from a region; it comes off again to find the sketch the region was in.
REGION   = ' (region)'
sketchOf = (runName) -> if runName?.endsWith REGION then runName[...-REGION.length] else runName

# Declared here, above everything that touches them, and not beside toCanvas
# further down: CoffeeScript resolves scope in file order, so `send` -- which
# sets inFlight -- would otherwise have compiled it as a local of its own and
# nothing would ever have read what it recorded (caught by Claude in the
# compiled output, 2026-10-04).
inFlight    = null      # the run last sent: its name, and how much a region was dedented
canvasTimer = null

# A runtime error's stack, in the pane the debugger uses for names: innermost
# first, one row a frame, each taking you to its line. Nothing here is live --
# the frames are gone -- but the image still holds every top-level name, which
# is why the prompt has the keyboard until a frame is chosen.
showStack = (frames, message) ->
  head = document.createElement 'div'
  head.className   = 'vars-head stack-head'
  head.textContent = message
  title = document.createElement 'div'
  title.className   = 'vars-title'
  title.textContent = 'stack'
  across = (new Set(step.name for step in frames)).size > 1
  rows = for step in frames
    do (step) ->
      row = document.createElement 'div'
      row.className = 'stack-frame'
      site = document.createElement 'span'
      site.className   = 'stack-site'
      where = "#{step.fn ? 'top level'} \u00b7 line #{step.line ? '?'}"
      where += " \u00b7 #{sketchOf step.name}" if across and step.name
      site.textContent = where
      code = document.createElement 'span'
      code.className   = 'stack-code'
      code.textContent = step.text ? ''
      row.append site, code
      if step.line?
        row.classList.add 'openable'
        row.addEventListener 'click', -> visitFrame step, row
      row
  varsEl.replaceChildren head, title, rows...
  varsEl.hidden = no
  undefined

visitFrame = (step, row) ->
  chosen.classList.remove 'chosen' for chosen in varsEl.querySelectorAll '.stack-frame.chosen'
  row.classList.add 'chosen'
  name = sketchOf step.name
  # A frame from a region of another sketch -- a helper defined there and
  # called from here -- is in that sketch, so that is where it opens.
  unless name is Editor.name()
    try
      await selectSketch name
    catch error
      say "cannot open #{name}: #{error.message ? error}", 'err'
      return
  Editor.jumpTo step.line
  undefined

# Where the keyboard goes once a run has failed. A syntax error is fixed where
# it is, so the cursor goes there. A runtime error offers its stack, marks
# the innermost line without moving the cursor, and gives the prompt the
# keyboard. A canvas focus still pending from the run is cancelled either way:
# a run that fails inside one tick would otherwise snatch the keyboard back.
showFailure = ({kind, line, column, frames, message}) ->
  clearTimeout canvasTimer
  mine = sketchOf(inFlight?.name) is Editor.name()
  if kind is 'syntax'
    hideVars()
    # Regions are dedented before they compile, so a column comes back short
    # by however much was cut.
    Editor.jumpTo line, (column + (inFlight?.cut ? 0) if column?) if mine
    return
  frames ?= []
  showStack frames, message
  Editor.showError frames[0].line if frames[0]?.line? and sketchOf(frames[0].name) is Editor.name()
  promptLine.focus()
  undefined

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

# Kept for Tab's beep, which is the renderer's own and not a sketch's note:
# the worker is the sound ring's only writer, and a beep must sound while a
# sketch is busy, paused, or not there at all.
audio = null
beeps = 0                 # counted for the suite, which runs muted

beep = ->
  beeps += 1
  return unless audio
  at   = audio.currentTime
  tone = new OscillatorNode audio, type: 'sine', frequency: 880
  gain = new GainNode audio, gain: 0.04
  gain.gain.setTargetAtTime 0, at + 0.04, 0.015
  tone.connect(gain).connect audio.destination
  tone.start at
  tone.stop at + 0.12
  undefined

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
    send pending if pending
    pending = null
    # A line typed while the worker was booting poked it before it had
    # anywhere to read the line from, and it is still waiting. Poked again,
    # behind the run: a sketch with a yield point answers it there, from its
    # own names, and one without answers it once it has finished. Served at
    # the end of boot instead, it would be answered from an empty image.
    worker.postMessage type: 'ask'
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
    showFailure data

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
send = ({source, name, cut}) ->
  if status in BUSY
    say '*** already running -- stop it first (Ctrl-.) ***', 'sys'
    return
  # The last failure's marks are stale the moment something else runs.
  inFlight = {name, cut: cut ? 0}
  Editor.showError null
  hideVars()
  Atomics.store i32, H.INTERRUPT, 0   # a stop leaves the flag raised
  setStatus 'running'
  worker.postMessage {type: 'run', source, name}

start = (thenRun = null) ->
  # terminate() does not stop a busy worker for two seconds (see checkOwner in
  # the runtime), so the old one is first told the memory is no longer its
  # own, and woken if it is parked on a frame, before anything is reset.
  Atomics.add    i32, H.OWNER, 1
  Atomics.notify i32, H.SWAP
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
  worker.postMessage type: 'boot', sab: sab, owner: Atomics.load i32, H.OWNER
  setStatus 'booting'

stop = ->
  pending = null
  # Nothing running is nothing to unwind, but a note with no length can
  # outlive the sketch that started it, and Stop is where anyone reaches to
  # make it quiet. Raising the flag here would leave it up with no worker
  # busy to report idle and lower it.
  if status in ['ready', 'error']
    Atomics.add i32, H.SOUND_EPOCH, 1
    return
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

runSource = (source, name, cut) -> armFirst source, ->
  return start {source, name, cut} unless worker
  return pending = {source, name, cut} if status is 'booting'
  send {source, name, cut}

runFresh = (source, name) -> armFirst source, -> start {source, name}

# A sketch you run is almost always one you are about to play with, so Run
# and :eval give it the keyboard. Region eval does not: that is the loop of
# redefining something and carrying on typing, and the next keystroke belongs
# to the editor. A tick late on purpose -- with Vim Keys on, :run and :eval
# come through vim's command line, which runs the command and then, still
# inside the same keydown, focuses the editor as it closes.
toCanvas = ->
  clearTimeout canvasTimer
  canvasTimer = setTimeout (-> stage.focus()), 0

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
  onEval:     (source, name, cut) -> runSource source, "#{name}#{REGION}", cut
  onEvalAll:  (source, name) -> toCanvas(); runSource source, name
  onRun:      (source, name) -> say '*** run -- fresh worker ***', 'sys'; toCanvas(); runFresh source, name
  onExternal: (name) -> say "reloaded #{name}.coffee from disk", 'sys'
  onHelp:     showHelp
  onLines:    (lines) -> setLines lines; watchBuffer()
  onMessage:  (text) -> say text, 'sys'
  onProblem:  (text) -> say text, 'err'
  onEdit:     (name) -> openSketch name

# The open sketch's name lives in the window title, which costs the header
# nothing, and is remembered so the next launch reopens it instead of
# whichever sketch sorts first.
#
# `name` is spelled as the disk spells it. Where the disk folds case, `asked`
# may differ from it, and Edit > Warn About Name Case (on unless unticked)
# says so once (Robert, 2026-10-05).
selectSketch = (name, asked = name) ->
  await Editor.load name
  document.title = "#{name} \u2014 CoffeeBEANS"
  localStorage.setItem 'lastSketch', name
  say "opened #{name} -- you asked for #{asked}", 'sys' if asked isnt name and await beans.warnCase()
  Editor.focus()

# :e newfile -- create it if it does not exist yet (an empty sketch, the way a
# touch would leave it), then open it. Created only if still absent: one that
# appeared since the look is opened instead (sketch:create).
openSketch = (asked) ->
  found = await beans.find asked
  {name, created} = if found.exists then found else await beans.create found.name
  say "created #{name}.coffee", 'sys' if created
  await selectSketch name, found.asked

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
document.getElementById('runFresh').onclick   = -> toCanvas(); runFresh Editor.all(), Editor.name()
document.getElementById('pauseFrame').onclick = -> if status in PAUSED then continueAll() else pauseFrames()
document.getElementById('stepFrame').onclick  = stepFrame
document.getElementById('stepLine').onclick   = stepLine
document.getElementById('stop').onclick       = stop
document.getElementById('toggle').onclick     = toggleEditor
document.getElementById('open').onclick = pickSketch
beans.onOpen pickSketch

# An open dialog -- About, the report -- has the keyboard. Ctrl-E typed in
# the report's text box must not hide the editor behind it, nor F8 pause a
# sketch nobody can see; Esc and the dialog's own buttons get out.
dialogOpen = -> document.querySelector('dialog[open]')?

# The line-stepping keys are DevTools' own, and are caught before the editor
# or the prompt can see them: Ctrl-\ is a prefix in vim when Vim Keys is on,
# and a key that pauses only when the right thing has focus is no use in a
# hurry. Not with Alt as well: AltGr arrives as Ctrl+Alt on Windows, and
# AltGr+ß is how a German keyboard types a backslash.
window.addEventListener 'keydown', ((event) ->
  return if dialogOpen()
  modified = (event.ctrlKey and not event.altKey) or event.metaKey
  verb = if event.key is 'F8' or (modified and event.key is '\\')
    togglePause
  else if event.key is 'F10'
    stepLine
  return unless verb
  event.preventDefault()
  event.stopPropagation()
  verb()
), true

# Not with Alt: chordOf leaves Ctrl+Alt with a typed key to the prompt as
# AltGr, so Ctrl-Alt-E reaching here would toggle the editor from the prompt.
window.addEventListener 'keydown', (event) ->
  return unless event.ctrlKey and not event.altKey and not dialogOpen()
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
  # Not awaited: git is asked at startup with a 5s limit, and a git that
  # hangs must not hold the sketch back for it.
  beans.about().then ({version}) ->
    say "CoffeeBEANS #{version}  --  Ctrl-Enter evals the block under the cursor, > for a line, /help for the rest", 'sys'
  if params.has 'crashed'
    say "*** the app crashed (#{params.get 'crashed'}) and has restarted -- your sketch is as it was last saved ***", 'err'

  try
    names   = await beans.list()
    wanted  = params.get 'sketch'
    # The URL is how the suite drives the app, so it must not inherit
    # whatever the last hand-run session had open.
    # A name main refuses (one outside sketches/) falls through to the first
    # sketch like an unknown one, saying why, rather than leaving none open.
    asked   = if params.has 'sketch' then wanted else localStorage.getItem 'lastSketch'
    found   = if asked then await beans.find(asked).catch((error) -> {exists: no, error}) else {exists: no}
    instead = if names.length then "opening #{names[0]}" else 'nothing to open'
    if found.error
      say "#{found.error.message} -- #{instead}", 'err'
    else if wanted and not found.exists
      say "no sketch named \"#{wanted}\" -- #{instead}", 'err'
    if found.exists
      await selectSketch found.name, (if wanted then found.asked else found.name)     # only a name typed into the URL was asked for
    else if names.length
      await selectSketch names[0]
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
