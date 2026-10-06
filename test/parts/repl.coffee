# The console prompt: one line at a time into the same live worker the sketch
# runs in, answered at a yield point so a running sketch can be questioned
# without being stopped.

fsp             = require 'fs/promises'
pathTo          = require 'path'
{BrowserWindow} = require 'electron'

module.exports = (t) ->
  {js, wait, check, setDoc, evalAll, consoleText, clearConsole,
   click, status, settle, settled, ask, paths} = t

  # 1. a line comes back with its value
  await clearConsole()
  answer = await ask '6 * 7'
  check 'a line at the prompt answers with its value', answer.includes('42'),
    JSON.stringify answer.trim()

  # 2. it is the same image the sketch runs in, in both directions
  await setDoc "fromSketch = 11\n"
  await wait 500
  await clearConsole()
  await evalAll()
  await settled()
  answer = await ask 'fromSketch + 1'
  sees   = answer.includes '12'

  await clearConsole()
  await ask "fromPrompt = 'hello'"
  await setDoc "print 'sketchSees=' + fromPrompt\n"
  await wait 500
  await evalAll()
  answer = await settled()
  check 'the prompt and the sketch share one image',
    sees and answer.includes('sketchSees=hello'), "sees=#{sees} #{JSON.stringify answer.trim()}"

  # 3. a question answered between frames of a sketch that never stops, and an
  # answer that reaches back into it. This is the whole point of going through
  # shared memory rather than postMessage.
  await setDoc "screen 320, 200\nbuffer.on\nticks = 0\nstep = 1\nloop\n  ticks += step\n  cls()\n  buffer.swap\n"
  await wait 500
  await clearConsole()
  await evalAll()
  await wait 400
  went  = await status()

  count = (text) -> Number /(-?\d+)/.exec(text)?[1] ? -1

  # Asked until it has actually ticked once, so the first reading is not a
  # race with the sketch's first frame.
  deadline = Date.now() + 5000
  loop
    first = await ask 'ticks'
    break if count(first) > 0 or Date.now() > deadline

  await wait 300
  second = await ask 'ticks'
  await ask 'step = 100'
  await wait 300
  third  = await ask 'ticks'
  still  = await status()
  await click 'stop'
  await settle()

  a = count first
  b = count second
  c = count third
  check 'the prompt answers a running sketch between frames',
    went is 'running' and still is 'running' and 0 < a < b,
    "first=#{a} #{JSON.stringify first} second=#{b} #{JSON.stringify second} status=#{still}"
  check 'and what it changes reaches the running sketch',
    c - b > (b - a) * 5, "before=#{b} after=#{c} (step went 1 -> 100)"

  # 4. a bad line is reported and the prompt still works after it
  await clearConsole()
  broken = await ask 'this is not coffee ('
  after  = await ask '1 + 1'
  check 'a bad line is reported without wedging the prompt',
    broken.length > 0 and not broken.includes('2') and after.includes('2'),
    "broken=#{JSON.stringify broken.trim()} after=#{JSON.stringify after.trim()}"

  # 5. the keystroke path, and the history behind it
  await clearConsole()
  typed = (line) -> js """
    const p = document.getElementById('promptLine')
    p.value = #{JSON.stringify line}
    p.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }))
    return true
  """
  arrow = (key) -> js """
    document.getElementById('promptLine')
      .dispatchEvent(new KeyboardEvent('keydown', { key: '#{key}', bubbles: true }))
    return document.getElementById('promptLine').value
  """
  await typed '3 + 4'
  await wait 400
  text    = await consoleText()
  recalled = await arrow 'ArrowUp'
  cleared  = await arrow 'ArrowDown'
  check 'Enter runs the line and Up recalls it',
    text.includes('7') and recalled is '3 + 4' and cleared is '',
    "console=#{JSON.stringify text.trim()} up=#{JSON.stringify recalled} down=#{JSON.stringify cleared}"

  # --- readline's keys -----------------------------------------------------------

  # Real key events, through Chromium's own input path rather than
  # dispatchEvent, so a key the prompt fails to claim still does whatever the
  # browser would do with it -- select all, for one. They are queued, not
  # delivered by the time sendInputEvent returns, so each press waits for its
  # keyup to arrive.
  #
  # Menu accelerators do not see these: Ctrl-R sent this way reloaded nothing
  # even from the canvas (Claude, 2026-10-05). So whether the prompt's Ctrl-R
  # beats the View menu's reload is not something this part can show. It was
  # measured with real X keys instead (xdotool, by Claude, 2026-10-05, Linux
  # X11 only): with the prompt's preventDefault a real Ctrl-R searches and
  # does not reload; without it, the window reloads. Windows and macOS are
  # unmeasured.
  win  = BrowserWindow.getAllWindows()[0]
  MODS = C: 'control', M: 'alt', S: 'shift'

  until_ = (probe, limit = 5000) ->
    deadline = Date.now() + limit
    loop
      value = await probe()
      return value if value or Date.now() > deadline
      await wait 20

  keyups = -> js """
    if (!window.__keyupsCounted) {
      window.__keyupsCounted = true
      window.__keyups = 0
      window.addEventListener('keyup', () => window.__keyups++, true)
    }
    return window.__keyups
  """

  send = (keyCode, modifiers, char) ->
    before = await keyups()
    win.webContents.sendInputEvent {type: 'keyDown', keyCode, modifiers}
    win.webContents.sendInputEvent {type: 'char',    keyCode, modifiers} if char
    win.webContents.sendInputEvent {type: 'keyUp',   keyCode, modifiers}
    await until_ -> (await keyups()) > before

  # 'C-S-Backspace' is Ctrl+Shift+Backspace; the last part is the key.
  press = (chords...) ->
    for chord in chords
      parts = chord.split /-(?=.)/
      await send parts.pop(), (MODS[mod] for mod in parts), no
    undefined

  typeText = (text) -> await send character, [], yes for character in text

  promptAt = (value, from, to = from) -> js """
    const p = document.getElementById('promptLine')
    p.focus()
    p.value = #{JSON.stringify value}
    p.setSelectionRange(#{from}, #{to})
    return true
  """
  promptNow = -> js """
    const p = document.getElementById('promptLine')
    return {value: p.value, from: p.selectionStart, to: p.selectionEnd,
            mark: document.getElementById('promptMark').textContent,
            focused: document.activeElement === p}
  """

  # 6. each binding against readline's own behaviour (lib/internal/readline/
  # interface.js in Node 24). Option is not Meta on a Mac, so the Alt rows
  # are skipped there. Ctrl-Shift-Backspace has no row: Chromium on Linux
  # already deletes to the start for it, so a row would pass without the
  # binding (found by Claude, 2026-10-05).
  EDITS = [
    # what it does                          line            caret  keys                         after          caret
    ['Ctrl-A goes to the start of the line',  'hello world',   5,   ['C-a'],                     'hello world',   0]
    ['Ctrl-E goes to the end of the line',    'hello world',   5,   ['C-e'],                     'hello world',  11]
    ['Ctrl-B goes back a character',          'hello world',   5,   ['C-b'],                     'hello world',   4]
    ['Ctrl-B steps over a whole emoji',       'a\u{1F600}b',   3,   ['C-b'],                     'a\u{1F600}b',   1]
    ['Ctrl-F goes forward a character',       'hello world',   5,   ['C-f'],                     'hello world',   6]
    ['Ctrl-H deletes left',                   'hello world',   5,   ['C-h'],                     'hell world',    4]
    ['Ctrl-D deletes right',                  'hello world',   5,   ['C-d'],                     'helloworld',    5]
    ['Ctrl-U deletes to the start',           'hello world',   5,   ['C-u'],                     ' world',        0]
    ['Ctrl-K deletes to the end',             'hello world',   5,   ['C-k'],                     'hello',         5]
    ['Ctrl-Shift-Delete deletes to the end',  'hello world',   5,   ['C-S-Delete'],              'hello',         5]
    ['Ctrl-W deletes the word before',        'foo bar baz',  11,   ['C-w'],                     'foo bar ',      8]
    ['Alt-B goes back a word',                'foo bar baz',  11,   ['M-b'],                     'foo bar baz',   8]
    ['Alt-F goes forward a word',             'foo bar baz',   0,   ['M-f'],                     'foo bar baz',   4]
    ['Alt-D deletes the word after',          'foo bar baz',   4,   ['M-d'],                     'foo baz',       4]
    ['Alt-Delete deletes the word after',     'foo bar baz',   4,   ['M-Delete'],                'foo baz',       4]
    ['Alt-Backspace deletes the word before', 'foo bar baz',   7,   ['M-Backspace'],             'foo  baz',      4]
    ['Ctrl-Y yanks back what Ctrl-K cut',     'hello world',   5,   ['C-k', 'C-a', 'C-y'],       ' worldhello',   6]
    ['Alt-Y swaps the yank for the cut before it', 'one two',  3,   ['C-k', 'C-u', 'C-y', 'M-y'], ' two',         4]
  ]
  for [what, line, at, keys, after, landed] in EDITS
    continue if process.platform is 'darwin' and keys.some (key) -> key.startsWith 'M-'
    await promptAt line, at
    await press keys...
    got = await promptNow()
    check "#{what}, at the prompt", got.value is after and got.from is landed and got.to is landed,
      JSON.stringify got

  # 7. edits keep the input's own undo, which assigning the value would wipe
  await promptAt 'hello world', 5
  await press 'C-u'
  cut = (await promptNow()).value
  await press 'C-z'
  back = (await promptNow()).value
  check 'Ctrl-Z undoes a Ctrl-U', cut is ' world' and back is 'hello world',
    "after Ctrl-U #{JSON.stringify cut}, after Ctrl-Z #{JSON.stringify back}"

  # 7b. a click moves the caret out from under a yank, so Alt-Y after one has
  # nothing to swap. The kill ring outlives promptAt, which only sets the value.
  clicks = -> js """
    if (!window.__mouseupsCounted) {
      window.__mouseupsCounted = true
      window.__mouseups = 0
      window.addEventListener('mouseup', () => window.__mouseups++, true)
    }
    return window.__mouseups
  """
  clickAt = (x, y) ->
    before = await clicks()
    win.webContents.sendInputEvent {type: 'mouseDown', x, y, button: 'left', clickCount: 1}
    win.webContents.sendInputEvent {type: 'mouseUp',   x, y, button: 'left', clickCount: 1}
    await until_ -> (await clicks()) > before

  await promptAt 'one two', 3
  await press 'C-k', 'C-u'
  await promptAt 'xyz', 0
  await press 'C-y'
  yanked = await promptNow()
  box = await js """
    const r = document.getElementById('promptLine').getBoundingClientRect()
    return {x: Math.round(r.right - 3), y: Math.round(r.top + r.height / 2)}
  """
  await clickAt box.x, box.y
  clicked = await promptNow()
  await press 'M-y'
  popped = await promptNow()
  unless process.platform is 'darwin'
    check 'Alt-Y after a click elsewhere in the line leaves the line alone',
      yanked.value is 'onexyz' and clicked.from is 6 and popped.value is 'onexyz',
      "yanked=#{JSON.stringify yanked} clicked=#{JSON.stringify clicked} after Alt-Y=#{JSON.stringify popped}"

  # 7c. Ctrl+Alt is only AltGr when it types something; with Enter it is not Enter
  await promptAt 'hello', 5
  await press 'C-M-Enter'
  check 'Ctrl-Alt-Enter does not run the line', (await promptNow()).value is 'hello',
    JSON.stringify await promptNow()

  # 8. Ctrl-C: the ordinary key where there is a selection, readline's
  # .break where there is not
  await js """
    if (!window.__copiesCounted) {
      window.__copiesCounted = true
      window.__copies = 0
      document.addEventListener('copy', () => window.__copies++)
    }
    return true
  """
  copiesBefore = await js "return window.__copies"
  await promptAt 'hello', 0, 2
  await press 'C-c'
  kept   = await promptNow()
  copied = (await js "return window.__copies") - copiesBefore
  await promptAt 'hello', 2
  await press 'C-c'
  dropped = await promptNow()
  check 'Ctrl-C copies a selection, and without one clears the line',
    kept.value is 'hello' and kept.from is 0 and kept.to is 2 and copied is 1 and dropped.value is '',
    "with selection #{JSON.stringify kept} copies=#{copied}; without #{JSON.stringify dropped}"

  # 9. the prompt's keys beat the app's, but only while it has focus
  solo = -> js "return document.getElementById('main').classList.contains('solo')"
  was  = await solo()
  await promptAt 'hello', 0
  await press 'C-e'
  inPrompt = await solo()
  await js "document.getElementById('stage').focus(); return true"
  await press 'C-e'
  fromCanvas = await solo()
  await press 'C-e' if fromCanvas isnt was
  check 'Ctrl-E in the prompt is end of line, and from the canvas still shows or hides the editor',
    inPrompt is was and fromCanvas isnt was and (await solo()) is was,
    "solo before=#{was} after prompt Ctrl-E=#{inPrompt} after canvas Ctrl-E=#{fromCanvas}"

  # Ctrl+Alt with a typed key is left to the prompt as AltGr, so the window
  # must not take it as Ctrl-E either.
  await promptAt 'hello', 0
  await press 'C-M-e'
  altE = await solo()
  check 'Ctrl-Alt-E at the prompt does not show or hide the editor',
    altE is was, "solo before=#{was} after=#{altE}"

  # 10. history, typed for real so Enter is the thing that records it
  enter = (line) ->
    await promptAt line, line.length
    await press 'Enter'
    await until_ -> not await js "return Prompt.pending()"
    await t.quiet()
  await enter 'alpha = 1'
  await enter 'beta = 2'
  await enter 'alpha + beta'

  await promptAt '', 0
  seen = []
  for key in ['C-p', 'C-p', 'C-n']
    await press key
    seen.push (await promptNow()).value
  check 'Ctrl-P and Ctrl-N walk the history', seen.join('|') is 'alpha + beta|beta = 2|alpha + beta',
    JSON.stringify seen

  # 11. reverse-i-search, as the node REPL has it
  await promptAt 'draft', 5
  await press 'C-r'
  await typeText 'alp'
  first  = await promptNow()
  await press 'C-r'
  second = await promptNow()
  await press 'Escape'
  undone = await promptNow()
  check 'Ctrl-R finds the newest match, again the one before, and Esc puts the line back',
    first.value is 'alpha + beta' and first.mark is 'bck-i-search: alp_' and
    second.value is 'alpha = 1' and second.from is 0 and
    undone.value is 'draft' and undone.from is 5 and undone.mark is '>',
    "first=#{JSON.stringify first} second=#{JSON.stringify second} esc=#{JSON.stringify undone}"

  await promptAt 'draft', 5
  await press 'C-r'
  await typeText 'alp'
  await press 'C-r', 'C-s'
  forward = await promptNow()
  await press 'Escape'
  check 'Ctrl-S turns the search round, back to the newer match',
    forward.value is 'alpha + beta' and forward.mark is 'fwd-i-search: alp_',
    JSON.stringify forward

  await promptAt '', 0
  await press 'C-r'
  await typeText 'zzz'
  failed = await promptNow()
  await press 'C-c'
  check 'a search that finds nothing says so', failed.mark is 'failed-bck-i-search: zzz_' and failed.value is '',
    JSON.stringify failed

  before = (await consoleText()).length
  await promptAt '', 0
  await press 'C-r'
  await typeText 'beta'
  await press 'Enter'
  await until_ -> not await js "return Prompt.pending()"
  await t.quiet()
  ran   = (await consoleText())[before..]
  after = await promptNow()
  check 'Enter takes the match and runs it',
    ran.includes('> alpha + beta') and ran.includes('3') and after.value is '' and after.mark is '>',
    "console=#{JSON.stringify ran} prompt=#{JSON.stringify after}"

  # Half a character -- a dead key -- leaves the search going, and a
  # character outside the BMP, one key but two UTF-16 units, extends it.
  # Dispatched, not sent: sendInputEvent cannot make a keydown whose key is
  # outside the BMP or is Dead (tried by Claude, 2026-10-05: the emoji
  # arrived as some other key and was then typed into the line).
  await enter "smile = '\u{1F600}!'"
  await promptAt '', 0
  await press 'C-r'
  await js """
    const p = document.getElementById('promptLine')
    for (const key of ['Dead', '\u{1F600}'])
      p.dispatchEvent(new KeyboardEvent('keydown', {key, bubbles: true, cancelable: true}))
    return true
  """
  wide = await promptNow()
  await press 'Escape'
  check 'Ctrl-R carries on past a dead key and searches for a character outside the BMP',
    wide.value is "smile = '\u{1F600}!'" and wide.mark is 'bck-i-search: \u{1F600}_',
    JSON.stringify wide

  # 11b. Up and Down search the history by what is left of the caret, as the
  # node REPL does (lib/internal/readline/interface.js and lib/internal/repl/
  # history.js in Node 24.20). Each walk starts from the bottom of the
  # history: Ctrl-C on an empty line puts it there.
  await enter line for line in ['circle 4, 5, 6', 'print 2', 'circle 1, 2, 3', 'print 1', 'print 1']
  fromTheBottom = (line, at = line.length) ->
    await promptAt '', 0
    await press 'C-c'
    await promptAt line, at
  pressing = (keys...) ->
    shown = []
    for key in keys
      await press key
      shown.push (await promptNow()).value
    shown

  await fromTheBottom 'ciXYZ', 2
  ups   = await pressing 'Up', 'Up', 'Up'
  downs = await pressing 'Down', 'Down', 'Down'
  back  = await promptNow()
  check 'with ci typed, Up skips print 1 to reach circle 1, 2, 3', ups[0] is 'circle 1, 2, 3', JSON.stringify ups
  check 'Up never leaves the prefix, and stays on the oldest match',
    ups.join('|') is 'circle 1, 2, 3|circle 4, 5, 6|circle 4, 5, 6', JSON.stringify ups
  check 'Down walks back to the line as it was typed, caret and all, and no further',
    downs.join('|') is 'circle 1, 2, 3|ciXYZ|ciXYZ' and back.from is 2 and back.to is 2,
    JSON.stringify {downs, back}

  await fromTheBottom ''
  plain = await pressing 'Up', 'Up'
  check 'with nothing typed, Up is the last line, and a run of repeats is one step',
    plain.join('|') is 'print 1|circle 1, 2, 3', JSON.stringify plain

  # Ended, the next Up asks for lines starting with the line as it now is,
  # from where the walk got to. Still walking, it would find circle 4, 5, 6.
  await fromTheBottom 'ci'
  await press 'Up'
  await press 'C-u'
  keyed = await pressing 'Up'
  await fromTheBottom 'ci'
  await press 'Up'
  await js """
    const p = document.getElementById('promptLine')
    p.select()
    document.execCommand('insertText', false, '')
    return true
  """
  pasted = await pressing 'Up'
  await fromTheBottom 'ci'
  await press 'Up'
  escaped = await pressing 'Escape', 'Up'
  check 'an edit, one with no key of its own, or Esc, ends the walk',
    keyed[0] is 'print 2' and pasted[0] is 'print 2' and escaped.join('|') is 'circle 1, 2, 3|circle 1, 2, 3',
    JSON.stringify {keyed, pasted, escaped}

  # A recalled line, edited, is the one Down comes back to: node gives back
  # pr here. So does a search started from an edited line and taken by Down.
  await fromTheBottom ''
  await press 'Up', 'Up', 'C-u'
  await typeText 'pr'
  edited = await pressing 'Up', 'Down', 'Down'
  await fromTheBottom ''
  await press 'Up', 'C-u'
  await typeText 'zz'
  await press 'C-r'
  await typeText '2'
  searched = await pressing 'Down', 'Down'
  check 'Down comes back to a recalled line as it was edited, not to the line before the walk',
    edited.join('|') is 'print 2|print 1|pr' and searched.join('|') is 'print 1|zz',
    JSON.stringify {edited, searched}

  # Node's Ctrl-P and Ctrl-N are its history keys without the prefix: they
  # end the walk and step through every line, repeats passed over.
  await fromTheBottom 'ci'
  steps = await pressing 'Up', 'C-p', 'C-n', 'C-n', 'C-n'
  check 'Ctrl-P and Ctrl-N walk every line, as node\'s do, and end a walk by prefix',
    steps.join('|') is 'circle 1, 2, 3|print 2|circle 1, 2, 3|print 1|ci', JSON.stringify steps

  # A search taken by Up walks every line from the match, as node's does --
  # not those starting with "circle 1, 2, ", left of where the match put the
  # caret. And Down from the newest line comes back to the one from before
  # the search.
  await fromTheBottom 'draft'
  await press 'C-r'
  await typeText '3'
  await press 'Up'
  fromMatch = await promptNow()
  await fromTheBottom 'draft'
  await press 'C-r'
  await typeText '1'
  await press 'Down'
  drafted = await promptNow()
  check 'Up or Down takes a reverse search\'s match and walks on from it',
    fromMatch.value is 'print 2' and fromMatch.mark is '>' and
      drafted.value is 'draft' and drafted.from is 5 and drafted.mark is '>',
    JSON.stringify {fromMatch, drafted}
  await fromTheBottom ''

  # 12. Ctrl-L clears the console, as it clears the screen
  await promptAt '', 0
  had = (await consoleText()).length
  await press 'C-l'
  check 'Ctrl-L clears the console', had > 0 and (await consoleText()) is '',
    "before=#{had} after=#{JSON.stringify await consoleText()}"

  # 13. the keys that work from anywhere still work from the prompt. These
  # guard against the prompt swallowing them; they pass against the code
  # before readline's keys too.
  await setDoc "screen 320, 200\nbuffer.on\nloop\n  cls()\n  buffer.swap\n"
  await wait 500
  await evalAll()
  await until_ -> (await status()) is 'running'
  # :eval hands the canvas the keyboard a tick late; take it back after that.
  await until_ -> js "return document.activeElement.id === 'stage'"
  await promptAt '', 0
  # AltGr+ß types a backslash on a German keyboard, and on Windows AltGr
  # is Ctrl+Alt: that must reach the prompt, not pause. Chromium types
  # nothing for a sent Ctrl+Alt character, so the check is that the key got
  # past the window's pause listener, which stops what it takes.
  await js """
    window.__backslashes = 0
    window.addEventListener('keydown', (e) => { if (e.key === '\\\\') window.__backslashes++ })
    return true
  """
  await press 'C-M-\\'
  passedOn = await js "return window.__backslashes"
  check 'Ctrl-Alt-\\ is left for typing rather than pausing',
    passedOn is 1 and (await status()) is 'running',
    "reached the window's bubble phase #{passedOn} times, status=#{await status()}"
  await promptAt '', 0
  steps = []
  for [key, wanted] in [['F8', 'line paused'], ['C-\\', 'running'], ['F10', 'line paused'], ['F8', 'running'], ['C-.', 'ready']]
    await press key
    steps.push "#{key}:#{await until_ (-> s = await status(); s if s is wanted), 10000}"
  focusedAfter = (await promptNow()).focused
  check 'F8, Ctrl-\\, F10 and Ctrl-. still work with the prompt focused',
    steps.join(' ') is 'F8:line paused C-\\:running F10:line paused F8:running C-.:ready',
    "#{steps.join ' '} prompt still focused=#{focusedAfter} console=#{JSON.stringify (await consoleText())[-200..]}"
  await setDoc ''

  # --- Tab ---------------------------------------------------------------------

  # Bash's Tab (AGENTS.md, Tab completion). Real Tab keys, so a Tab the prompt
  # failed to claim would move the focus instead. Every Tab ends in an answer
  # or a beep, so the wait is for the question to be back in, then the line.
  beeps = -> js "return globalThis.Prompt.beeps ? Prompt.beeps() : -1"
  # Names of its own: this whole part is one scope, and `before` and `got`
  # are already taken above.
  tab = (line) ->
    beepsBefore = await beeps()
    await promptAt line, line.length
    await press 'Tab'
    await until_ -> not await js "return Prompt.pending()"
    tabbed = await promptNow()
    tabbed.beeped = (await beeps()) - beepsBefore
    tabbed
  # The completion list (T2), or null where there is none, as in the code
  # before it.
  listNow = -> js """
    const list = document.getElementById('completions')
    if (!list) return null
    const rows = [...list.children]
    return {open: !list.hidden, names: rows.map((row) => row.textContent),
            chosen: rows.findIndex((row) => row.classList.contains('chosen'))}
  """

  await setDoc """
counter = hits: 0
Object.defineProperty counter, 'probe', get: ->
  counter.hits += 1
  deep: 1
ball  = velocity: 1, x: 2
world = ball: ball
myWidget = 1
pan = pup = 1
"""
  await wait 500
  await evalAll()
  await settled()
  await clearConsole()

  # 14. a unique prefix finishes, from each place a name can come from
  unique = [['myWid', 'myWidget'], ['randomi', 'randomize'], ['world.ball.vel', 'world.ball.velocity'],
            ['x = rectF', 'x = rectFill'], ['/ru', '/run'], [':ru', ':run'], [' /ru', ' /run'],
            ['parseFl', 'parseFloat'], ['Math.hyp', 'Math.hypot'], ['x = JSON.stri', 'x = JSON.stringify']]
  for [typed, wanted] in unique
    got = await tab typed
    check "Tab finishes #{JSON.stringify typed}", got.value is wanted and got.from is wanted.length and
      got.focused and got.beeped is 0, JSON.stringify got

  # A command's arguments are not CoffeeScript: the worker's names are not
  # offered there, though `myWidget` is one.
  argued = await tab '/e myWid'
  check 'Tab after a command name does not offer the worker\'s names',
    argued.value is '/e myWid' and argued.beeped is 1, JSON.stringify argued

  # 15. ambiguous: as far as they agree, a beep, and a second Tab opens the
  # list of them above the prompt -- not printed into the console, which is
  # what a second Tab did before T2.
  first     = await tab 'circ'
  firstList = await listNow()
  before    = (await consoleText()).length
  await press 'Tab'
  await t.quiet()
  said   = (await consoleText())[before..]
  opened = await listNow()
  check 'an ambiguous Tab finishes as far as every name agrees, and beeps',
    first.value is 'circle' and first.beeped is 1, JSON.stringify first
  check 'a second Tab opens the list of them above the prompt, the first chosen, and prints nothing',
    firstList? and not firstList.open and opened?.open and opened.names[0] is 'circle' and
      'circleFill' in opened.names and opened.chosen is 0 and said is '' and (await promptNow()).value is 'circle',
    JSON.stringify {firstList, opened, said}
  await press 'Escape'

  # Any other key in between, even one that comes back to the same line and
  # caret, makes the next Tab ask again rather than open what it had.
  await press 'C-a', 'C-e'
  beepsAt = await beeps()
  await press 'Tab'
  await until_ -> not await js "return Prompt.pending()"
  await t.quiet()
  reopened = await listNow()
  check 'a key between two Tabs means the second asks again instead of listing',
    reopened? and not reopened.open and (await beeps()) - beepsAt is 1, JSON.stringify reopened

  # Nearest first: the image's names, then CoffeeBEANS's, then JavaScript's,
  # alphabetical only within each. `pup` sorts after `print`, so a list sorted
  # as a whole would put it there.
  # The first Tab opens the list itself when the names are too many for one
  # line, which depends on the window's width; a second Tab then would take
  # a name rather than open it.
  await tab 'p'
  await press 'Tab' unless (await listNow())?.open
  listed = (await listNow())?.names ? []
  await press 'Escape'
  ranked = ['pan', 'pup', 'pget', 'print', 'parseFloat', 'parseInt'].map (name) -> listed.indexOf name
  check 'Tab lists the sketch\'s names, then CoffeeBEANS\'s, then JavaScript\'s',
    -1 not in ranked and ranked.every((at, i) -> i is 0 or at > ranked[i - 1]), JSON.stringify listed

  # 16. the worker's machinery and CoffeeBEANS's plumbing are never offered:
  # JavaScript's names come from a list, not from whatever globalThis holds.
  # structuredClone was on it, and made `st` an ambiguous `stamp`.
  hidden = ['Atom', 'postMess', 'sel', 'onmess', 'requestAnim', 'WebAss', 'REP', 'REPL.se', 'toCol', 'LAYO',
            'hsvI', 'ColorB', 'Interr', 'stru']
  strays = []
  for typed in hidden
    stray = await tab typed
    strays.push stray unless stray.value is typed and stray.beeped is 1 and stray.focused
  check 'Tab does not offer the worker\'s globals or the runtime\'s plumbing', strays.length is 0,
    JSON.stringify strays

  # A getter on a JavaScript root is named and never run: Map.prototype.size
  # throws when read off the prototype, so running it would print an error.
  await clearConsole()
  size    = await tab 'Map.prototype.si'
  through = await tab 'Map.prototype.size.toF'
  await t.quiet()
  said = await consoleText()
  check 'Tab names a getter on a JavaScript root and never runs it',
    size.value is 'Map.prototype.size' and size.beeped is 0 and
      through.value is 'Map.prototype.size.toF' and through.beeped is 1 and said.trim() is '',
    "size=#{JSON.stringify size} through=#{JSON.stringify through} said=#{JSON.stringify said}"

  # 17. a getter is named but never run, and never walked through
  named   = await tab 'counter.pr'
  through = await tab 'counter.probe.de'
  hits    = await ask "'hits=' + counter.hits"
  check 'Tab names a getter, will not walk through one, and never runs it',
    named.value is 'counter.probe' and through.value is 'counter.probe.de' and through.beeped is 1 and
      hits.includes('"hits=0"'), "named=#{JSON.stringify named} through=#{JSON.stringify through} hits=#{JSON.stringify hits}"

  # The runtime's own: mouse.wheel consumes the movement it reports, so a Tab
  # that read it would leave nothing for the line after.
  await js """
    document.getElementById('stage').dispatchEvent(new WheelEvent('wheel', {deltaY: 3, bubbles: true, cancelable: true}))
    return true
  """
  wheel = await tab 'mouse.whe'
  moved = await ask 'mouse.wheel'
  check 'Tab names a runtime getter, mouse.wheel, without consuming it',
    wheel.value is 'mouse.wheel' and wheel.beeped is 0 and moved is '> mouse.wheel3',
    "wheel=#{JSON.stringify wheel} moved=#{JSON.stringify moved}"

  # Tab in a reverse search takes the match and completes the word at the
  # caret, which the search leaves at the start of what it found.
  await ask 'myWid +1'
  await promptAt '', 0
  await press 'C-r'
  await typeText ' '
  found = await promptNow()
  await press 'Tab'
  await until_ -> not await js "return Prompt.pending()"
  searched = await promptNow()
  check 'Tab in a reverse search ends it and completes at the match',
    found.value is 'myWid +1' and found.from is 5 and
      searched.value is 'myWidget +1' and searched.from is 8 and searched.mark is '>',
    "found=#{JSON.stringify found} after=#{JSON.stringify searched}"

  # 18. a running sketch's own locals, lent to the question as the prompt's
  # are; a question still out makes Tab beep rather than queue; and an answer
  # to a line that has changed since is dropped. The sketch yields only
  # every half second, so a question stays out long enough to see. The
  # change goes in the same tick as the Tab, so the answer cannot beat it.
  await setDoc """
slowLocal = 1
loop
  until0 = Date.now() + 500
  null while Date.now() < until0
  buffer.swap
"""
  await wait 500
  await evalAll()
  await until_ -> (await status()) is 'running'
  local = await tab 'slowLoc'
  check 'Tab finishes a running sketch\'s own local', local.value is 'slowLocal', JSON.stringify local

  tabAndType = (line, then_) -> js """
    const p = document.getElementById('promptLine')
    p.focus()
    p.value = #{JSON.stringify line}
    p.setSelectionRange(p.value.length, p.value.length)
    p.dispatchEvent(new KeyboardEvent('keydown', {key: 'Tab', bubbles: true, cancelable: true}))
    const out = Prompt.pending()
    p.value = #{JSON.stringify then_}
    return out
  """
  wasOut = await tabAndType 'slowLoc', 'slowLoc + 1'
  await until_ -> not await js "return Prompt.pending()"
  await t.quiet()
  stale = await promptNow()
  check 'an answer that arrives after the line has changed is dropped',
    wasOut and stale.value is 'slowLoc + 1', "asked=#{wasOut} #{JSON.stringify stale}"

  # The line and caret stand still when the focus leaves, so they cannot be
  # what says the answer is stale: a completion typed into the editor would
  # land in the sketch, and the autosave would write it to disk.
  sketchFile = pathTo.join paths.sketches, "#{await js 'return Editor.name()'}.coffee"
  docBefore  = await js "return Editor.all()"
  diskBefore = await fsp.readFile sketchFile, 'utf8'
  leftOut = await js """
    const p = document.getElementById('promptLine')
    p.focus()
    p.value = 'slowLoc'
    p.setSelectionRange(7, 7)
    p.dispatchEvent(new KeyboardEvent('keydown', {key: 'Tab', bubbles: true, cancelable: true}))
    const out = Prompt.pending()
    Editor.focus()
    return out
  """
  await until_ -> not await js "return Prompt.pending()"
  await t.quiet()
  await wait 500          # past the editor's 250ms autosave
  docAfter  = await js "return Editor.all()"
  diskAfter = await fsp.readFile sketchFile, 'utf8'
  left      = await promptNow()
  check 'an answer that arrives after the focus has left the prompt is dropped, not typed into the editor',
    leftOut and docAfter is docBefore and diskAfter is diskBefore and left.value is 'slowLoc',
    "asked=#{leftOut} doc=#{JSON.stringify docAfter} disk=#{JSON.stringify diskAfter} prompt=#{JSON.stringify left}"

  # In one tick for the same reason: the line's answer cannot get in first.
  before  = await beeps()
  refused = await js """
    Prompt.ask('slowLocal')
    const p = document.getElementById('promptLine')
    p.focus()
    p.value = 'slowLoc'
    p.setSelectionRange(7, 7)
    p.dispatchEvent(new KeyboardEvent('keydown', {key: 'Tab', bubbles: true, cancelable: true}))
    return {value: p.value, out: Prompt.pending()}
  """
  beeped = (await beeps()) - before
  await until_ -> not await js "return Prompt.pending()"
  await t.quiet()
  after = await promptNow()
  check 'Tab while a line is out beeps and does not queue',
    beeped is 1 and refused.out and refused.value is 'slowLoc' and after.value is 'slowLoc',
    "beeped=#{beeped} refused=#{JSON.stringify refused} after=#{JSON.stringify after}"
  await click 'stop'
  await settle()

  # 19. a line gives way to nothing but an answer in progress. This sketch
  # has no yield point until space is held, so a Tab's question sits there
  # unclaimed; the line after it takes its place instead of being refused.
  await setDoc """
gate = 1
loop
  null until keys.down 'space'
  buffer.swap
"""
  await wait 500
  await evalAll()
  await until_ -> (await status()) is 'running'
  before   = (await consoleText()).length
  withdrew = await js """
    const p = document.getElementById('promptLine')
    p.focus()
    p.value = 'gat'
    p.setSelectionRange(3, 3)
    p.dispatchEvent(new KeyboardEvent('keydown', {key: 'Tab', bubbles: true, cancelable: true}))
    const tabOut = Prompt.pending()
    Prompt.ask('gate + 41')
    return {tabOut, value: p.value}
  """
  await t.key 'keydown', 'Space'
  await until_ -> not await js "return Prompt.pending()"
  await t.key 'keyup', 'Space'
  await t.quiet()
  gave = (await consoleText())[before..]
  check 'a line withdraws a Tab the worker has not claimed, and is answered',
    withdrew.tabOut and gave.includes('42') and not gave.includes('still') and
      (await promptNow()).value is 'gat',
    "#{JSON.stringify withdrew} console=#{JSON.stringify gave}"

  # Line after line is refused as it always was. One tick, so the first
  # answer cannot be drained before the second is asked.
  before = (await consoleText()).length
  await js "Prompt.ask('1'); Prompt.ask('2'); return true"
  await t.key 'keydown', 'Space'
  await until_ -> not await js "return Prompt.pending()"
  await t.key 'keyup', 'Space'
  await t.quiet()
  twice = (await consoleText())[before..]
  check 'a line while a line is out is still refused as waiting on the last line',
    twice.includes('*** still waiting on the last line ***'), JSON.stringify twice
  await click 'stop'
  await settle()

  # Once the worker has claimed the Tab it has to finish, and the line is
  # refused -- saying so, not claiming a line was out. An author's Proxy is
  # the one thing a Tab runs, which is what makes this window wide enough to
  # see; the trap's print says the worker is inside it.
  await setDoc """
slowProxy = new Proxy {}, ownKeys: (target) ->
  print 'claimed'
  until0 = Date.now() + 1500
  null while Date.now() < until0
  Reflect.ownKeys target
done = 1
"""
  await wait 500
  await evalAll()
  await settled()
  await clearConsole()
  await js """
    const p = document.getElementById('promptLine')
    p.focus()
    p.value = 'slowProxy.'
    p.setSelectionRange(10, 10)
    p.dispatchEvent(new KeyboardEvent('keydown', {key: 'Tab', bubbles: true, cancelable: true}))
    return true
  """
  claimed = await until_ -> (await consoleText()).includes 'claimed'
  await js "Prompt.ask('3 * 3'); return true"
  await until_ -> not await js "return Prompt.pending()"
  await t.quiet()
  busy = await consoleText()
  check 'a line while the worker is answering Tab is refused, and says that is why',
    claimed and busy.includes('*** still answering Tab ***') and not busy.includes('last line'),
    JSON.stringify busy

  # 20. line paused, Tab asks the paused frame: these names live nowhere else
  await setDoc """
screen 320, 200
turn = (angleDelta) ->
  vec = magnitude: angleDelta
  parsed = angleDelta
  breakpoint
  vec
turn 5
"""
  await wait 500
  await evalAll()
  paused = await until_ (-> (await status()) is 'line paused'), 10000
  await until_ -> js "return !document.getElementById('vars').hidden"
  param  = await tab 'angleDel'
  member = await tab 'vec.magn'
  check 'line paused, Tab finishes the paused frame\'s names and their members',
    paused and param.value is 'angleDelta' and member.value is 'vec.magnitude',
    "paused=#{paused} param=#{JSON.stringify param} member=#{JSON.stringify member}"

  # The paused frame's names come before JavaScript's, though `parsed` sorts
  # after `parseFloat`.
  common = await tab 'pars'
  await press 'Tab'
  listed = (await listNow())?.names ? []
  await press 'Escape'
  check 'line paused, Tab lists the frame\'s names before JavaScript\'s',
    common.value is 'parse' and listed.join(' ') is 'parsed parseFloat parseInt', JSON.stringify {common, listed}

  # A line that does not compile, typed in the paused frame, says why.
  unparsed = await ask 'this is not coffee ('
  check 'line paused, a line that does not compile shows the error',
    unparsed.includes('missing )') and (await status()) is 'line paused', JSON.stringify unparsed

  # 21. and nothing reaches V8 while the prompt is evaluating in that frame:
  # Tab beeps, nothing is sent after, and Tab works again once it is back
  await js "Prompt.ask('n = 0; loop then n += 1'); return true"
  await until_ -> js "return Prompt.pending()"
  await promptAt 'angleDel', 8
  before = await beeps()
  await press 'Tab'
  beeped = (await beeps()) - before
  await until_ (-> not await js "return Prompt.pending()"), 15000
  await t.quiet()
  held  = await promptNow()
  again = await tab 'angleDel'
  check 'Tab while the paused frame is evaluating beeps, sends nothing, and works once it is back',
    beeped is 1 and held.value is 'angleDel' and again.value is 'angleDelta',
    "beeped=#{beeped} held=#{JSON.stringify held} again=#{JSON.stringify again}"
  await js "Stepping.resume(); return true"
  await until_ (-> (await status()) is 'ready'), 10000

  # 22. Tab in a paused frame, then Stop while its evaluation is still out.
  # The trap's print says the evaluation is inside it, and it stays there
  # until the check presses x; Stop waits it out, so its answer arrives after
  # Stop. The sketch waits for y before its breakpoint, so a line sent before
  # then sits in shared memory, unclaimed, all through the pause. Both wait
  # on keys rather than the clock -- `keys.down` reads shared memory and has
  # no yield point, so it works inside an evaluation too -- because a timed
  # wait on a slow machine ran out early and let both checks pass against
  # the code they were written to catch. The clock only bounds a broken run;
  # the trap is bounded anyway, by the debugger's 3s evaluation limit.
  slowTabSketch = """
slowProxy = new Proxy {oldName: 1}, ownKeys: (target) ->
  print 'claimed'
  until1 = Date.now() + 10000
  null until keys.down('x') or Date.now() > until1
  Reflect.ownKeys target
until0 = Date.now() + 10000
null until keys.down('y') or Date.now() > until0
breakpoint
done = 1
"""
  # Dispatched at the stage without focusing it, unlike t.key: an answer is
  # offered only to a focused prompt, so moving focus would hide the very
  # stale offer the second check looks for. Held until what it lets go of is
  # over, since `keys.down` sees only a key held at the moment it looks.
  stageKey = (kind, code) -> js """
    document.getElementById('stage').dispatchEvent(new KeyboardEvent('#{kind}', { code: '#{code}', bubbles: true }))
    return true
  """
  tabPaused = -> js """
    const p = document.getElementById('promptLine')
    p.focus()
    p.value = 'slowProxy.'
    p.setSelectionRange(10, 10)
    p.dispatchEvent(new KeyboardEvent('keydown', {key: 'Tab', bubbles: true, cancelable: true}))
    return true
  """

  # A line waiting from before the pause is not taken for Tab's question:
  # the line after Stop used to take it back, and it was never answered.
  await setDoc slowTabSketch
  await wait 500
  await clearConsole()
  await evalAll()
  await until_ -> (await status()) is 'running'
  await js "Prompt.ask('6 * 7'); return true"
  lineOut = await js "return Prompt.pending()"
  await stageKey 'keydown', 'KeyY'
  waited  = await until_ (-> (await status()) is 'line paused'), 10000
  await stageKey 'keyup', 'KeyY'
  await until_ -> js "return !document.getElementById('vars').hidden"
  await tabPaused()
  inTrap = await until_ (-> (await consoleText()).includes 'claimed'), 10000
  await js """
    document.getElementById('stop').click()
    Prompt.ask('7 * 8')
    return true
  """
  await stageKey 'keydown', 'KeyX'
  await until_ (-> (await status()) is 'ready' and not await js "return Prompt.pending()"), 15000
  await stageKey 'keyup', 'KeyX'
  await t.quiet()
  heldLine = await consoleText()
  check 'a line out before a pause is not taken back by a line after a paused Tab and Stop',
    waited and lineOut and inTrap and /\b42\b/.test(heldLine) and heldLine.includes('*** still waiting on the last line ***'),
    "paused=#{waited} lineOut=#{lineOut} inTrap=#{inTrap} console=#{JSON.stringify heldLine}"

  # The paused Tab's answer, arriving after Stop and a Tab asked of the
  # worker since, belongs to the paused Tab and is not offered to the later
  # one. The worker cannot answer until the evaluation is done, so the stale
  # answer always comes first. `oldName` is the proxy's key, not a name the
  # worker could offer.
  await setDoc slowTabSketch
  await wait 500
  await clearConsole()
  await evalAll()
  await until_ -> (await status()) is 'running'
  await stageKey 'keydown', 'KeyY'
  waited = await until_ (-> (await status()) is 'line paused'), 10000
  await stageKey 'keyup', 'KeyY'
  await until_ -> js "return !document.getElementById('vars').hidden"
  await tabPaused()
  inTrap = await until_ (-> (await consoleText()).includes 'claimed'), 10000
  await js """
    document.getElementById('stop').click()
    const p = document.getElementById('promptLine')
    p.focus()
    p.value = 'old'
    p.setSelectionRange(3, 3)
    p.dispatchEvent(new KeyboardEvent('keydown', {key: 'Tab', bubbles: true, cancelable: true}))
    return true
  """
  await stageKey 'keydown', 'KeyX'
  await until_ (-> (await status()) is 'ready' and not await js "return Prompt.pending()"), 15000
  await stageKey 'keyup', 'KeyX'
  await t.quiet()
  later = await promptNow()
  check 'a paused Tab\'s answer after Stop is not offered to the Tab asked since',
    waited and inTrap and later.value isnt 'oldName' and later.value.startsWith('old'),
    "paused=#{waited} inTrap=#{inTrap} prompt=#{JSON.stringify later}"
  await setDoc ''

  # 23. A line typed while the worker is booting. The poke reaches a worker
  # still loading its modules, with nowhere yet to read the line from, and a
  # sketch with no yield point never looks again: the line sat unanswered,
  # and every later one said it was still waiting, until the next restart.
  # Run once first, so the debugger is already disarmed for an empty buffer
  # and the Run under test starts its worker in the same tick.
  await wait 400
  await click 'runFresh'
  await settle()
  await clearConsole()
  asked = await js """
    document.getElementById('runFresh').click()
    const at = document.getElementById('status').textContent
    Prompt.ask('6 * 7')
    return at
  """
  answered = await until_ (-> not await js "return Prompt.pending()"), 5000
  await t.quiet()
  text = await consoleText()
  check 'a line typed while the worker boots is answered',
    asked is 'booting' and answered and text.includes('42'),
    "status=#{asked} answered=#{answered} console=#{JSON.stringify text}"
  await settle()

  # 24. the completion list (T2). The proxy prints each time the worker lists
  # its members, which is the count of questions a Tab or the list put to
  # the worker about it.
  await setDoc """
noisy = new Proxy {alphaOne: 1, alphaTwo: 1, alphaThree: 1, betaOne: 1, betaTwo: 1}, ownKeys: (target) ->
  print 'asked'
  Reflect.ownKeys target
noisyToo = 1
"""
  await wait 500
  await evalAll()
  await settled()
  await clearConsole()
  askedOf = -> ((await consoleText()).match(/asked/g) ? []).length
  NOISY   = 'alphaOne alphaThree alphaTwo betaOne betaTwo'
  # Five names fit on a line, so the first Tab beeps and the second opens.
  # A key first, as a player's would be: a line set from here leaves the
  # last Tab's answer standing, and a Tab on the same line would open it.
  openNoisy = (line = 'noisy.') ->
    await promptAt line, line.length
    await press 'End'
    first = await tab line
    await press 'Tab'
    first

  first  = await openNoisy()
  opened = await listNow()
  await typeText 'a'
  fromA  = await listNow()
  await typeText 'lphaT'
  fromT  = await listNow()
  await typeText 'w'
  fromW  = await listNow()
  typed  = await promptNow()
  await t.quiet()
  asks   = await askedOf()
  check 'the list opens on the second Tab, narrows as letters are typed, and closes at one, asking nothing more',
    first.beeped is 1 and opened?.open and opened.names.join(' ') is NOISY and
      fromA?.open and fromA.names.length is 3 and fromT?.open and fromT.names.join(' ') is 'alphaThree alphaTwo' and
      fromW? and not fromW.open and typed.value is 'noisy.alphaTw' and asks is 1,
    JSON.stringify {first, opened, fromA, fromT, fromW, typed, asks}

  # A deletion past the word the names were asked for, or a dot, needs names
  # the list does not have: it asks again, and shows them when they come.
  await openNoisy 'noisy.alpha'
  three = await listNow()
  await t.quiet()
  asks  = await askedOf()
  await press 'Backspace', 'Backspace', 'Backspace', 'Backspace', 'Backspace'
  wider = await until_ -> l = await listNow(); l if l?.names.length is 5
  await t.quiet()
  reasked = await askedOf()
  await press 'Escape'
  await clearConsole()
  await openNoisy 'nois'
  both = await listNow()
  await typeText '.'
  members = await until_ -> l = await listNow(); l if l?.open and l.names.join(' ') is NOISY
  check 'a deletion past the word asked, or a dot, asks again and lists what it answers',
    three?.names.length is 3 and wider?.open and reasked > asks and
      both?.names.join(' ') is 'noisy noisyToo' and members? and (await promptNow()).value is 'noisy.',
    JSON.stringify {three, wider, reasked, both, members}
  await press 'Escape'

  # Up and Down are the list's while it is open, and the history's again
  # once it closes.
  earlier = await js "return Prompt.entered()"
  await openNoisy()
  await t.quiet()
  before = (await consoleText()).length
  await press 'Down', 'Down', 'Up'
  moved = await listNow()
  held  = await promptNow()
  await press 'Up', 'Up'
  wrapped = await listNow()
  await press 'Enter'
  took   = await promptNow()
  closed = await listNow()
  await t.quiet()
  ran = (await consoleText())[before..]
  check 'Up and Down move the highlight, round the ends, and leave the history alone',
    moved?.chosen is 1 and held.value is 'noisy.' and wrapped?.chosen is 4, JSON.stringify {moved, held, wrapped}
  check 'Enter takes the chosen name and does not run the line',
    took.value is 'noisy.betaTwo' and took.from is 13 and closed? and not closed.open and ran is '' and
      (await js "return Prompt.entered()").length is earlier.length,
    JSON.stringify {took, closed, ran}
  # Ctrl-P, the list's key as Up is, and one that moves no caret: a caret
  # move would close a list left open and hide the fault. Up itself would
  # prove nothing here, since nothing in the history starts with
  # noisy.betaTwo, and Ctrl-P walks every line.
  await press 'C-p'
  recalled = await promptNow()
  check 'once the list has closed, its keys are the history\'s again',
    took.value is 'noisy.betaTwo' and recalled.value is earlier.at(-1),
    JSON.stringify {took: took.value, recalled: recalled.value, last: earlier.at(-1)}

  await openNoisy()
  await press 'Down', 'Tab'
  tookTab = await promptNow()
  check 'Tab takes the chosen name', tookTab.value is 'noisy.alphaThree' and not (await listNow()).open,
    JSON.stringify tookTab

  await openNoisy()
  wasOpen = (await listNow())?.open
  await press 'Escape'
  escaped = await promptNow()
  check 'Esc closes the list and leaves the line', wasOpen and not (await listNow()).open and
    escaped.value is 'noisy.' and escaped.focused, JSON.stringify {wasOpen, escaped, list: await listNow()}

  # Taking a name that begins another leaves a word both still fit, so a
  # list that only narrowed after the take would stay open on the pair.
  await openNoisy 'nois'
  pair = await listNow()
  await press 'Enter'
  tookPrefix = await promptNow()
  check 'taking a name that begins another still closes the list',
    pair?.open and pair.names.join(' ') is 'noisy noisyToo' and pair.chosen is 0 and
      tookPrefix.value is 'noisy' and not (await listNow()).open,
    JSON.stringify {pair, tookPrefix, list: await listNow()}

  await openNoisy()
  wasOpen = (await listNow())?.open
  # Dispatched as well as moving the focus, as the input part does: in a
  # window that is not the OS's focused one, Chromium moves the focus
  # without firing blur.
  await js """
    Editor.focus()
    document.getElementById('promptLine').dispatchEvent(new FocusEvent('blur'))
    return true
  """
  away = await listNow()
  await js "document.getElementById('promptLine').focus(); return true"
  back = await listNow()
  check 'leaving the prompt closes the list, and coming back does not reopen it',
    wasOpen and away? and not away.open and not back.open, JSON.stringify {wasOpen, away, back}

  await openNoisy()
  await press 'Left'
  moved = await until_ -> l = await listNow(); l if l and not l.open
  check 'moving the caret without an edit closes the list', moved? and (await promptNow()).value is 'noisy.',
    JSON.stringify {list: await listNow(), prompt: await promptNow()}

  # A real click, so a press that took the focus from the prompt would close
  # the list before the click could choose.
  await openNoisy()
  spot = await js """
    const row = document.getElementById('completions')?.children[2]?.getBoundingClientRect()
    return row && {x: Math.round(row.left + row.width / 2), y: Math.round(row.top + row.height / 2)}
  """
  if spot
    win.webContents.sendInputEvent {type: 'mouseDown', x: spot.x, y: spot.y, button: 'left', clickCount: 1}
    win.webContents.sendInputEvent {type: 'mouseUp',   x: spot.x, y: spot.y, button: 'left', clickCount: 1}
  clicked = await until_ -> p = await promptNow(); p if p.value isnt 'noisy.'
  check 'a click takes a name and leaves the prompt focused',
    clicked?.value is 'noisy.alphaTwo' and clicked.focused and not (await listNow()).open, JSON.stringify {spot, clicked}

  # More than fit on a line open the list on the first Tab, with no beep.
  # It sits between the header and the line being typed, and still does
  # after the window's size changes -- by zoom, which resizes the page in
  # CSS pixels as a resize does: the test window is minimised on Linux and
  # never shown on macOS, and whether a setSize reaches the page then has
  # not been measured. At 4x the room above the prompt is less than the
  # list's own most, so a list sized only when it opened would rise past
  # the top of the window. A window that small takes room from the panels
  # (reflowPanels) and does not give it back, so they are put back as they
  # were, stored sizes and all, for the checks after this one.
  placed = -> js """
    const list   = document.getElementById('completions')?.getBoundingClientRect() ?? {}
    const header = document.querySelector('header').getBoundingClientRect()
    const line   = document.getElementById('promptLine').getBoundingClientRect()
    return {open: document.getElementById('completions')?.hidden === false, top: list.top, bottom: list.bottom,
            header: header.bottom, line: line.top, height: innerHeight}
  """
  inPlace = (at) -> at.open and at.top >= at.header - 1 and at.bottom <= at.line + 1 and at.bottom - at.top > 10
  many = await tab 'Math.'
  manyList = await listNow()
  normal = await placed()
  layout = await js """
    return {editor: Panels.size('editor'), console: Panels.size('console'),
            stored: ['panel.editor', 'panel.console'].map((key) => localStorage.getItem(key))}
  """
  win.webContents.setZoomFactor 4
  # Until it is in place, not just until the page has shrunk: the page
  # learns its new size at once, and runs resize handlers only at its next
  # rendering update.
  zoomed = await until_ -> at = await placed(); at if at.height < normal.height / 2 and inPlace at
  zoomed ?= await placed()
  win.webContents.setZoomFactor 1
  await until_ -> (await placed()).height is normal.height
  await js """
    Panels.set('editor', #{layout.editor})
    Panels.set('console', #{layout.console})
    const stored = #{JSON.stringify layout.stored}
    ;['panel.editor', 'panel.console'].forEach((key, i) =>
      stored[i] === null ? localStorage.removeItem(key) : localStorage.setItem(key, stored[i]))
    return true
  """
  check 'too many names for one line open the list on the first Tab, without a beep',
    many.beeped is 0 and manyList?.open and 'hypot' in manyList.names and many.value is 'Math.',
    JSON.stringify {many, names: manyList?.names.length}
  check 'the list sits between the header and the prompt line, and still does after a resize',
    inPlace(normal) and zoomed.height < normal.height / 2 and inPlace(zoomed), JSON.stringify {normal, zoomed}

  # Down past the rows the list has room for keeps the chosen one in sight.
  await press 'Escape'
  await tab 'Math.'
  await press ('Down' for [1..25])...
  scrolled = await js """
    const list = document.getElementById('completions')
    const box  = list.getBoundingClientRect()
    const row  = list.querySelector('.chosen')?.getBoundingClientRect()
    return {open: !list.hidden, taller: list.scrollHeight > list.clientHeight,
            chosen: [...list.children].findIndex((row) => row.classList.contains('chosen')),
            inside: !!row && row.top >= box.top - 1 && row.bottom <= box.bottom + 1}
  """
  await press 'Escape'
  check 'Down past the rows in sight scrolls the chosen one into view',
    scrolled.open and scrolled.taller and scrolled.chosen is 25 and scrolled.inside, JSON.stringify scrolled

  # Never with a reverse search: Ctrl-R closes the list, and a Tab answered
  # once a search has begun does not open one over it. The sketch answers
  # only while space is held, so the answer comes after the search starts.
  await press 'C-r'
  searched = {list: await listNow(), prompt: await promptNow()}
  await press 'Escape'
  await setDoc """
gate = 1
loop
  null until keys.down 'space'
  buffer.swap
"""
  await wait 500
  await evalAll()
  await until_ -> (await status()) is 'running'
  await promptAt 'Math.', 5
  await press 'Tab'
  out = await js "return Prompt.pending()"
  await press 'C-r'
  await stageKey 'keydown', 'Space'
  await until_ -> not await js "return Prompt.pending()"
  await stageKey 'keyup', 'Space'
  during = {out, list: await listNow(), prompt: await promptNow()}
  await press 'Escape'
  check 'Ctrl-R closes the list, and a Tab answered during a search does not open one',
    searched.list? and not searched.list.open and searched.prompt.mark is 'bck-i-search: _' and
      out and not during.list.open and during.prompt.mark is 'bck-i-search: _' and during.prompt.value is 'Math.',
    JSON.stringify {searched, during}

  await click 'stop'
  await settle()

  # Esc closes a list that is waiting, hidden, for the names after a dot,
  # and they do not open it when they come. The sketch answers until x is
  # pressed and then says it has stopped answering, so the dot's question
  # is certain to wait -- until space lets it answer again.
  await setDoc """
noisy = alphaOne: 1, betaOne: 1
noisyToo = 1
loop
  buffer.swap
  break if keys.down 'x'
print 'parked'
null until keys.down 'space'
loop
  buffer.swap
"""
  await wait 500
  await clearConsole()
  await evalAll()
  await until_ -> (await status()) is 'running'
  await openNoisy 'nois'
  both = await listNow()
  await stageKey 'keydown', 'KeyX'
  parked = await until_ -> (await consoleText()).includes 'parked'
  await stageKey 'keyup', 'KeyX'
  await typeText '.'
  waiting = {list: await listNow(), out: await js "return Prompt.pending()"}
  await press 'Escape'
  await stageKey 'keydown', 'Space'
  await until_ -> not await js "return Prompt.pending()"
  await stageKey 'keyup', 'Space'
  after = await listNow()
  check 'Esc closes a list waiting for its names, and they do not open it when they come',
    both?.open and parked and waiting.out and not waiting.list.open and after? and not after.open and
      (await promptNow()).value is 'noisy.', JSON.stringify {both, parked, waiting, after}
  await click 'stop'
  await settle()
  await setDoc ''
